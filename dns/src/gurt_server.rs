mod auth_routes;
mod helpers;
mod models;
mod routes;
mod ca;

use crate::{auth::jwt_middleware_gurt, config::Config, discord_bot};
use colored::Colorize;
use macros_rs::fmt::{crashln, string};
use std::{sync::Arc, collections::HashMap};
use gurtlib::prelude::*;
use warp::Filter;
use gurtlib::{GurtStatusCode, Route};

#[derive(Debug)]
struct CertificateError;
impl warp::reject::Reject for CertificateError {}

#[derive(Clone)]
pub(crate) struct AppState {
    config: Config,
    db: sqlx::PgPool,
    jwt_secret: String,
}

impl AppState {
    pub fn new(config: Config, db: sqlx::PgPool, jwt_secret: String) -> Self {
        Self {
            config,
            db,
            jwt_secret,
        }
    }
}

#[derive(Clone)]
pub(crate) struct RateLimitState {
    limits: Arc<tokio::sync::RwLock<HashMap<String, Vec<chrono::DateTime<chrono::Utc>>>>>,
}

impl RateLimitState {
    pub fn new() -> Self {
        Self {
            limits: Arc::new(tokio::sync::RwLock::new(HashMap::new())),
        }
    }

    pub async fn check_rate_limit(&self, key: &str, window_secs: i64, max_requests: usize) -> bool {
        let mut limits = self.limits.write().await;
        let now = chrono::Utc::now();
        let window_start = now - chrono::Duration::seconds(window_secs);

        let entry = limits.entry(key.to_string()).or_insert_with(Vec::new);
        
        entry.retain(|&timestamp| timestamp > window_start);
        
        if entry.len() >= max_requests {
            false
        } else {
            entry.push(now);
            true
        }
    }
}

struct AppHandler {
    app_state: AppState,
    rate_limit_state: Option<RateLimitState>,
    handler_type: HandlerType,
}

// Macro to reduce JWT middleware duplication
macro_rules! handle_authenticated {
    ($ctx:expr, $app_state:expr, $handler:expr) => {
        match jwt_middleware_gurt(&$ctx, &$app_state.jwt_secret).await {
            Ok(claims) => $handler(&$ctx, $app_state, claims).await,
            Err(e) => Ok(GurtResponse::new(GurtStatusCode::Unauthorized)
                .with_string_body(&format!("Authentication failed: {}", e))),
        }
    };
}

#[derive(Clone, Debug)]
enum HandlerType {
    Index,
    GetDomain,
    GetDomains, 
    GetTlds,
    CheckDomain,
    Register,
    Login,
    GetUserInfo,
    CreateInvite,
    RedeemInvite,
    CreateDomainInvite,
    RedeemDomainInvite,
    CreateDomain,
    UpdateDomain,
    DeleteDomain,
    GetUserDomains,
    CreateDomainRecord,
    ResolveDomain,
    ResolveFullDomain,
    VerifyDomainOwnership,
    RequestCertificate,
    GetCertificate,
    GetCaCertificate,
    StaticFile,
}

impl GurtHandler for AppHandler {
    fn handle(&self, ctx: &ServerContext) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<GurtResponse>> + Send + '_>> {
        let app_state = self.app_state.clone();
        let rate_limit_state = self.rate_limit_state.clone();
        let handler_type = self.handler_type.clone();
        
        let ctx_data = (
            ctx.remote_addr,
            ctx.request.clone(),
        );
        
        Box::pin(async move {
            let start_time = std::time::Instant::now();
            let ctx = ServerContext {
                remote_addr: ctx_data.0,
                request: ctx_data.1,
            };
            
            log::info!("Handler started for {} {} from {}", ctx.method(), ctx.path(), ctx.remote_addr);
            
            let result = match handler_type {
                HandlerType::Index => routes::index(&ctx, app_state).await,
                HandlerType::GetDomain => {
                    if ctx.path().contains("/records") {
                        handle_authenticated!(ctx, app_state, routes::get_domain_records)
                    } else {
                        handle_authenticated!(ctx, app_state, routes::get_domain)
                    }
                },
                HandlerType::GetDomains => routes::get_domains(&ctx, app_state).await,
                HandlerType::GetTlds => routes::get_tlds(app_state).await,
                HandlerType::CheckDomain => routes::check_domain(&ctx, app_state).await,
                HandlerType::Register => auth_routes::register(&ctx, app_state).await,
                HandlerType::Login => auth_routes::login(&ctx, app_state).await,
                HandlerType::GetUserInfo => handle_authenticated!(ctx, app_state, auth_routes::get_user_info),
                HandlerType::CreateInvite => handle_authenticated!(ctx, app_state, auth_routes::create_invite),
                HandlerType::RedeemInvite => handle_authenticated!(ctx, app_state, auth_routes::redeem_invite),
                HandlerType::CreateDomainInvite => handle_authenticated!(ctx, app_state, auth_routes::create_domain_invite),
                HandlerType::RedeemDomainInvite => handle_authenticated!(ctx, app_state, auth_routes::redeem_domain_invite),
                HandlerType::GetUserDomains => handle_authenticated!(ctx, app_state, routes::get_user_domains),
                HandlerType::CreateDomainRecord => {
                    if ctx.path().contains("/records") {
                        handle_authenticated!(ctx, app_state, routes::create_domain_record)
                    } else {
                        Ok(GurtResponse::new(GurtStatusCode::MethodNotAllowed).with_string_body("Method not allowed"))
                    }
                },
                HandlerType::CreateDomain => {
                    // Check rate limit first
                    if let Some(ref rate_limit_state) = rate_limit_state {
                        let client_ip = ctx.client_ip().to_string();
                        if !rate_limit_state.check_rate_limit(&client_ip, 600, 5).await {
                            return Ok(GurtResponse::new(GurtStatusCode::TooLarge).with_string_body("Rate limit exceeded: 5 requests per 10 minutes"));
                        }
                    }

                    handle_authenticated!(ctx, app_state, routes::create_domain)
                },
                HandlerType::UpdateDomain => handle_authenticated!(ctx, app_state, routes::update_domain),
                HandlerType::DeleteDomain => {
                    if ctx.path().contains("/records/") {
                        handle_authenticated!(ctx, app_state, routes::delete_domain_record)
                    } else {
                        handle_authenticated!(ctx, app_state, routes::delete_domain)
                    }
                },
                HandlerType::ResolveDomain => routes::resolve_domain(&ctx, app_state).await,
                HandlerType::ResolveFullDomain => routes::resolve_full_domain(&ctx, app_state).await,
                HandlerType::VerifyDomainOwnership => routes::verify_domain_ownership(&ctx, app_state).await,
                HandlerType::RequestCertificate => routes::request_certificate(&ctx, app_state).await,
                HandlerType::GetCertificate => routes::get_certificate(&ctx, app_state).await,
                HandlerType::GetCaCertificate => routes::get_ca_certificate(&ctx, app_state).await,
                HandlerType::StaticFile => serve_static_file(&ctx).await,
            };
            
            let duration = start_time.elapsed();
            match &result {
                Ok(response) => {
                    log::info!("Handler completed for {} {} in {:?} - Status: {}", 
                              ctx.method(), ctx.path(), duration, response.status_code);
                },
                Err(e) => {
                    log::error!("Handler failed for {} {} in {:?} - Error: {}", 
                               ctx.method(), ctx.path(), duration, e);
                }
            }
            
            result
        })
    }
}

pub async fn start(cli: crate::Cli) -> std::io::Result<()> {
    let config = Config::new().set_path(&cli.config).read();

    let db = match config.connect_to_db().await {
        Ok(pool) => pool,
        Err(err) => crashln!("Failed to connect to PostgreSQL database.\n{}", string!(err).white()),
    };

    // Start Discord bot
    if !config.discord.bot_token.is_empty() {
        if let Err(e) = discord_bot::start_discord_bot(config.discord.bot_token.clone(), db.clone()).await {
            log::error!("Failed to start Discord bot: {}", e);
        }
    }

    let jwt_secret = config.auth.jwt_secret.clone();
    let app_state = AppState::new(config.clone(), db, jwt_secret);
    let rate_limit_state = RateLimitState::new();

    // Create GURT server
    let mut server = GurtServer::new();
    
    // Load TLS certificates
    if let Err(e) = server.load_tls_certificates(&config.server.cert_path, &config.server.key_path) {
        crashln!("Failed to load TLS certificates: {}", e);
    }

    server = server
        .route(Route::get("/"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::Index })
        .route(Route::get("/domains"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::GetDomains })
        .route(Route::get("/tlds"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::GetTlds })
        .route(Route::get("/check"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::CheckDomain })
        .route(Route::post("/auth/register"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::Register })
        .route(Route::post("/auth/login"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::Login })
        .route(Route::get("/auth/me"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::GetUserInfo })
        .route(Route::post("/auth/invite"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::CreateInvite })
        .route(Route::post("/auth/redeem-invite"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::RedeemInvite })
        .route(Route::post("/auth/create-domain-invite"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::CreateDomainInvite })
        .route(Route::post("/auth/redeem-domain-invite"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::RedeemDomainInvite })
        .route(Route::get("/auth/domains"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::GetUserDomains })
        .route(Route::post("/domain"), AppHandler { app_state: app_state.clone(), rate_limit_state: Some(rate_limit_state), handler_type: HandlerType::CreateDomain })
        .route(Route::get("/domain/*"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::GetDomain })
        .route(Route::post("/domain/*"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::CreateDomainRecord })
        .route(Route::put("/domain/*"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::UpdateDomain })
        .route(Route::delete("/domain/*"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::DeleteDomain })
        .route(Route::post("/resolve"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::ResolveDomain })
        .route(Route::post("/resolve-full"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::ResolveFullDomain })
        .route(Route::get("/verify-ownership/*"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::VerifyDomainOwnership })
        .route(Route::post("/ca/request-certificate"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::RequestCertificate })
        .route(Route::get("/ca/certificate/*"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::GetCertificate })
        .route(Route::get("/ca/root"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::GetCaCertificate })
        .route(Route::get("/register.html"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/signup.html"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/dashboard.html"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/domain.html"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/script.lua"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/register.lua"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/signup.lua"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/dashboard.lua"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/domain.lua"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/clanker.txt"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile })
        .route(Route::get("/search.lua"), AppHandler { app_state: app_state.clone(), rate_limit_state: None, handler_type: HandlerType::StaticFile });

    let http_port = 8876;
    let ca_bootstrap_server = start_ca_bootstrap_server(app_state.clone(), http_port, config.server.address.clone());
    
    log::info!("Starting CA bootstrap HTTP server on {}:{}", config.server.address, http_port);
    log::info!("GURT server listening on {}", config.get_address());
    
    let result = tokio::try_join!(
        ca_bootstrap_server,
        async {
            server.listen(&config.get_address()).await.map_err(|e| {
                std::io::Error::new(std::io::ErrorKind::Other, format!("GURT server error: {}", e))
            })
        }
    );
    
    match result {
        Ok(_) => Ok(()),
        Err(e) => Err(e),
    }
}

async fn start_ca_bootstrap_server(app_state: AppState, port: u16, address: String) -> std::result::Result<(), std::io::Error> {
    let ca_root = warp::path("ca")
        .and(warp::path("root"))
        .and(warp::path::end())
        .and_then({
            let app_state = app_state.clone();
            move || {
                let app_state = app_state.clone();
                async move {
                    match get_ca_certificate_content(&app_state).await {
                        Ok(cert_pem) => {
                            Ok(warp::reply::with_header(
                                cert_pem,
                                "content-type",
                                "application/x-pem-file"
                            ))
                        }
                        Err(e) => {
                            log::error!("Failed to get CA certificate: {}", e);
                            Err(warp::reject::custom(CertificateError))
                        }
                    }
                }
            }
        });
    
    let routes = ca_root
        .with(warp::cors().allow_any_origin().allow_methods(vec!["GET"]));
    
    let addr: std::net::SocketAddr = format!("{}:{}", address, port).parse()
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?;
    
    warp::serve(routes).run(addr).await;
    Ok(())
}

async fn get_ca_certificate_content(app_state: &AppState) -> std::result::Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let query = "SELECT ca_cert_pem FROM ca_certificates WHERE is_active = TRUE ORDER BY created_at DESC LIMIT 1";
    let row: std::result::Result<(String,), _> = sqlx::query_as(query)
        .fetch_one(&app_state.db)
        .await;
    
    match row {
        Ok((ca_cert_pem,)) => Ok(ca_cert_pem),
        Err(e) => {
            log::error!("Failed to retrieve CA certificate from database: {}", e);
            Err(format!("No active CA certificate found in database: {}", e).into())
        }
    }
}

async fn serve_static_file(ctx: &ServerContext) -> Result<GurtResponse> {
    let path = ctx.path();
    
    let host_header = ctx.request.header("host")
        .map(|s| s.as_str())
        .unwrap_or("");
    
    let hostname = host_header.split(':').next().unwrap_or(host_header);
    
    // Strip query parameters from the path for static file serving
    let path_without_query = if let Some(query_pos) = path.find('?') {
        &path[..query_pos]
    } else {
        path
    };
    
    let file_path = if path_without_query == "/" || path_without_query == "" {
        if hostname == "search.web" {
            "search.html"
        } else {
            "index.html"
        }
    } else {
        if path_without_query.starts_with('/') {
            &path_without_query[1..]
        } else {
            path_without_query
        }
    };
    
    if file_path.contains("..") || file_path.contains('/') || file_path.contains('\\') {
        log::warn!("Invalid file path requested: '{}'", file_path);
        return Ok(GurtResponse::new(GurtStatusCode::Forbidden)
            .with_string_body("Invalid file path"));
    }
    
    let current_dir = std::env::current_dir()
        .map_err(|_| GurtError::invalid_message("Failed to get current directory"))?;
    
    let frontend_dir = if hostname == "search.web" {
        current_dir.join("search-engine").join("frontend")
    } else {
        current_dir.join("frontend")
    };
    
    let full_path = frontend_dir.join(file_path);
    
    match tokio::fs::read_to_string(&full_path).await {
        Ok(content) => {
            let content_type = match full_path.extension().and_then(|ext| ext.to_str()) {
                Some("html") => "text/html",
                Some("lua") => "text/plain", 
                Some("txt") => "text/plain",
                Some("js") => "application/javascript",
                Some("css") => "text/css",
                Some("json") => "application/json",
                _ => "text/plain",
            };
            
            Ok(GurtResponse::ok()
                .with_header("Content-Type", content_type)
                .with_string_body(&content))
        }
        Err(e) => {
            log::error!("Failed to read file '{}': {}", full_path.display(), e);
            Ok(GurtResponse::new(GurtStatusCode::NotFound)
                .with_string_body("File not found"))
        }
    }
}