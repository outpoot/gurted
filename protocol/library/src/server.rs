use crate::{
    GurtError, Result, GurtRequest, GurtResponse, GurtMessage, 
    protocol::{BODY_SEPARATOR, MAX_MESSAGE_SIZE},
    message::GurtMethod,
    protocol::GurtStatusCode,
    crypto::{TLS_VERSION, GURT_ALPN, TlsConfig},
};
use tokio::net::{TcpListener, TcpStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time::Duration;
use tokio_rustls::{TlsAcceptor, server::TlsStream};
use rustls::pki_types::CertificateDer;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::fs;
use tracing::{info, warn, error, debug};

#[derive(Debug, Clone)]
pub struct ServerContext {
    pub remote_addr: SocketAddr,
    pub request: GurtRequest,
}

impl ServerContext {
    pub fn client_ip(&self) -> std::net::IpAddr {
        self.remote_addr.ip()
    }
    
    pub fn client_port(&self) -> u16 {
        self.remote_addr.port()
    }
    
    
    pub fn method(&self) -> &GurtMethod {
        &self.request.method
    }
    
    pub fn path(&self) -> &str {
        &self.request.path
    }
    
    pub fn headers(&self) -> &HashMap<String, String> {
        &self.request.headers
    }
    
    pub fn body(&self) -> &[u8] {
        &self.request.body
    }
    
    pub fn text(&self) -> Result<String> {
        self.request.text()
    }
    
    pub fn header(&self, key: &str) -> Option<&String> {
        self.request.header(key)
    }
}

pub trait GurtHandler: Send + Sync {
    fn handle(&self, ctx: &ServerContext) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<GurtResponse>> + Send + '_>>;
}

pub struct FnHandler<F> {
    handler: F,
}

impl<F, Fut> GurtHandler for FnHandler<F>
where
    F: Fn(&ServerContext) -> Fut + Send + Sync,
    Fut: std::future::Future<Output = Result<GurtResponse>> + Send + 'static,
{
    fn handle(&self, ctx: &ServerContext) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<GurtResponse>> + Send + '_>> {
        Box::pin((self.handler)(ctx))
    }
}

#[derive(Debug, Clone)]
pub struct Route {
    method: Option<GurtMethod>,
    path_pattern: String,
}

impl Route {
    pub fn new(method: Option<GurtMethod>, path_pattern: String) -> Self {
        Self { method, path_pattern }
    }
    
    pub fn get(path: &str) -> Self {
        Self::new(Some(GurtMethod::GET), path.to_string())
    }
    
    pub fn post(path: &str) -> Self {
        Self::new(Some(GurtMethod::POST), path.to_string())
    }
    
    pub fn put(path: &str) -> Self {
        Self::new(Some(GurtMethod::PUT), path.to_string())
    }
    
    pub fn delete(path: &str) -> Self {
        Self::new(Some(GurtMethod::DELETE), path.to_string())
    }
    
    pub fn head(path: &str) -> Self {
        Self::new(Some(GurtMethod::HEAD), path.to_string())
    }
    
    pub fn options(path: &str) -> Self {
        Self::new(Some(GurtMethod::OPTIONS), path.to_string())
    }
    
    pub fn patch(path: &str) -> Self {
        Self::new(Some(GurtMethod::PATCH), path.to_string())
    }
    
    pub fn any(path: &str) -> Self {
        Self::new(None, path.to_string())
    }
    
    pub fn matches(&self, method: &GurtMethod, path: &str) -> bool {
        if let Some(route_method) = &self.method {
            if route_method != method {
                return false;
            }
        }
        
        self.matches_path(path)
    }
    
    pub fn matches_path(&self, path: &str) -> bool {
        // Strip query parameters from path for matching
        let path_without_query = if let Some(query_pos) = path.find('?') {
            &path[..query_pos]
        } else {
            path
        };
        
        self.path_pattern == path_without_query || 
        (self.path_pattern.ends_with('*') && path_without_query.starts_with(&self.path_pattern[..self.path_pattern.len()-1]))
    }
}

pub struct GurtServer {
    routes: Vec<(Route, Arc<dyn GurtHandler>)>,
    tls_acceptor: Option<TlsAcceptor>,
    handshake_timeout: Duration,
    request_timeout: Duration,
    connection_timeout: Duration,
}

impl GurtServer {
    pub fn new() -> Self {
        Self {
            routes: Vec::new(),
            tls_acceptor: None,
            handshake_timeout: Duration::from_secs(5),
            request_timeout: Duration::from_secs(30),
            connection_timeout: Duration::from_secs(10),
        }
    }
    
    pub fn with_timeouts(mut self, handshake_timeout: Duration, request_timeout: Duration, connection_timeout: Duration) -> Self {
        self.handshake_timeout = handshake_timeout;
        self.request_timeout = request_timeout;
        self.connection_timeout = connection_timeout;
        self
    }
    
    pub fn with_tls_certificates(cert_path: &str, key_path: &str) -> Result<Self> {
        let mut server = Self::new();
        server.load_tls_certificates(cert_path, key_path)?;
        Ok(server)
    }
    
    pub fn load_tls_certificates(&mut self, cert_path: &str, key_path: &str) -> Result<()> {
        info!("Loading TLS certificates: cert={}, key={}", cert_path, key_path);
        
        let cert_data = fs::read(cert_path)
            .map_err(|e| GurtError::crypto(format!("Failed to read certificate file '{}': {}", cert_path, e)))?;
        
        let key_data = fs::read(key_path)
            .map_err(|e| GurtError::crypto(format!("Failed to read private key file '{}': {}", key_path, e)))?;
        
        let mut cursor = std::io::Cursor::new(cert_data);
        let certs: Vec<CertificateDer<'static>> = rustls_pemfile::certs(&mut cursor)
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(|e| GurtError::crypto(format!("Failed to parse certificates: {}", e)))?;
        
        if certs.is_empty() {
            return Err(GurtError::crypto("No certificates found in certificate file"));
        }
        
        let mut key_cursor = std::io::Cursor::new(key_data);
        let private_key = rustls_pemfile::private_key(&mut key_cursor)
            .map_err(|e| GurtError::crypto(format!("Failed to parse private key: {}", e)))?
            .ok_or_else(|| GurtError::crypto("No private key found in key file"))?;
        
        let tls_config = TlsConfig::new_server(certs, private_key)?;
        self.tls_acceptor = Some(tls_config.get_acceptor()?);
        
        info!("TLS certificates loaded successfully");
        Ok(())
    }
    
    pub fn route<H>(mut self, route: Route, handler: H) -> Self
    where
        H: GurtHandler + 'static,
    {
        self.routes.push((route, Arc::new(handler)));
        self
    }
    
    pub fn get<F, Fut>(self, path: &str, handler: F) -> Self
    where
        F: Fn(&ServerContext) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<GurtResponse>> + Send + 'static,
    {
        self.route(Route::get(path), FnHandler { handler })
    }
    
    pub fn post<F, Fut>(self, path: &str, handler: F) -> Self
    where
        F: Fn(&ServerContext) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<GurtResponse>> + Send + 'static,
    {
        self.route(Route::post(path), FnHandler { handler })
    }
    
    pub fn put<F, Fut>(self, path: &str, handler: F) -> Self
    where
        F: Fn(&ServerContext) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<GurtResponse>> + Send + 'static,
    {
        self.route(Route::put(path), FnHandler { handler })
    }
    
    pub fn delete<F, Fut>(self, path: &str, handler: F) -> Self
    where
        F: Fn(&ServerContext) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<GurtResponse>> + Send + 'static,
    {
        self.route(Route::delete(path), FnHandler { handler })
    }
    
    pub fn head<F, Fut>(self, path: &str, handler: F) -> Self
    where
        F: Fn(&ServerContext) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<GurtResponse>> + Send + 'static,
    {
        self.route(Route::head(path), FnHandler { handler })
    }
    
    pub fn options<F, Fut>(self, path: &str, handler: F) -> Self
    where
        F: Fn(&ServerContext) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<GurtResponse>> + Send + 'static,
    {
        self.route(Route::options(path), FnHandler { handler })
    }
    
    pub fn patch<F, Fut>(self, path: &str, handler: F) -> Self
    where
        F: Fn(&ServerContext) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<GurtResponse>> + Send + 'static,
    {
        self.route(Route::patch(path), FnHandler { handler })
    }
    
    pub fn any<F, Fut>(self, path: &str, handler: F) -> Self
    where
        F: Fn(&ServerContext) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<GurtResponse>> + Send + 'static,
    {
        self.route(Route::any(path), FnHandler { handler })
    }
    
    pub async fn listen(self, addr: &str) -> Result<()> {
        let listener = TcpListener::bind(addr).await?;
        info!("GURT server listening on {}", addr);
        
        loop {
            match listener.accept().await {
                Ok((stream, addr)) => {
                    info!("Client connected: {}", addr);
                    let server = self.clone();
                    
                    tokio::spawn(async move {
                        if let Err(e) = server.handle_connection(stream, addr).await {
                            error!("Connection error from {}: {}", addr, e);
                        }
                        info!("Client disconnected: {}", addr);
                    });
                }
                Err(e) => {
                    error!("Failed to accept connection: {}", e);
                }
            }
        }
    }
    
    async fn handle_connection(&self, mut stream: TcpStream, addr: SocketAddr) -> Result<()> {
        self.handle_initial_handshake(&mut stream, addr).await?;
        
        if let Some(tls_acceptor) = &self.tls_acceptor {
            info!("Upgrading connection to TLS for {}", addr);
            let tls_stream = tls_acceptor.accept(stream).await
                .map_err(|e| GurtError::crypto(format!("TLS upgrade failed: {}", e)))?;
            
            info!("TLS upgrade completed for {}", addr);
            
            self.handle_tls_connection(tls_stream, addr).await
        } else {
            warn!("No TLS configuration available, but handshake completed - this violates GURT protocol");
            Err(GurtError::protocol("TLS is required after handshake but no TLS configuration available"))
        }
    }
    
    async fn handle_initial_handshake(&self, stream: &mut TcpStream, addr: SocketAddr) -> Result<()> {
        let mut buffer = Vec::new();
        let mut temp_buffer = [0u8; 8192];
        
        loop {
            let bytes_read = stream.read(&mut temp_buffer).await?;
            if bytes_read == 0 {
                return Err(GurtError::connection("Connection closed during handshake"));
            }
            
            buffer.extend_from_slice(&temp_buffer[..bytes_read]);
            
            let body_separator = BODY_SEPARATOR.as_bytes();
            if buffer.windows(body_separator.len()).any(|w| w == body_separator) {
                break;
            }
            
            if buffer.len() > MAX_MESSAGE_SIZE {
                return Err(GurtError::protocol("Handshake message too large"));
            }
        }
        
        let message = GurtMessage::parse_bytes(&buffer)?;
        
        match message {
            GurtMessage::Request(request) => {
                if request.method == GurtMethod::HANDSHAKE {
                    self.send_handshake_response(stream, addr, &request).await
                } else {
                    Err(GurtError::protocol("First message must be HANDSHAKE"))
                }
            }
            GurtMessage::Response(_) => {
                Err(GurtError::protocol("Server received response during handshake"))
            }
        }
    }
    
    async fn handle_tls_connection(&self, mut tls_stream: TlsStream<TcpStream>, addr: SocketAddr) -> Result<()> {
        let mut buffer = Vec::new();
        let mut temp_buffer = [0u8; 8192];
        
        loop {
            let bytes_read = match tls_stream.read(&mut temp_buffer).await {
                Ok(n) => n,
                Err(e) => {
                    if e.kind() == std::io::ErrorKind::UnexpectedEof {
                        debug!("Client {} closed connection without TLS close_notify (benign)", addr);
                        break;
                    }
                    return Err(e.into());
                }
            };
            if bytes_read == 0 {
                break;
            }
            
            buffer.extend_from_slice(&temp_buffer[..bytes_read]);
            
            let body_separator = BODY_SEPARATOR.as_bytes();
            let has_complete_message = buffer.windows(body_separator.len()).any(|w| w == body_separator) ||
                (buffer.starts_with(b"{") && buffer.ends_with(b"}"));
            
            if has_complete_message {
                // Remove timeout wrapper that causes connection aborts
                match self.process_tls_message(&mut tls_stream, addr, &buffer).await {
                    Ok(()) => {
                        debug!("Processed message from {} successfully", addr);
                    }
                    Err(e) => {
                        error!("Encrypted message processing error from {}: {}", addr, e);
                        let error_response = GurtResponse::internal_server_error()
                            .with_string_body("Internal server error");
                        let _ = tls_stream.write_all(&error_response.to_bytes()).await;
                    }
                }
                
                buffer.clear();
            }
            
            if buffer.len() > MAX_MESSAGE_SIZE {
                warn!("Message too large from {}, closing connection", addr);
                break;
            }
        }
        
        Ok(())
    }
    
    async fn send_handshake_response(&self, stream: &mut TcpStream, addr: SocketAddr, _request: &GurtRequest) -> Result<()> {
        info!("Sending handshake response to {}", addr);
        
        let response = GurtResponse::new(GurtStatusCode::SwitchingProtocols)
            .with_header("GURT-Version", crate::GURT_VERSION.to_string())
            .with_header("Encryption", TLS_VERSION)
            .with_header("ALPN", std::str::from_utf8(GURT_ALPN).unwrap_or("GURT/1.0"));
        
        let response_bytes = response.to_string().into_bytes();
        stream.write_all(&response_bytes).await?;
        
        info!("Handshake response sent to {}, preparing for TLS upgrade", addr);
        Ok(())
    }
    
    async fn process_tls_message(&self, tls_stream: &mut TlsStream<TcpStream>, addr: SocketAddr, data: &[u8]) -> Result<()> {
        let message = GurtMessage::parse_bytes(data)?;
        
        match message {
            GurtMessage::Request(request) => {
                if request.method == GurtMethod::HANDSHAKE {
                    Err(GurtError::protocol("Received HANDSHAKE over TLS - protocol violation"))
                } else {
                    self.handle_encrypted_request(tls_stream, addr, &request).await
                }
            }
            GurtMessage::Response(_) => {
                warn!("Received response on server, ignoring");
                Ok(())
            }
        }
    }
    
    async fn handle_default_options(&self, tls_stream: &mut TlsStream<TcpStream>, request: &GurtRequest) -> Result<()> {
        let mut allowed_methods = std::collections::HashSet::new();
        
        for (route, _) in &self.routes {
            if route.matches_path(&request.path) {
                if let Some(method) = &route.method {
                    allowed_methods.insert(method.to_string());
                } else {
                    allowed_methods.extend(vec![
                        "GET".to_string(), "POST".to_string(), "PUT".to_string(),
                        "DELETE".to_string(), "HEAD".to_string(), "PATCH".to_string()
                    ]);
                }
            }
        }
        
        allowed_methods.insert("OPTIONS".to_string());
        
        let mut allowed_methods_vec: Vec<String> = allowed_methods.into_iter().collect();
        allowed_methods_vec.sort();
        let allow_header = allowed_methods_vec.join(", ");
        
        let response = GurtResponse::ok()
            .with_header("Allow", allow_header)
            .with_header("Access-Control-Allow-Origin", "*")
            .with_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH")
            .with_header("Access-Control-Allow-Headers", "Content-Type, Authorization");
        
        tls_stream.write_all(&response.to_bytes()).await?;
        Ok(())
    }
    
    async fn handle_default_head(&self, tls_stream: &mut TlsStream<TcpStream>, addr: SocketAddr, request: &GurtRequest) -> Result<()> {
        for (route, handler) in &self.routes {
            if route.method == Some(GurtMethod::GET) && route.matches(&GurtMethod::GET, &request.path) {
                let context = ServerContext {
                    remote_addr: addr,
                    request: request.clone(),
                };
                
                match handler.handle(&context).await {
                    Ok(mut response) => {
                        let original_content_length = response.body.len();
                        response.body.clear();
                        response = response.with_header("content-length", original_content_length.to_string());
                        
                        tls_stream.write_all(&response.to_bytes()).await?;
                        return Ok(());
                    }
                    Err(e) => {
                        error!("Handler error for HEAD {} (via GET): {}", request.path, e);
                        let error_response = GurtResponse::internal_server_error();
                        tls_stream.write_all(&error_response.to_bytes()).await?;
                        return Ok(());
                    }
                }
            }
        }
        
        let not_found_response = GurtResponse::not_found();
        tls_stream.write_all(&not_found_response.to_bytes()).await?;
        Ok(())
    }

    async fn handle_encrypted_request(&self, tls_stream: &mut TlsStream<TcpStream>, addr: SocketAddr, request: &GurtRequest) -> Result<()> {
        debug!("Handling encrypted {} request to {} from {}", request.method, request.path, addr);
        
        for (route, handler) in &self.routes {
            if route.matches(&request.method, &request.path) {
                let context = ServerContext {
                    remote_addr: addr,
                    request: request.clone(),
                };
                
                match handler.handle(&context).await {
                    Ok(response) => {
                        let response_bytes = response.to_bytes();
                        tls_stream.write_all(&response_bytes).await?;
                        return Ok(());
                    }
                    Err(e) => {
                        error!("Handler error for {} {}: {}", request.method, request.path, e);
                        let error_response = GurtResponse::internal_server_error()
                            .with_string_body("Internal server error");
                        tls_stream.write_all(&error_response.to_bytes()).await?;
                        return Ok(());
                    }
                }
            }
        }
        
        match request.method {
            GurtMethod::OPTIONS => {
                self.handle_default_options(tls_stream, request).await
            }
            GurtMethod::HEAD => {
                self.handle_default_head(tls_stream, addr, request).await
            }
            _ => {
                let not_found_response = GurtResponse::not_found()
                    .with_string_body("Not found");
                tls_stream.write_all(&not_found_response.to_bytes()).await?;
                Ok(())
            }
        }
    }
}

impl Clone for GurtServer {
    fn clone(&self) -> Self {
        Self {
            routes: self.routes.clone(),
            tls_acceptor: self.tls_acceptor.clone(),
            handshake_timeout: self.handshake_timeout,
            request_timeout: self.request_timeout,
            connection_timeout: self.connection_timeout,
        }
    }
}

impl Default for GurtServer {
    fn default() -> Self {
        Self::new()
    }
}


#[cfg(test)]
mod tests {
    use super::*;
    use tokio::test;
    
    #[test]
    async fn test_route_matching() {
        let route = Route::get("/test");
        assert!(route.matches(&GurtMethod::GET, "/test"));
        assert!(!route.matches(&GurtMethod::POST, "/test"));
        assert!(!route.matches(&GurtMethod::GET, "/other"));
        
        assert!(route.matches(&GurtMethod::GET, "/test?foo=bar"));
        assert!(route.matches(&GurtMethod::GET, "/test?page=1&limit=100"));
        
        let wildcard_route = Route::get("/api/*");
        assert!(wildcard_route.matches(&GurtMethod::GET, "/api/users"));
        assert!(wildcard_route.matches(&GurtMethod::GET, "/api/posts"));
        assert!(!wildcard_route.matches(&GurtMethod::GET, "/other"));
        
        assert!(wildcard_route.matches(&GurtMethod::GET, "/api/users?id=123"));
        assert!(wildcard_route.matches(&GurtMethod::GET, "/api/posts?page=2"));
    }
    
}