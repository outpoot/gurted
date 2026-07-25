use anyhow::{Result, Context};
use chrono::{DateTime, Utc};
use std::collections::HashSet;
use std::path::Path;
use std::time::Instant;
use tantivy::schema::{Schema, FAST, INDEXED, STORED, STRING, TEXT};
use tantivy::{doc, Index, IndexReader, IndexWriter, ReloadPolicy, Term, TantivyDocument};
use tantivy::collector::TopDocs;
use tantivy::query::QueryParser;
use tantivy::tokenizer::*;
use tantivy::schema::Value;
use tracing::{info, debug};

use crate::config::Config;
use crate::models::{SearchResult, SearchResponse, IndexStats, CrawledPage};

pub struct SearchEngine {
    config: Config,
    index: Index,
    reader: IndexReader,
    schema: Schema,
}

impl SearchEngine {
    pub fn new(config: Config) -> Result<Self> {
        let index_path = &config.search.index_path;
        
        std::fs::create_dir_all(index_path)
            .with_context(|| format!("Failed to create index directory: {:?}", index_path))?;

        let schema = build_schema();
        
        let index = if index_path.join("meta.json").exists() {
            info!("Loading existing search index from {:?}", index_path);
            Index::open_in_dir(index_path)
                .with_context(|| format!("Failed to open existing index at {:?}", index_path))?
        } else {
            info!("Creating new search index at {:?}", index_path);
            Index::create_in_dir(index_path, schema.clone())
                .with_context(|| format!("Failed to create new index at {:?}", index_path))?
        };

        // Configure tokenizers
        let tokenizer_manager = index.tokenizers();
        tokenizer_manager.register(
            "gurted_text",
            TextAnalyzer::builder(SimpleTokenizer::default())
                .filter(RemoveLongFilter::limit(40))
                .filter(LowerCaser)
                .filter(StopWordFilter::new(Language::English).unwrap())
                .build(),
        );

        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::OnCommitWithDelay)
            .try_into()
            .context("Failed to create index reader")?;

        Ok(Self {
            config,
            index,
            reader,
            schema,
        })
    }

    pub async fn index_pages(&self, pages: Vec<CrawledPage>) -> Result<usize> {
        if pages.is_empty() {
            return Ok(0);
        }

        let start_time = Instant::now();
        let mut writer = self.get_writer()?;
        let mut indexed_count = 0;
        let mut duplicate_count = 0;

        let url_field = self.schema.get_field("url").unwrap();
        let title_field = self.schema.get_field("title").unwrap();
        let content_field = self.schema.get_field("content").unwrap();
        let preview_field = self.schema.get_field("preview").unwrap();
        let domain_field = self.schema.get_field("domain").unwrap();
        let indexed_at_field = self.schema.get_field("indexed_at").unwrap();
        let content_hash_field = self.schema.get_field("content_hash").unwrap();
        let icon_field = self.schema.get_field("icon").unwrap();
        let description_field = self.schema.get_field("description").unwrap();
        let is_online_field = self.schema.get_field("is_online").unwrap();

        info!("Indexing {} pages...", pages.len());

        for page in pages {
            // Check for duplicates (always enabled)
            if let Ok(existing_hash) = self.get_document_hash(&page.url).await {
                if existing_hash == page.content_hash {
                    duplicate_count += 1;
                    continue;
                }
            }

            // Remove existing document for this URL
            let url_term = Term::from_field_text(url_field, &page.url);
            writer.delete_term(url_term);

            let preview = page.generate_preview(500);
            let title = page.title.unwrap_or_else(|| extract_title_from_content(&page.content));

            // Add new document
            writer.add_document(doc!(
                url_field => page.url.clone(),
                title_field => title,
                content_field => page.content.clone(),
                preview_field => preview,
                domain_field => page.domain.clone(),
                indexed_at_field => page.indexed_at.timestamp(),
                content_hash_field => page.content_hash.clone(),
                icon_field => page.icon.unwrap_or_default(),
                description_field => page.description.unwrap_or_default(),
                is_online_field => 1i64
            ))?;

            indexed_count += 1;

            // Commit in batches
            if indexed_count % 100 == 0 {
                writer.commit()
                    .context("Failed to commit batch of documents")?;
                writer = self.get_writer()?; // Get new writer after commit
                
                let elapsed = start_time.elapsed().as_secs_f64();
                let rate = indexed_count as f64 / elapsed;
                info!("Indexed {} pages ({:.1} pages/sec)", indexed_count, rate);
            }
        }

        // Final commit
        writer.commit().context("Failed to commit final batch")?;

        let total_time = start_time.elapsed();
        info!(
            "Indexing completed: {} pages indexed, {} duplicates skipped in {:.2}s",
            indexed_count,
            duplicate_count,
            total_time.as_secs_f64()
        );

        Ok(indexed_count)
    }

    pub async fn search(&self, query: &str, limit: usize) -> Result<Vec<SearchResult>> {
        let start_time = Instant::now();
        let searcher = self.reader.searcher();
        
        let url_field = self.schema.get_field("url").unwrap();
        let title_field = self.schema.get_field("title").unwrap();
        let content_field = self.schema.get_field("content").unwrap();
        let preview_field = self.schema.get_field("preview").unwrap();
        let domain_field = self.schema.get_field("domain").unwrap();
        let indexed_at_field = self.schema.get_field("indexed_at").unwrap();
        let icon_field = self.schema.get_field("icon").unwrap();
        let description_field = self.schema.get_field("description").unwrap();
        let is_online_field = self.schema.get_field("is_online").unwrap();

        // Create query parser for title and content fields
        let query_parser = QueryParser::for_index(
            &self.index, 
            vec![title_field, content_field]
        );

        let parsed_query = query_parser
            .parse_query(query)
            .with_context(|| format!("Failed to parse query: {}", query))?;

        let top_docs = searcher
            .search(&parsed_query, &TopDocs::with_limit(limit))
            .context("Search query execution failed")?;

        let mut results = Vec::new();

        for (score, doc_address) in top_docs {
            let doc: TantivyDocument = searcher.doc(doc_address)?;
            
            let url = doc.get_first(url_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let title = doc.get_first(title_field)
                .and_then(|v| v.as_str())
                .unwrap_or("Untitled")
                .to_string();

            let preview = doc.get_first(preview_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let domain = doc.get_first(domain_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let indexed_at_timestamp = doc.get_first(indexed_at_field)
                .and_then(|v| v.as_i64())
                .unwrap_or(0);

            let indexed_at = DateTime::from_timestamp(indexed_at_timestamp, 0)
                .unwrap_or_else(|| Utc::now());

            let icon = doc.get_first(icon_field)
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string());

            let description = doc.get_first(description_field)
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string());

            let is_online = doc.get_first(is_online_field)
                .and_then(|v| v.as_i64())
                .map(|v| v != 0)
                .unwrap_or(true);

            results.push(SearchResult {
                url,
                title,
                preview,
                domain,
                score,
                indexed_at,
                icon,
                description,
                is_online,
            });
        }

        let search_time = start_time.elapsed();
        debug!(
            "Search completed: {} results for '{}' in {:.2}ms",
            results.len(),
            query,
            search_time.as_millis()
        );

        Ok(results)
    }

    pub async fn search_with_response(&self, query: &str, page: usize, per_page: usize) -> Result<SearchResponse> {
        let offset = page.saturating_sub(1) * per_page;
        let limit = std::cmp::min(per_page, self.config.search.max_search_results);

        let all_results = self.search(query, offset + limit).await?;
        let results = all_results.into_iter().skip(offset).take(per_page).collect();
        let total_results = self.get_total_document_count().await?;

        Ok(SearchResponse {
            query: query.to_string(),
            results,
            total_results,
            page,
            per_page,
        })
    }

    pub async fn get_stats(&self) -> Result<IndexStats> {
        let searcher = self.reader.searcher();
        let total_documents = searcher.num_docs() as usize;

        // Count unique domains (simplified approach)
        let domains: HashSet<String> = HashSet::new();
        // TODO: Implement domain counting when needed

        let total_domains = domains.len();

        // Calculate index size
        let index_size_mb = calculate_directory_size(&self.config.search.index_path)?;

        // Get last update time (approximate)
        let last_updated = get_index_last_modified(&self.config.search.index_path)?;

        Ok(IndexStats {
            total_documents,
            total_domains,
            index_size_mb,
            last_updated,
        })
    }

    pub async fn get_total_document_count(&self) -> Result<usize> {
        let searcher = self.reader.searcher();
        Ok(searcher.num_docs() as usize)
    }

    async fn get_document_hash(&self, url: &str) -> Result<String> {
        let searcher = self.reader.searcher();
        let url_field = self.schema.get_field("url").unwrap();
        let content_hash_field = self.schema.get_field("content_hash").unwrap();
        
        let query_parser = QueryParser::for_index(&self.index, vec![url_field]);
        let query = query_parser.parse_query(&format!("\"{}\"", url))?;
        
        let top_docs = searcher.search(&query, &TopDocs::with_limit(1))?;
        
        if let Some((_, doc_address)) = top_docs.first() {
            let doc: TantivyDocument = searcher.doc(*doc_address)?;
            if let Some(hash_value) = doc.get_first(content_hash_field) {
                if let Some(hash_str) = hash_value.as_str() {
                    return Ok(hash_str.to_string());
                }
            }
        }
        
        Err(anyhow::anyhow!("Document not found: {}", url))
    }

    fn get_writer(&self) -> Result<IndexWriter> {
        self.index
            .writer_with_num_threads(4, 256 * 1024 * 1024) // 256MB buffer
            .context("Failed to create index writer")
    }
}

pub async fn rebuild_index(config: Config) -> Result<()> {
    info!("Starting index rebuild...");
    
    // Remove existing index
    if config.search.index_path.exists() {
        std::fs::remove_dir_all(&config.search.index_path)
            .context("Failed to remove existing index")?;
    }

    // Create new search engine (which will create a new index)
    let _search_engine = SearchEngine::new(config)?;
    
    info!("Index rebuild completed - new empty index created");
    info!("Run a crawl to populate the index with content");
    
    Ok(())
}

fn build_schema() -> Schema {
    let mut schema_builder = Schema::builder();

    schema_builder.add_text_field("url", STRING | STORED | FAST);
    schema_builder.add_text_field("title", TEXT | STORED);
    schema_builder.add_text_field("content", TEXT);
    schema_builder.add_text_field("preview", STRING | STORED);
    schema_builder.add_text_field("domain", STRING | STORED | FAST);
    schema_builder.add_i64_field("indexed_at", INDEXED | STORED | FAST);
    schema_builder.add_text_field("content_hash", STRING | STORED);
    schema_builder.add_text_field("icon", STRING | STORED);
    schema_builder.add_text_field("description", STRING | STORED);
    schema_builder.add_i64_field("is_online", INDEXED | STORED | FAST);

    schema_builder.build()
}

fn extract_title_from_content(content: &str) -> String {
    // Try to extract title from HTML content
    let document = scraper::Html::parse_document(content);
    let title_selector = scraper::Selector::parse("title").unwrap();
    if let Some(title_element) = document.select(&title_selector).next() {
        let title = title_element.text().collect::<Vec<_>>().join(" ");
        if !title.trim().is_empty() {
            return title.trim().to_string();
        }
    }

    // Fallback to h1
    let h1_selector = scraper::Selector::parse("h1").unwrap();
    if let Some(h1_element) = document.select(&h1_selector).next() {
        let h1_text = h1_element.text().collect::<Vec<_>>().join(" ");
        if !h1_text.trim().is_empty() {
            return h1_text.trim().to_string();
        }
    }

    // Fallback to first line of content
    content.lines()
        .find(|line| !line.trim().is_empty())
        .unwrap_or("Untitled")
        .trim()
        .to_string()
}

fn calculate_directory_size(path: &Path) -> Result<f64> {
    let mut total_size = 0u64;
    
    if path.is_dir() {
        for entry in std::fs::read_dir(path)? {
            let entry = entry?;
            let metadata = entry.metadata()?;
            if metadata.is_file() {
                total_size += metadata.len();
            } else if metadata.is_dir() {
                total_size += (calculate_directory_size(&entry.path())? * 1024.0 * 1024.0) as u64;
            }
        }
    }
    
    Ok(total_size as f64 / 1024.0 / 1024.0) // Convert to MB
}

fn get_index_last_modified(path: &Path) -> Result<DateTime<Utc>> {
    let meta_path = path.join("meta.json");
    
    if meta_path.exists() {
        let metadata = std::fs::metadata(meta_path)?;
        let modified = metadata.modified()?;
        let datetime = DateTime::<Utc>::from(modified);
        Ok(datetime)
    } else {
        Ok(Utc::now())
    }
}