use anyhow::{Result, Context};
use gurtlib::prelude::*;
use gurtlib::GurtError;
use serde_json::json;
use std::sync::Arc;
use tracing::{info, error};

use crate::config::Config;
use crate::indexer::SearchEngine;
use crate::scheduler::BackgroundScheduler;

pub struct SearchServer {
    config: Config,
    search_engine: Arc<SearchEngine>,
}

impl SearchServer {
    pub async fn new(config: Config) -> Result<Self> {
        // Connect to database
        sqlx::PgPool::connect(&config.database_url()).await
            .context("Failed to connect to database")?;

        let search_engine = Arc::new(SearchEngine::new(config.clone())?);

        Ok(Self {
            config,
            search_engine,
        })
    }

    pub async fn run(self) -> Result<()> {
        info!("Starting GURT search server on {}", self.config.server_bind_address());

        let scheduler_config = self.config.clone();
        let _scheduler_handle = BackgroundScheduler::new(scheduler_config).start();
        info!("Background crawler scheduler started");

        let server = GurtServer::with_tls_certificates(
            &self.config.server.cert_path.to_string_lossy(),
            &self.config.server.key_path.to_string_lossy()
        )?;

        let search_engine = self.search_engine.clone();
        let config = self.config.clone();

        let server = server
            .get("/search", {
                let search_engine = search_engine.clone();
                let config = config.clone();
                move |ctx| {
                    let search_engine = search_engine.clone();
                    let config = config.clone();
                    let path = ctx.path().to_string();
                    async move {
                        handle_search(path, search_engine, config).await
                    }
                }
            })
            .get("/api/search*", {
                let search_engine = search_engine.clone();
                let config = config.clone();
                move |ctx| {
                    let search_engine = search_engine.clone();
                    let config = config.clone();
                    
                    let path = ctx.path().to_string();
                    async move {
                        handle_api_search(path, search_engine, config).await
                    }
                }
            })
            .get("/health", |_ctx| async {
                Ok(GurtResponse::ok().with_json_body(&json!({"status": "healthy"}))?)
            })
            .get("/test*", |ctx| {
                let path = ctx.path().to_string();
                async move {
                    println!("Test request path: '{}'", path);
                    Ok(GurtResponse::ok().with_string_body(format!("Path received: {}", path)))
                }
            });

        info!("GURT search server listening on {}", self.config.gurt_protocol_url());
        server.listen(&self.config.server_bind_address()).await.map_err(|e| anyhow::anyhow!("GURT server error: {}", e))
    }
}

pub async fn run_server(config: Config) -> Result<()> {
    let server = SearchServer::new(config).await?;
    server.run().await
}

fn parse_query_param(path: &str, param: &str) -> String {
    let param_with_eq = format!("{}=", param);
    if let Some(start) = path.find(&format!("?{}", param_with_eq)) {
        let start_pos = start + 1 + param_with_eq.len(); // Skip the '?' and 'param='
        let query_part = &path[start_pos..];
        let end_pos = query_part.find('&').unwrap_or(query_part.len());
        urlencoding::decode(&query_part[..end_pos]).unwrap_or_default().to_string()
    } else if let Some(start) = path.find(&format!("&{}", param_with_eq)) {
        let start_pos = start + 1 + param_with_eq.len(); // Skip the '&' and 'param='
        let query_part = &path[start_pos..];
        let end_pos = query_part.find('&').unwrap_or(query_part.len());
        urlencoding::decode(&query_part[..end_pos]).unwrap_or_default().to_string()
    } else {
        String::new()
    }
}

fn parse_query_param_usize(path: &str, param: &str) -> Option<usize> {
    let value = parse_query_param(path, param);
    if value.is_empty() { None } else { value.parse().ok() }
}

async fn handle_search(
    path: String,
    search_engine: Arc<SearchEngine>,
    config: Config
) -> Result<GurtResponse, GurtError> {
    let query = parse_query_param(&path, "q");
    
    if query.is_empty() {
        return Ok(GurtResponse::bad_request()
            .with_json_body(&json!({"error": "Query parameter 'q' is required"}))?);
    }

    println!("Search query: '{}'", query);

    let limit = parse_query_param_usize(&path, "limit")
        .unwrap_or(config.search.search_results_per_page)
        .min(config.search.max_search_results);

    match search_engine.search(&query, limit).await {
        Ok(results) => {
            let response = json!({
                "query": query,
                "results": results,
                "count": results.len()
            });
            
            Ok(GurtResponse::ok()
                .with_header("content-type", "application/json")
                .with_json_body(&response)?)
        }
        Err(e) => {
            error!("Search failed: {}", e);
            Ok(GurtResponse::internal_server_error()
                .with_json_body(&json!({"error": "Search failed", "details": e.to_string()}))?)
        }
    }
}

async fn handle_api_search(
    path: String, 
    search_engine: Arc<SearchEngine>,
    config: Config
) -> Result<GurtResponse, GurtError> {
    let query = parse_query_param(&path, "q");
    
    if query.is_empty() {
        return Ok(GurtResponse::bad_request()
            .with_json_body(&json!({"error": "Query parameter 'q' is required"}))?);
    }

    let page = parse_query_param_usize(&path, "page")
        .unwrap_or(1)
        .max(1);

    let per_page = parse_query_param_usize(&path, "per_page")
        .unwrap_or(config.search.search_results_per_page)
        .min(config.search.max_search_results);

    match search_engine.search_with_response(&query, page, per_page).await {
        Ok(response) => {
            Ok(GurtResponse::ok()
                .with_header("content-type", "application/json")
                .with_json_body(&response)?)
        }
        Err(e) => {
            error!("API search failed: {}", e);
            Ok(GurtResponse::internal_server_error()
                .with_json_body(&json!({"error": "Search failed", "details": e.to_string()}))?)
        }
    }
}
