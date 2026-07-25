use serde::{Deserialize, Serialize};
use sqlx::{FromRow, types::chrono::{DateTime, Utc}};

#[derive(Clone, Debug, Deserialize, Serialize, FromRow)]
pub struct Domain {
    pub id: i32,
    pub name: String,
    pub tld: String,
    pub user_id: Option<i32>,
    pub status: Option<String>,
    pub created_at: Option<DateTime<Utc>>,
}

impl Domain {
    pub fn full_domain(&self) -> String {
        format!("{}.{}", self.name, self.tld)
    }

    pub fn gurt_url(&self) -> String {
        format!("gurt://{}.{}", self.name, self.tld)
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, FromRow)]
pub struct DnsRecord {
    pub id: i32,
    pub domain_id: i32,
    pub record_type: String,
    pub name: String,
    pub value: String,
    pub ttl: Option<i32>,
    pub priority: Option<i32>,
    pub created_at: Option<DateTime<Utc>>,
}

#[derive(Clone, Debug, Serialize)]
pub struct SearchResult {
    pub url: String,
    pub title: String,
    pub preview: String,
    pub domain: String,
    pub score: f32,
    pub indexed_at: DateTime<Utc>,
    pub icon: Option<String>,
    pub description: Option<String>,
    pub is_online: bool,
}

#[derive(Clone, Debug, Serialize)]
pub struct SearchResponse {
    pub query: String,
    pub results: Vec<SearchResult>,
    pub total_results: usize,
    pub page: usize,
    pub per_page: usize,
}

#[derive(Clone, Debug, Serialize)]
pub struct IndexStats {
    pub total_documents: usize,
    pub total_domains: usize,
    pub index_size_mb: f64,
    pub last_updated: DateTime<Utc>,
}

#[derive(Clone, Debug)]
pub struct CrawledPage {
    pub url: String,
    pub domain: String,
    pub title: Option<String>,
    pub content: String,
    pub content_hash: String,
    pub indexed_at: DateTime<Utc>,
    pub icon: Option<String>,
    pub description: Option<String>,
}

impl CrawledPage {
    pub fn generate_preview(&self, max_len: usize) -> String {
        let text = self.content.trim();
        if text.len() <= max_len {
            text.to_string()
        } else {
            let mut preview = text.chars().take(max_len).collect::<String>();
            if let Some(last_space) = preview.rfind(' ') {
                preview.truncate(last_space);
            }
            preview.push_str("...");
            preview
        }
    }
}

#[derive(Clone)]
pub struct DomainRepository {
    pool: sqlx::PgPool,
}

impl DomainRepository {
    pub fn new(pool: sqlx::PgPool) -> Self {
        Self { pool }
    }

    pub async fn get_domains_for_crawling(&self, limit: Option<i32>) -> Result<Vec<Domain>, sqlx::Error> {
        let query = if let Some(limit) = limit {
            sqlx::query_as::<_, Domain>(
                "SELECT d.id, d.name, d.tld, d.user_id, d.status, d.created_at 
                 FROM domains d
                 LEFT JOIN domain_crawl_status dcs ON d.id = dcs.domain_id
                 WHERE d.status = 'approved' 
                 AND (dcs.crawl_status IS NULL 
                      OR (dcs.crawl_status = 'completed' AND dcs.next_crawl_at <= NOW())
                      OR (dcs.crawl_status = 'failed' AND dcs.next_crawl_at <= NOW())
                      OR (dcs.crawl_status = 'pending' AND dcs.next_crawl_at <= NOW()))
                 ORDER BY COALESCE(dcs.last_crawled_at, '1970-01-01'::timestamptz) ASC
                 LIMIT $1"
            )
            .bind(limit)
        } else {
            sqlx::query_as::<_, Domain>(
                "SELECT d.id, d.name, d.tld, d.user_id, d.status, d.created_at 
                 FROM domains d
                 LEFT JOIN domain_crawl_status dcs ON d.id = dcs.domain_id
                 WHERE d.status = 'approved' 
                 AND (dcs.crawl_status IS NULL 
                      OR (dcs.crawl_status = 'completed' AND dcs.next_crawl_at <= NOW())
                      OR (dcs.crawl_status = 'failed' AND dcs.next_crawl_at <= NOW())
                      OR (dcs.crawl_status = 'pending' AND dcs.next_crawl_at <= NOW()))
                 ORDER BY COALESCE(dcs.last_crawled_at, '1970-01-01'::timestamptz) ASC"
            )
        };
        
        query.fetch_all(&self.pool).await
    }

    pub async fn update_crawl_status(
        &self, 
        domain_id: i32, 
        status: &str, 
        error_message: Option<&str>,
        pages_found: Option<i32>,
        next_crawl_hours: Option<i64>
    ) -> Result<(), sqlx::Error> {
        let next_crawl_at = next_crawl_hours
            .map(|hours| chrono::Utc::now() + chrono::Duration::hours(hours));

        sqlx::query(
            "INSERT INTO domain_crawl_status (domain_id, crawl_status, error_message, pages_found, last_crawled_at, next_crawl_at, updated_at)
             VALUES ($1, $2, $3, $4,
                     CASE WHEN $2 IN ('completed','failed') THEN NOW() ELSE NULL END,
                     $5, NOW())
             ON CONFLICT (domain_id) 
             DO UPDATE SET 
                crawl_status = $2,
                error_message = $3,
                pages_found = CASE WHEN $2 = 'completed'
                                   THEN COALESCE($4, domain_crawl_status.pages_found)
                                   ELSE domain_crawl_status.pages_found END,
                last_crawled_at = CASE WHEN $2 IN ('completed','failed')
                                       THEN NOW()
                                       ELSE domain_crawl_status.last_crawled_at END,
                next_crawl_at = COALESCE($5, domain_crawl_status.next_crawl_at),
                updated_at = NOW()"
        )
        .bind(domain_id)
        .bind(status)
        .bind(error_message)
        .bind(pages_found)
        .bind(next_crawl_at)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, FromRow)]
pub struct CrawlStatus {
    pub domain_id: i32,
    pub last_crawled_at: Option<DateTime<Utc>>,
    pub next_crawl_at: Option<DateTime<Utc>>,
    pub crawl_status: Option<String>,
    pub error_message: Option<String>,
    pub pages_found: Option<i32>,
    pub updated_at: Option<DateTime<Utc>>,
}