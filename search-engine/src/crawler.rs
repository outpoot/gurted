use anyhow::{Result, Context};
use chrono::Utc;
use gurtlib::{GurtClient, GurtClientConfig};
use scraper::{Html, Selector};
use std::collections::{HashSet, VecDeque};
use std::sync::Arc;
use tracing::{info, debug, warn, error};
use url::Url;

use crate::config::Config;
use crate::models::{Domain, DomainRepository, CrawledPage};

#[derive(Debug, Clone)]
struct CrawledPageWithHtml {
    crawled_page: CrawledPage,
    original_html: String,
}
use crate::indexer::SearchEngine;

#[derive(Clone)]
pub struct DomainCrawler {
    config: Config,
    gurt_client: GurtClient,
    domain_repo: DomainRepository,
    search_engine: Arc<SearchEngine>,
}

impl DomainCrawler {
    pub async fn new(config: Config, domain_repo: DomainRepository, search_engine: Arc<SearchEngine>) -> Result<Self> {
        // Fetch the Gurted CA certificate from the DNS server
        let ca_cert = Self::fetch_ca_certificate().await
            .context("Failed to fetch Gurted CA certificate")?;
        
        let gurt_config = GurtClientConfig {
            request_timeout: config.crawler_timeout(),
            user_agent: config.search.crawler_user_agent.clone(),
            max_redirects: config.crawler.max_redirects,
            custom_ca_certificates: vec![ca_cert],
            ..Default::default()
        };
        
        let gurt_client = GurtClient::with_config(gurt_config);

        Ok(Self {
            config,
            gurt_client,
            domain_repo,
            search_engine,
        })
    }

    async fn fetch_ca_certificate() -> Result<String> {
        // Use GurtClient's DNS server configuration to build the HTTP URL
        let dns_ip = GurtClientConfig::default().dns_server_ip;
        
        // The HTTP bootstrap server runs on port 8876 (hardcoded in DNS server)
        let http_url = format!("http://{}:8876/ca/root", dns_ip);
        
        let response = reqwest::get(&http_url).await
            .context("Failed to fetch CA certificate from HTTP bootstrap server")?;
            
        if !response.status().is_success() {
            return Err(anyhow::anyhow!("Failed to fetch CA certificate: HTTP {}", response.status()));
        }
        
        let ca_cert = response.text().await
            .context("Failed to read CA certificate response")?;
            
        if ca_cert.trim().is_empty() {
            return Err(anyhow::anyhow!("Received empty CA certificate"));
        }
        
        Ok(ca_cert)
    }

    pub async fn crawl_domain(&self, domain: &Domain) -> Result<CrawlStats> {
        info!("Starting crawl for domain: {}", domain.full_domain());
        
        let start_time = std::time::Instant::now();
        let mut stats = CrawlStats::new();
        
        self.domain_repo
            .update_crawl_status(domain.id, "crawling", None, None, None)
            .await
            .context("Failed to update crawl status to crawling")?;

        let result = self.crawl_domain_internal(domain, &mut stats).await;

        let duration = start_time.elapsed();
        stats.duration_seconds = duration.as_secs();

        match result {
            Ok(()) => {
                info!(
                    "Successfully crawled domain {} - {} pages found, {} indexed in {:.2}s",
                    domain.full_domain(),
                    stats.pages_found,
                    stats.pages_indexed,
                    duration.as_secs_f64()
                );

                self.domain_repo
                    .update_crawl_status(
                        domain.id,
                        "completed",
                        None,
                        Some(stats.pages_found as i32),
                        Some(self.config.search.crawl_interval_hours as i64),
                    )
                    .await
                    .context("Failed to update crawl status to completed")?;
            }
            Err(e) => {
                error!(
                    "Failed to crawl domain {}: {}",
                    domain.full_domain(),
                    e
                );

                self.domain_repo
                    .update_crawl_status(
                        domain.id,
                        "failed",
                        Some(&e.to_string()),
                        Some(stats.pages_found as i32),
                        Some(24),
                    )
                    .await
                    .context("Failed to update crawl status to failed")?;

                return Err(e);
            }
        }

        Ok(stats)
    }

    async fn check_clanker_txt(&self, base_url: &str) -> Result<Vec<String>> {
        let clanker_url = format!("{}/clanker.txt", base_url);
        debug!("Checking clanker.txt at: {}", clanker_url);

        match self.gurt_client.get(&clanker_url).await {
            Ok(response) => {
                if response.status_code == 200 {
                    let content = String::from_utf8_lossy(&response.body);
                    let urls = self.parse_clanker_txt(&content, base_url)?;
                    debug!("Found {} allowed URLs in clanker.txt", urls.len());
                    return Ok(urls);
                }
                // If clanker.txt doesn't exist (404), crawling is allowed
                Ok(vec![])
            }
            Err(_) => {
                // If we can't fetch clanker.txt, assume crawling is allowed
                Ok(vec![])
            }
        }
    }

    fn parse_clanker_txt(&self, content: &str, base_url: &str) -> Result<Vec<String>> {
        let user_agent = &self.config.search.crawler_user_agent;
        let mut disallow_all = false;
        let mut user_agent_matches = false;
        let mut allowed_urls = Vec::new();

        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            if let Some(user_agent_value) = line.to_lowercase().strip_prefix("user-agent:") {
                let current_user_agent = user_agent_value.trim().to_string();
                user_agent_matches = current_user_agent == "*" || current_user_agent.eq_ignore_ascii_case(user_agent);
                continue;
            }

            if user_agent_matches {
                if let Some(path_value) = line.to_lowercase().strip_prefix("disallow:") {
                    let path = path_value.trim();
                    if path == "/" {
                        disallow_all = true;
                        break;
                    }
                } else if let Some(path_value) = line.to_lowercase().strip_prefix("allow:") {
                    let path = path_value.trim();
                    if !path.is_empty() {
                        let full_url = Self::normalize_url(format!("{}{}", base_url, path));
                        debug!("Added allowed URL from clanker.txt: {}", full_url);
                        allowed_urls.push(full_url);
                    }
                }
            }
        }

        if disallow_all {
            Err(anyhow::anyhow!("Crawling disallowed by clanker.txt"))
        } else {
            Ok(allowed_urls)
        }
    }

    async fn crawl_domain_internal(&self, domain: &Domain, stats: &mut CrawlStats) -> Result<()> {
        let base_url = domain.gurt_url();
        let mut visited_urls = HashSet::new();
        let mut queue = VecDeque::new();
        let mut pages_to_index = Vec::new();

        // Check clanker.txt if enabled and get allowed URLs
        let mut clanker_urls = Vec::new();
        if self.config.crawler.clanker_txt {
            match self.check_clanker_txt(&base_url).await {
                Ok(urls) => {
                    clanker_urls = urls;
                    info!("Found {} URLs in clanker.txt for {}", clanker_urls.len(), domain.full_domain());
                },
                Err(e) => {
                    warn!("Clanker.txt check failed for {}: {}", domain.full_domain(), e);
                    return Err(anyhow::anyhow!("Crawling disabled by clanker.txt: {}", e));
                }
            }
        }

        // Start with the root URL
        let normalized_base_url = Self::normalize_url(base_url.clone());
        queue.push_back(CrawlItem {
            url: normalized_base_url,
            depth: 0,
        });
        
        // Add all URLs from clanker.txt to the queue
        for url in clanker_urls {
            let normalized_url = Self::normalize_url(url);
            if !visited_urls.contains(&normalized_url) {
                queue.push_back(CrawlItem {
                    url: normalized_url.clone(),
                    depth: 0, // Treat clanker.txt URLs as root level
                });
                debug!("Added clanker.txt URL to queue: {}", normalized_url);
            }
        }

        while let Some(item) = queue.pop_front() {
            if visited_urls.contains(&item.url) {
                continue;
            }

            if item.depth > self.config.crawler.max_depth {
                debug!("Skipping URL due to depth limit: {}", item.url);
                continue;
            }

            if stats.pages_found >= self.config.search.max_pages_per_domain {
                info!("Reached page limit for domain: {}", domain.full_domain());
                break;
            }

            visited_urls.insert(item.url.clone());
            stats.pages_found += 1;

            // Add crawl delay between requests
            if stats.pages_found > 1 {
                tokio::time::sleep(self.config.crawl_delay()).await;
            }

            match self.crawl_page(&item.url, domain).await {
                Ok(Some(page_with_html)) => {
                    // Extract links if not at max depth
                    if item.depth < self.config.crawler.max_depth {
                        if let Ok(links) = self.extract_links(&page_with_html.original_html, &base_url).await {
                            debug!("Found {} links on {}", links.len(), item.url);
                            for link in links {
                                let normalized_link = Self::normalize_url(link);
                                if self.should_crawl_url(&normalized_link, domain) && !visited_urls.contains(&normalized_link) {
                                    debug!("Adding link to crawl queue: {}", normalized_link);
                                    queue.push_back(CrawlItem {
                                        url: normalized_link,
                                        depth: item.depth + 1,
                                    });
                                }
                            }
                        }
                    }

                    pages_to_index.push(page_with_html.crawled_page);
                    stats.pages_indexed += 1;

                    // Index in batches
                    if pages_to_index.len() >= 50 {
                        let batch = std::mem::take(&mut pages_to_index);
                        self.search_engine.index_pages(batch).await?;
                    }
                }
                Ok(None) => {
                    debug!("Skipped page: {}", item.url);
                    stats.pages_skipped += 1;
                }
                Err(e) => {
                    warn!("Failed to crawl page {}: {}", item.url, e);
                    stats.errors += 1;
                }
            }
        }

        // Index remaining pages
        if !pages_to_index.is_empty() {
            self.search_engine.index_pages(pages_to_index).await?;
        }

        Ok(())
    }

    async fn crawl_page(&self, url: &str, domain: &Domain) -> Result<Option<CrawledPageWithHtml>> {
        debug!("Crawling page: {}", url);

        let response = match self.gurt_client.get(url).await {
            Ok(response) => response,
            Err(e) => {
                return Err(anyhow::anyhow!("Failed to fetch URL: {} - {}", url, e));
            }
        };

        let status_code = response.status_code;
        let content_type = response
            .headers
            .get("content-type")
            .map(|s| s.to_string());

        // Check if we should process this content type
        if let Some(ref ct) = content_type {
            if !self.is_allowed_content_type(ct) {
                debug!("Skipping URL with unsupported content type: {} ({})", url, ct);
                return Ok(None);
            }
        }

        if status_code != 200 {
            return Err(anyhow::anyhow!(
                "HTTP error {}: {}",
                status_code,
                response.status_message
            ));
        }

        let content_bytes = response.body;

        // Check content size limit
        if content_bytes.len() > self.config.content_size_limit_bytes() {
            warn!("Skipping URL due to size limit: {} ({} bytes)", url, content_bytes.len());
            return Ok(None);
        }

        // Convert bytes to string
        let content = String::from_utf8_lossy(&content_bytes);

        // Extract metadata from HTML
        let title = self.extract_title(&content);
        let icon = self.extract_icon(&content, url);
        let description = self.extract_meta_description(&content);
        let cleaned_content = self.clean_content(&content);

        let page = CrawledPageWithHtml {
            crawled_page: CrawledPage {
                url: Self::normalize_url(url.to_string()),
                domain: domain.full_domain(),
                title,
                content: cleaned_content.clone(),
                content_hash: Self::calculate_content_hash(&cleaned_content),
                indexed_at: Utc::now(),
                icon,
                description,
            },
            original_html: content.to_string(),
        };

        Ok(Some(page))
    }

    async fn extract_links(&self, content: &str, base_url: &str) -> Result<Vec<String>> {
        debug!("Extracting links from content length: {} chars", content.len());
        let document = Html::parse_document(content);
        let link_selector = Selector::parse("a[href]").unwrap();
        let base = Url::parse(base_url)?;
        let mut links = Vec::new();
        
        let all_links = document.select(&link_selector).collect::<Vec<_>>();
        debug!("Found {} anchor tags in HTML", all_links.len());

        for element in all_links {
            if let Some(href) = element.value().attr("href") {
                // Skip empty links and fragments
                if href.is_empty() || href.starts_with('#') {
                    continue;
                }

                // Skip mailto, tel, javascript links
                if href.starts_with("mailto:") || href.starts_with("tel:") || href.starts_with("javascript:") {
                    continue;
                }

                // Resolve relative URLs
                match base.join(href) {
                    Ok(absolute_url) => {
                        let url_str = Self::normalize_url(absolute_url.to_string());
                        
                        // Only include GURT protocol URLs for the same domain
                        if url_str.starts_with("gurt://") {
                            if let Ok(parsed) = Url::parse(&url_str) {
                                if let Some(host) = parsed.host_str() {
                                    if let Ok(base_parsed) = Url::parse(base_url) {
                                        if let Some(base_host) = base_parsed.host_str() {
                                            if host == base_host {
                                                links.push(url_str);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Err(e) => {
                        debug!("Failed to resolve URL {}: {}", href, e);
                    }
                }
            }
        }

        // Remove duplicates
        links.sort();
        links.dedup();

        Ok(links)
    }

    fn extract_title(&self, content: &str) -> Option<String> {
        let document = Html::parse_document(content);
        
        // Try <title> tag first
        if let Ok(title_selector) = Selector::parse("title") {
            if let Some(title_element) = document.select(&title_selector).next() {
                let title_text = title_element.text().collect::<Vec<_>>().join(" ").trim().to_string();
                if !title_text.is_empty() {
                    return Some(title_text);
                }
            }
        }

        // Fallback to first <h1>
        if let Ok(h1_selector) = Selector::parse("h1") {
            if let Some(h1_element) = document.select(&h1_selector).next() {
                let h1_text = h1_element.text().collect::<Vec<_>>().join(" ").trim().to_string();
                if !h1_text.is_empty() {
                    return Some(h1_text);
                }
            }
        }

        None
    }

    fn extract_icon(&self, content: &str, base_url: &str) -> Option<String> {
        let document = Html::parse_document(content);
        
        // Try to find icon tag first (custom GURT standard)
        if let Ok(icon_selector) = Selector::parse("icon") {
            if let Some(icon_element) = document.select(&icon_selector).next() {
                if let Some(src) = icon_element.value().attr("src") {
                    return Some(src.to_string());
                }
            }
        }
        
        // Fallback to standard link rel="icon" or link rel="shortcut icon"
        if let Ok(link_selector) = Selector::parse("link[rel~=\"icon\"], link[rel=\"shortcut icon\"]") {
            if let Some(link_element) = document.select(&link_selector).next() {
                if let Some(href) = link_element.value().attr("href") {
                    // Convert relative URLs to absolute
                    if href.starts_with("http") || href.starts_with("gurt") {
                        return Some(href.to_string());
                    } else if let Ok(base) = Url::parse(base_url) {
                        if let Ok(absolute_url) = base.join(href) {
                            return Some(absolute_url.to_string());
                        }
                    }
                }
            }
        }
        
        None
    }

    fn extract_meta_description(&self, content: &str) -> Option<String> {
        let document = Html::parse_document(content);
        
        // Look for meta name="description"
        if let Ok(meta_selector) = Selector::parse("meta[name=\"description\"]") {
            if let Some(meta_element) = document.select(&meta_selector).next() {
                if let Some(content_attr) = meta_element.value().attr("content") {
                    let description = content_attr.trim();
                    if !description.is_empty() {
                        return Some(description.to_string());
                    }
                }
            }
        }
        
        None
    }

    fn clean_content(&self, content: &str) -> String {
        use lol_html::{element, rewrite_str, RewriteStrSettings};

        // First pass: remove script, style, noscript elements
        let settings = RewriteStrSettings {
            element_content_handlers: vec![
                element!("script", |el| {
                    el.remove();
                    Ok(())
                }),
                element!("style", |el| {
                    el.remove();
                    Ok(())
                }),
                element!("noscript", |el| {
                    el.remove();
                    Ok(())
                }),
            ],
            ..RewriteStrSettings::default()
        };

        let cleaned_html = match rewrite_str(content, settings) {
            Ok(html) => html,
            Err(_) => content.to_string(),
        };

        // Second pass: extract text using scraper (already imported)
        let document = Html::parse_document(&cleaned_html);
        let text_content = document.root_element()
            .text()
            .collect::<Vec<_>>()
            .join(" ");

        // Clean up whitespace
        text_content
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
    }

    fn should_crawl_url(&self, url: &str, domain: &Domain) -> bool {
        // Parse the URL
        let parsed_url = match Url::parse(url) {
            Ok(u) => u,
            Err(_) => return false,
        };

        // Must be GURT protocol
        if parsed_url.scheme() != "gurt" {
            return false;
        }

        // Must be same domain
        if let Some(host) = parsed_url.host_str() {
            if host != domain.full_domain() {
                return false;
            }
        } else {
            return false;
        }

        if let Some(path) = parsed_url.path().split('/').last() {
            if let Some(extension) = path.split('.').last() {
                if path.contains('.') && extension != path {
                    if self.config.is_blocked_extension(extension) {
                        return false;
                    }
                    if !self.config.search.allowed_extensions.is_empty() 
                        && !self.config.is_allowed_extension(extension) {
                        return false;
                    }
                }
            }
        }

        true
    }

    fn is_allowed_content_type(&self, content_type: &str) -> bool {
        let ct_lower = content_type.to_lowercase();
        
        if ct_lower.contains("text/html") || ct_lower.contains("application/xhtml") {
            return true;
        }

        if ct_lower.contains("text/plain") {
            return true;
        }

        if ct_lower.contains("text/markdown") || ct_lower.contains("application/json") {
            return true;
        }

        false
    }

    fn normalize_url(url: String) -> String {
        if url.ends_with("/index.html") {
            let without_index = &url[..url.len() - 11]; // Remove "/index.html" (11 chars)
            if without_index.ends_with('/') {
                without_index.to_string()
            } else {
                format!("{}/", without_index)
            }
        } else {
            url
        }
    }

    fn calculate_content_hash(content: &str) -> String {
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(content.as_bytes());
        format!("{:x}", hasher.finalize())
    }
}

pub async fn run_crawl_all(config: Config) -> Result<()> {
    info!("Starting crawl of all registered domains");

    let pool = sqlx::PgPool::connect(&config.database_url()).await
        .context("Failed to connect to database")?;

    let domain_repo = DomainRepository::new(pool);
    let search_engine = Arc::new(SearchEngine::new(config.clone())?);
    let crawler = DomainCrawler::new(config.clone(), domain_repo.clone(), search_engine).await?;

    let domains = domain_repo.get_domains_for_crawling(None).await
        .context("Failed to fetch domains for crawling")?;

    if domains.is_empty() {
        info!("No domains found that need crawling");
        return Ok(());
    }

    info!("Found {} domains to crawl", domains.len());

    let mut total_stats = CrawlStats::new();
    let max_concurrent = config.search.max_concurrent_crawls;

    let semaphore = std::sync::Arc::new(tokio::sync::Semaphore::new(max_concurrent));
    let mut tasks = Vec::new();

    for domain in domains {
        let crawler = Arc::new(crawler.clone());
        let permit = semaphore.clone().acquire_owned().await
            .context("Failed to acquire semaphore permit")?;
        
        let task = tokio::spawn(async move {
            let _permit = permit; // Keep permit alive
            crawler.crawl_domain(&domain).await
        });
        
        tasks.push(task);
    }

    for task in tasks {
        match task.await {
            Ok(Ok(stats)) => {
                total_stats.pages_found += stats.pages_found;
                total_stats.pages_indexed += stats.pages_indexed;
                total_stats.pages_skipped += stats.pages_skipped;
                total_stats.errors += stats.errors;
            }
            Ok(Err(e)) => {
                error!("Crawl task failed: {}", e);
                total_stats.errors += 1;
            }
            Err(e) => {
                error!("Task join error: {}", e);
                total_stats.errors += 1;
            }
        }
    }

    info!(
        "Crawl completed - {} pages found, {} indexed, {} skipped, {} errors",
        total_stats.pages_found,
        total_stats.pages_indexed,
        total_stats.pages_skipped,
        total_stats.errors
    );

    Ok(())
}

#[derive(Debug, Clone)]
struct CrawlItem {
    url: String,
    depth: usize,
}

#[derive(Debug, Clone)]
pub struct CrawlStats {
    pub pages_found: usize,
    pub pages_indexed: usize,
    pub pages_skipped: usize,
    pub errors: usize,
    pub duration_seconds: u64,
}

impl CrawlStats {
    fn new() -> Self {
        Self {
            pages_found: 0,
            pages_indexed: 0,
            pages_skipped: 0,
            errors: 0,
            duration_seconds: 0,
        }
    }
}