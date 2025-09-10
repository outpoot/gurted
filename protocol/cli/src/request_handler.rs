use crate::{
    handlers::{FileHandler, DirectoryHandler, DefaultFileHandler, DefaultDirectoryHandler},
    config::GurtConfig,
    security::SecurityMiddleware,
};
use gurtlib::prelude::*;
use std::path::Path;
use std::sync::Arc;
use tracing;

pub struct RequestHandlerBuilder {
    file_handler: Arc<dyn FileHandler>,
    directory_handler: Arc<dyn DirectoryHandler>,
    base_directory: std::path::PathBuf,
    config: Option<Arc<GurtConfig>>,
}

impl RequestHandlerBuilder {
    pub fn new<P: AsRef<Path>>(base_directory: P) -> Self {
        Self {
            file_handler: Arc::new(DefaultFileHandler),
            directory_handler: Arc::new(DefaultDirectoryHandler),
            base_directory: base_directory.as_ref().to_path_buf(),
            config: None,
        }
    }

    pub fn with_file_handler<H: FileHandler + 'static>(mut self, handler: H) -> Self {
        self.file_handler = Arc::new(handler);
        self
    }

    pub fn with_directory_handler<H: DirectoryHandler + 'static>(mut self, handler: H) -> Self {
        self.directory_handler = Arc::new(handler);
        self
    }

    pub fn with_config(mut self, config: Arc<GurtConfig>) -> Self {
        self.config = Some(config);
        self
    }

    pub fn build(self) -> RequestHandler {
        let security = self.config.as_ref().map(|config| SecurityMiddleware::new(config.clone()));
        
        RequestHandler {
            file_handler: self.file_handler,
            directory_handler: self.directory_handler,
            base_directory: self.base_directory,
            config: self.config,
            security,
        }
    }
}

pub struct RequestHandler {
    file_handler: Arc<dyn FileHandler>,
    directory_handler: Arc<dyn DirectoryHandler>,
    base_directory: std::path::PathBuf,
    config: Option<Arc<GurtConfig>>,
    security: Option<SecurityMiddleware>,
}

impl RequestHandler {
    pub fn builder<P: AsRef<Path>>(base_directory: P) -> RequestHandlerBuilder {
        RequestHandlerBuilder::new(base_directory)
    }

    fn apply_custom_error_page(&self, mut response: GurtResponse) -> GurtResponse {
        if response.status_code >= 400 {
            let custom_content = self.get_custom_error_page(response.status_code)
                .unwrap_or_else(|| self.get_fallback_error_page(response.status_code));
            
            response.body = custom_content.into_bytes();
            response = response.with_header("Content-Type", "text/html");
            tracing::debug!("Applied error page for status {}", response.status_code);
        }
        response
    }

    fn get_custom_error_page(&self, status_code: u16) -> Option<String> {
        if let Some(config) = &self.config {
            if let Some(error_pages) = &config.error_pages {
                error_pages.get_page_content(status_code, &self.base_directory)
            } else {
                None
            }
        } else {
            None
        }
    }

    fn get_fallback_error_page(&self, status_code: u16) -> String {
        let (title, message) = match status_code {
            400 => ("Bad Request", "The request could not be understood by the server."),
            401 => ("Unauthorized", "Authentication is required to access this resource."),
            403 => ("Forbidden", "Access to this resource is denied by server policy."),
            404 => ("Not Found", "The requested resource was not found on this server."),
            405 => ("Method Not Allowed", "The request method is not allowed for this resource."),
            429 => ("Too Many Requests", "You have exceeded the rate limit. Please try again later."),
            500 => ("Internal Server Error", "The server encountered an error processing your request."),
            502 => ("Bad Gateway", "The server received an invalid response from an upstream server."),
            503 => ("Service Unavailable", "The server is temporarily unavailable. Please try again later."),
            504 => ("Gateway Timeout", "The server did not receive a timely response from an upstream server."),
            _ => ("Error", "An error occurred while processing your request."),
        };

        format!(include_str!("../templates/error.html"), status_code, title, status_code, title, message)
    }

    pub fn check_security(&self, ctx: &ServerContext) -> Option<std::result::Result<GurtResponse, GurtError>> {
        if let Some(security) = &self.security {
            let client_ip = ctx.client_ip();
            let method = ctx.method();

            if !security.is_method_allowed(method) {
                tracing::warn!("Method {} not allowed from {}", method, client_ip);
                let response = security.create_method_not_allowed_response()
                    .map(|r| self.apply_global_headers(r));
                return Some(response);
            }

            if !security.check_rate_limit(client_ip) {
                let response = security.create_rate_limit_response()
                    .map(|r| self.apply_global_headers(r));
                return Some(response);
            }

            if !security.check_connection_limit(client_ip) {
                let response = security.create_rate_limit_response()
                    .map(|r| self.apply_global_headers(r));
                return Some(response);
            }
        }

        None
    }

    pub fn register_connection(&self, client_ip: std::net::IpAddr) {
        if let Some(security) = &self.security {
            security.register_connection(client_ip);
        }
    }

    pub fn unregister_connection(&self, client_ip: std::net::IpAddr) {
        if let Some(security) = &self.security {
            security.unregister_connection(client_ip);
        }
    }

    fn is_file_denied(&self, file_path: &Path) -> bool {
        if let Some(config) = &self.config {
            let path_str = file_path.to_string_lossy();
            
            let relative_path = if let Ok(canonical_file) = file_path.canonicalize() {
                if let Ok(canonical_base) = self.base_directory.canonicalize() {
                    canonical_file.strip_prefix(&canonical_base)
                        .map(|p| p.to_string_lossy().to_string())
                        .unwrap_or_else(|_| path_str.to_string())
                } else {
                    path_str.to_string()
                }
            } else {
                path_str.to_string()
            };

            let is_denied = config.should_deny_file(&path_str) || config.should_deny_file(&relative_path);
            
            if is_denied {
                tracing::warn!("File access denied by security policy: {}", relative_path);
            }
            
            is_denied
        } else {
            false
        }
    }

    fn apply_global_headers(&self, mut response: GurtResponse) -> GurtResponse {
        response = self.apply_custom_error_page(response);
        
        if let Some(config) = &self.config {
            if let Some(headers) = &config.headers {
                for (key, value) in headers {
                    response = response.with_header(key, value);
                }
            }
        }
        response
    }

    fn create_forbidden_response(&self) -> std::result::Result<GurtResponse, GurtError> {
        let response = GurtResponse::forbidden()
            .with_header("Content-Type", "text/html");
        
        Ok(self.apply_global_headers(response))
    }

    pub async fn handle_root_request_with_context(&self, ctx: ServerContext) -> std::result::Result<GurtResponse, GurtError> {
        let client_ip = ctx.client_ip();
        
        self.register_connection(client_ip);
        
        if let Some(security_response) = self.check_security(&ctx) {
            self.unregister_connection(client_ip);
            return security_response;
        }
        
        let result = self.handle_root_request().await;
        self.unregister_connection(client_ip);
        result
    }

    pub async fn handle_file_request_with_context(&self, request_path: &str, ctx: ServerContext) -> std::result::Result<GurtResponse, GurtError> {
        let client_ip = ctx.client_ip();
        
        self.register_connection(client_ip);
        
        if let Some(security_response) = self.check_security(&ctx) {
            self.unregister_connection(client_ip);
            return security_response;
        }
        
        let result = self.handle_file_request(request_path).await;
        self.unregister_connection(client_ip);
        result
    }

    pub async fn handle_method_request_with_context(&self, ctx: ServerContext) -> std::result::Result<GurtResponse, GurtError> {
        let client_ip = ctx.client_ip();
        let method = ctx.method();
        
        self.register_connection(client_ip);
        
        if let Some(security_response) = self.check_security(&ctx) {
            self.unregister_connection(client_ip);
            return security_response;
        }
        
        let result = match method {
            gurtlib::message::GurtMethod::GET => {
                if ctx.path() == "/" {
                    self.handle_root_request().await
                } else {
                    self.handle_file_request(ctx.path()).await
                }
            }
            gurtlib::message::GurtMethod::HEAD => {
                let mut response = if ctx.path() == "/" {
                    self.handle_root_request().await?
                } else {
                    self.handle_file_request(ctx.path()).await?
                };
                response.body = Vec::new();
                Ok(response)
            }
            gurtlib::message::GurtMethod::OPTIONS => {
                let allowed_methods = if let Some(config) = &self.config {
                    if let Some(security) = &config.security {
                        security.allowed_methods.join(", ")
                    } else {
                        "GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH".to_string()
                    }
                } else {
                    "GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH".to_string()
                };
                
                let response = GurtResponse::ok()
                    .with_header("Allow", &allowed_methods)
                    .with_header("Content-Type", "text/plain")
                    .with_string_body("Allowed methods");
                Ok(self.apply_global_headers(response))
            }
            _ => {
                let response = GurtResponse::new(gurtlib::protocol::GurtStatusCode::MethodNotAllowed)
                    .with_header("Content-Type", "text/html");
                Ok(self.apply_global_headers(response))
            }
        };
        
        self.unregister_connection(client_ip);
        result
    }

    pub async fn handle_root_request(&self) -> std::result::Result<GurtResponse, GurtError> {
        let index_path = self.base_directory.join("index.html");

        if index_path.exists() && index_path.is_file() {
            if self.is_file_denied(&index_path) {
                return self.create_forbidden_response();
            }

            match self.file_handler.handle_file(&index_path) {
                Ok(content) => {
                    let content_type = self.file_handler.get_content_type(&index_path);
                    let response = GurtResponse::ok()
                        .with_header("Content-Type", &content_type)
                        .with_body(content);
                    return Ok(self.apply_global_headers(response));
                }
                Err(_) => {
                    // fall
                }
            }
        }

        match self.directory_handler.handle_directory(&self.base_directory, "/") {
            Ok(listing) => {
                let response = GurtResponse::ok()
                    .with_header("Content-Type", "text/html")
                    .with_string_body(listing);
                Ok(self.apply_global_headers(response))
            }
            Err(_) => {
                let response = GurtResponse::internal_server_error()
                    .with_header("Content-Type", "text/html");
                Ok(self.apply_global_headers(response))
            }
        }
    }

    pub async fn handle_file_request(&self, request_path: &str) -> std::result::Result<GurtResponse, GurtError> {
        let path_without_query = if let Some(query_start) = request_path.find('?') {
            &request_path[..query_start]
        } else {
            request_path
        };
        
        let mut relative_path = path_without_query.strip_prefix('/').unwrap_or(path_without_query).to_string();
        
        while relative_path.starts_with('/') || relative_path.starts_with('\\') {
            relative_path = relative_path[1..].to_string();
        }
        
        let relative_path = if relative_path.is_empty() { 
            ".".to_string() 
        } else { 
            relative_path 
        };
        
        let file_path = self.base_directory.join(&relative_path);

        if self.is_file_denied(&file_path) {
            return self.create_forbidden_response();
        }

        match file_path.canonicalize() {
            Ok(canonical_path) => {
                let canonical_base = match self.base_directory.canonicalize() {
                    Ok(base) => base,
                    Err(_) => {
                        return Ok(GurtResponse::internal_server_error()
                            .with_header("Content-Type", "text/html"));
                    }
                };

                if !canonical_path.starts_with(&canonical_base) {
                    let response = GurtResponse::bad_request()
                        .with_header("Content-Type", "text/html");
                    return Ok(self.apply_global_headers(response));
                }
                
                if self.is_file_denied(&canonical_path) {
                    return self.create_forbidden_response();
                }
                
                if canonical_path.is_file() {
                    self.handle_file_response(&canonical_path).await
                } else if canonical_path.is_dir() {
                    self.handle_directory_response(&canonical_path, request_path).await
                } else {
                    self.handle_not_found_response().await
                }
            }
            Err(_) => {
                self.handle_not_found_response().await
            }
        }
    }

    async fn handle_file_response(&self, path: &Path) -> std::result::Result<GurtResponse, GurtError> {
        match self.file_handler.handle_file(path) {
            Ok(content) => {
                let content_type = self.file_handler.get_content_type(path);
                let response = GurtResponse::ok()
                    .with_header("Content-Type", &content_type)
                    .with_body(content);
                Ok(self.apply_global_headers(response))
            }
            Err(_) => {
                let response = GurtResponse::internal_server_error()
                    .with_header("Content-Type", "text/html");
                Ok(self.apply_global_headers(response))
            }
        }
    }

    async fn handle_directory_response(&self, canonical_path: &Path, request_path: &str) -> std::result::Result<GurtResponse, GurtError> {
        let index_path = canonical_path.join("index.html");
        if index_path.is_file() {
            self.handle_file_response(&index_path).await
        } else {
            match self.directory_handler.handle_directory(canonical_path, request_path) {
                Ok(listing) => {
                    let response = GurtResponse::ok()
                        .with_header("Content-Type", "text/html")
                        .with_string_body(listing);
                    Ok(self.apply_global_headers(response))
                }
                Err(_) => {
                    let response = GurtResponse::internal_server_error()
                        .with_header("Content-Type", "text/html");
                    Ok(self.apply_global_headers(response))
                }
            }
        }
    }

    async fn handle_not_found_response(&self) -> std::result::Result<GurtResponse, GurtError> {
        let content = self.get_custom_error_page(404)
            .unwrap_or_else(|| crate::handlers::get_404_html().to_string());
        
        let response = GurtResponse::not_found()
            .with_header("Content-Type", "text/html")
            .with_string_body(content);
        Ok(self.apply_global_headers(response))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gurtlib::GurtStatusCode;
    use std::fs;
    use std::env;

    fn create_test_handler() -> RequestHandler {
        let temp_dir = env::temp_dir().join("gurty_request_handler_test");
        let _ = fs::create_dir_all(&temp_dir);
        
        RequestHandler::builder(&temp_dir).build()
    }

    fn create_test_handler_with_config() -> RequestHandler {
        let temp_dir = env::temp_dir().join("gurty_request_handler_test_config");
        let _ = fs::create_dir_all(&temp_dir);
        
        let config = Arc::new(GurtConfig::default());
        RequestHandler::builder(&temp_dir)
            .with_config(config)
            .build()
    }

    #[test]
    fn test_request_handler_builder() {
        let temp_dir = env::temp_dir().join("gurty_builder_test");
        let _ = fs::create_dir_all(&temp_dir);
        
        let handler = RequestHandler::builder(&temp_dir).build();
        
        assert_eq!(handler.base_directory, temp_dir);
        assert!(handler.config.is_none());
        assert!(handler.security.is_none());
        
        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_request_handler_builder_with_config() {
        let temp_dir = env::temp_dir().join("gurty_builder_config_test");
        let _ = fs::create_dir_all(&temp_dir);
        
        let config = Arc::new(GurtConfig::default());
        let handler = RequestHandler::builder(&temp_dir)
            .with_config(config.clone())
            .build();
        
        assert!(handler.config.is_some());
        assert!(handler.security.is_some());
        
        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_fallback_error_page_generation() {
        let handler = create_test_handler();
        
        let error_404 = handler.get_fallback_error_page(404);
        assert!(error_404.contains("404 Not Found"));
        assert!(error_404.contains("not found"));
        
        let error_500 = handler.get_fallback_error_page(500);
        assert!(error_500.contains("500 Internal Server Error"));
        assert!(error_500.contains("processing your request"));
        
        let error_429 = handler.get_fallback_error_page(429);
        assert!(error_429.contains("429 Too Many Requests"));
        assert!(error_429.contains("rate limit"));
    }

    #[test]
    fn test_custom_error_page_with_config() {
        let handler = create_test_handler_with_config();
        
        let result = handler.get_custom_error_page(404);
        assert!(result.is_none());
    }

    #[test]
    fn test_apply_global_headers_without_config() {
        let handler = create_test_handler();
        let response = GurtResponse::ok();
        
        let modified_response = handler.apply_global_headers(response);
        
        assert_eq!(modified_response.status_code, 200);
    }

    #[test]
    fn test_apply_global_headers_with_config() {
        let temp_dir = env::temp_dir().join("gurty_headers_test");
        let _ = fs::create_dir_all(&temp_dir);
        
        let mut config = GurtConfig::default();
        let mut headers = std::collections::HashMap::new();
        headers.insert("X-Test-Header".to_string(), "test-value".to_string());
        config.headers = Some(headers);
        
        let handler = RequestHandler::builder(&temp_dir)
            .with_config(Arc::new(config))
            .build();
        
        let response = GurtResponse::ok();
        let modified_response = handler.apply_global_headers(response);
        
        assert!(modified_response.headers.contains_key("x-test-header"));
        assert_eq!(modified_response.headers.get("x-test-header").unwrap(), "test-value");
        
        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_apply_custom_error_page() {
        let handler = create_test_handler();
        let mut response = GurtResponse::new(GurtStatusCode::NotFound);
        response.body = b"Not Found".to_vec();
        
        let modified_response = handler.apply_custom_error_page(response);
        
        assert!(modified_response.status_code >= 400);
        let body_str = String::from_utf8_lossy(&modified_response.body);
        assert!(body_str.contains("html"));
    }

    #[test]
    fn test_apply_custom_error_page_for_success() {
        let handler = create_test_handler();
        let mut response = GurtResponse::ok();
        response.body = b"Success".to_vec();
        
        let modified_response = handler.apply_custom_error_page(response);
        
        assert_eq!(modified_response.status_code, 200);
        assert_eq!(modified_response.body, b"Success".to_vec());
    }
}
