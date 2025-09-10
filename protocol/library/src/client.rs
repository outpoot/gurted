use crate::{
    GurtError, Result, GurtRequest, GurtResponse,
    protocol::{DEFAULT_PORT, DEFAULT_CONNECTION_TIMEOUT, DEFAULT_REQUEST_TIMEOUT, DEFAULT_HANDSHAKE_TIMEOUT, BODY_SEPARATOR},
    message::GurtMethod,
    crypto::GURT_ALPN,
};
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time::{timeout, Duration};
use tokio_rustls::{TlsConnector, rustls::{ClientConfig as TlsClientConfig, RootCertStore, pki_types::ServerName}};
use std::sync::Arc;
use std::collections::HashMap;
use std::sync::Mutex;
use url::Url;
use tracing::debug;

#[derive(Debug, Clone)]
pub struct GurtClientConfig {
    pub connect_timeout: Duration,
    pub request_timeout: Duration,
    pub handshake_timeout: Duration,
    pub user_agent: String,
    pub max_redirects: usize,
    pub enable_connection_pooling: bool,
    pub max_connections_per_host: usize,
    pub custom_ca_certificates: Vec<String>,
    pub dns_server_ip: String,
    pub dns_server_port: u16,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct ConnectionKey {
    host: String,
    port: u16,
}

struct PooledTlsConnection {
    connection: tokio_rustls::client::TlsStream<TcpStream>,
    last_used: std::time::Instant,
}

impl Default for GurtClientConfig {
    fn default() -> Self {
        Self {
            connect_timeout: Duration::from_secs(DEFAULT_CONNECTION_TIMEOUT),
            request_timeout: Duration::from_secs(DEFAULT_REQUEST_TIMEOUT),
            handshake_timeout: Duration::from_secs(DEFAULT_HANDSHAKE_TIMEOUT),
            user_agent: format!("GURT-Client/{}", crate::GURT_VERSION),
            max_redirects: 5,
            enable_connection_pooling: true,
            max_connections_per_host: 4,
            custom_ca_certificates: Vec::new(),
            dns_server_ip: "135.125.163.131".to_string(),
            dns_server_port: 4878,
        }
    }
}

#[derive(Debug)]
enum Connection {
    Plain(TcpStream),
}

impl Connection {
    async fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        match self {
            Connection::Plain(stream) => stream.read(buf).await.map_err(|e| GurtError::connection(e.to_string())),
        }
    }
    
    async fn write_all(&mut self, buf: &[u8]) -> Result<()> {
        match self {
            Connection::Plain(stream) => stream.write_all(buf).await.map_err(|e| GurtError::connection(e.to_string())),
        }
    }
}

#[derive(Debug)]
struct PooledConnection {
    connection: Connection,
}

impl PooledConnection {
    fn new(stream: TcpStream) -> Self {
        Self { connection: Connection::Plain(stream) }
    }
}

pub struct GurtClient {
    config: GurtClientConfig,
    connection_pool: Arc<Mutex<HashMap<ConnectionKey, Vec<PooledTlsConnection>>>>,
    dns_cache: Arc<Mutex<HashMap<String, String>>>,
}

impl GurtClient {
    pub fn new() -> Self {
        Self {
            config: GurtClientConfig::default(),
            connection_pool: Arc::new(Mutex::new(HashMap::new())),
            dns_cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }
    
    pub fn with_config(config: GurtClientConfig) -> Self {
        Self {
            config,
            connection_pool: Arc::new(Mutex::new(HashMap::new())),
            dns_cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }
    
    async fn get_pooled_connection(&self, host: &str, port: u16, original_host: Option<&str>) -> Result<tokio_rustls::client::TlsStream<TcpStream>> {
        if !self.config.enable_connection_pooling {
            return self.perform_handshake(host, port, original_host).await;
        }
        
        let key = ConnectionKey {
            host: host.to_string(),
            port,
        };
        
        if let Ok(mut pool) = self.connection_pool.lock() {
            if let Some(connections) = pool.get_mut(&key) {
                connections.retain(|conn| conn.last_used.elapsed().as_secs() < 30);
                
                if let Some(pooled_conn) = connections.pop() {
                    debug!("Reusing pooled connection for {}:{}", host, port);
                    return Ok(pooled_conn.connection);
                }
            }
        }
        
        debug!("Creating new connection for {}:{}", host, port);
        self.perform_handshake(host, port, original_host).await
    }
    
    fn return_connection_to_pool(&self, host: &str, port: u16, connection: tokio_rustls::client::TlsStream<TcpStream>) {
        if !self.config.enable_connection_pooling {
            return;
        }
        
        let key = ConnectionKey {
            host: host.to_string(),
            port,
        };
        
        if let Ok(mut pool) = self.connection_pool.lock() {
            let connections = pool.entry(key).or_insert_with(Vec::new);
            
            if connections.len() < self.config.max_connections_per_host {
                connections.push(PooledTlsConnection {
                    connection,
                    last_used: std::time::Instant::now(),
                });
                debug!("Returned connection to pool");
            }
        }
    }
    
    async fn create_connection(&self, host: &str, port: u16) -> Result<PooledConnection> {
        let addr = format!("{}:{}", host, port);
        let stream = timeout(
            self.config.connect_timeout,
            TcpStream::connect(&addr)
        ).await
            .map_err(|_| GurtError::timeout("Connection timeout"))?
            .map_err(|e| GurtError::connection(format!("Failed to connect: {}", e)))?;
        
        let conn = PooledConnection::new(stream);
        Ok(conn)
    }
    
    async fn read_response_data(&self, conn: &mut PooledConnection) -> Result<Vec<u8>> {
        let mut buffer = Vec::new();
        let mut temp_buffer = [0u8; 8192];
        
        let start_time = std::time::Instant::now();
        let mut headers_parsed = false;
        let mut expected_body_length: Option<usize> = None;
        let mut headers_end_pos: Option<usize> = None;
        
        loop {
            if start_time.elapsed() > self.config.request_timeout {
                return Err(GurtError::timeout("Response timeout"));
            }
            
            let bytes_read = conn.connection.read(&mut temp_buffer).await?;
            if bytes_read == 0 {
                break;
            }
            
            buffer.extend_from_slice(&temp_buffer[..bytes_read]);
            
            let body_separator = BODY_SEPARATOR.as_bytes();
            
            if !headers_parsed {
                if let Some(pos) = buffer.windows(body_separator.len()).position(|w| w == body_separator) {
                    headers_end_pos = Some(pos + body_separator.len());
                    headers_parsed = true;
                    
                    let headers_section = &buffer[..pos];
                    if let Ok(headers_str) = std::str::from_utf8(headers_section) {
                        for line in headers_str.lines() {
                            if line.to_lowercase().starts_with("content-length:") {
                                if let Some(length_str) = line.split(':').nth(1) {
                                    if let Ok(length) = length_str.trim().parse::<usize>() {
                                        expected_body_length = Some(length);
                                    }
                                }
                                break;
                            }
                        }
                    }
                }
            }
            
            if let (Some(headers_end), Some(expected_length)) = (headers_end_pos, expected_body_length) {
                let current_body_length = buffer.len() - headers_end;
                if current_body_length >= expected_length {
                    return Ok(buffer);
                }
            } else if headers_parsed && expected_body_length.is_none() {
                return Ok(buffer);
            }
        }
        
        if buffer.is_empty() {
            Err(GurtError::connection("Connection closed unexpectedly"))
        } else {
            Ok(buffer)
        }
    }
    
    async fn perform_handshake(&self, host: &str, port: u16, original_host: Option<&str>) -> Result<tokio_rustls::client::TlsStream<TcpStream>> {
        debug!("Starting GURT handshake with {}:{}", host, port);
        
        let mut plain_conn = self.create_connection(host, port).await?;
        
        // Use original_host for the Host header if available, otherwise fall back to host
        let host_header = original_host.unwrap_or(host);
        
        let handshake_request = GurtRequest::new(GurtMethod::HANDSHAKE, "/".to_string())
            .with_header("Host", host_header)
            .with_header("User-Agent", &self.config.user_agent);
        
        let handshake_data = handshake_request.to_string();
        plain_conn.connection.write_all(handshake_data.as_bytes()).await?;
        
        let handshake_response_bytes = timeout(
            self.config.handshake_timeout,
            self.read_response_data(&mut plain_conn)
        ).await
            .map_err(|_| GurtError::timeout("Handshake timeout"))??;
        
        let handshake_response = GurtResponse::parse_bytes(&handshake_response_bytes)?;
        
        if handshake_response.status_code != 101 {
            return Err(GurtError::protocol(format!("Handshake failed: {} {}", 
                handshake_response.status_code, 
                handshake_response.status_message)));
        }
        
        let tcp_stream = match plain_conn.connection {
            Connection::Plain(stream) => stream,
        };
        
        // Use original_host for TLS SNI if available, otherwise fall back to host
        let tls_host = original_host.unwrap_or(host);
        
        self.upgrade_to_tls(tcp_stream, tls_host).await
    }
    
    async fn upgrade_to_tls(&self, stream: TcpStream, host: &str) -> Result<tokio_rustls::client::TlsStream<TcpStream>> {
        debug!("Upgrading connection to TLS for {}", host);
        
        let mut root_store = RootCertStore::empty();
        
        let cert_result = rustls_native_certs::load_native_certs();
        let mut added = 0;
        for cert in cert_result.certs {
            if root_store.add(cert).is_ok() {
                added += 1;
            }
        }
        
        for ca_cert_pem in &self.config.custom_ca_certificates {
            let mut pem_bytes = ca_cert_pem.as_bytes();
            let cert_iter = rustls_pemfile::certs(&mut pem_bytes);
            for cert_result in cert_iter {
                match cert_result {
                    Ok(cert) => {
                        if root_store.add(cert).is_ok() {
                            added += 1;
                            debug!("Added custom CA certificate");
                        }
                    }
                    Err(e) => {
                        debug!("Failed to parse CA certificate: {}", e);
                    }
                }
            }
        }
        
        if added == 0 {
            return Err(GurtError::crypto("No valid certificates found (system or custom)".to_string()));
        }
        
        let mut client_config = TlsClientConfig::builder()
            .with_root_certificates(root_store)
            .with_no_client_auth();
        
        client_config.alpn_protocols = vec![GURT_ALPN.to_vec()];
        
        let connector = TlsConnector::from(Arc::new(client_config));
        
        let server_name = match host {
            "127.0.0.1" => "localhost",
            "localhost" => "localhost", 
            _ => host
        };
        
        let domain = ServerName::try_from(server_name.to_string())
            .map_err(|e| GurtError::crypto(format!("Invalid server name '{}': {}", server_name, e)))?;
        
        let tls_stream = connector.connect(domain, stream).await
            .map_err(|e| GurtError::crypto(format!("TLS handshake failed: {}", e)))?;
        
        debug!("TLS connection established with {}", host);
        Ok(tls_stream)
    }
    
    async fn send_request_internal(&self, host: &str, port: u16, request: GurtRequest, original_host: Option<&str>) -> Result<GurtResponse> {
        debug!("Sending {} {} to {}:{}", request.method, request.path, host, port);
        
        let mut tls_stream = self.get_pooled_connection(host, port, original_host).await?;
        
        let request_data = request.to_string();
        tls_stream.write_all(request_data.as_bytes()).await
            .map_err(|e| GurtError::connection(format!("Failed to write request: {}", e)))?;
        
        let mut buffer = Vec::new();
        let mut temp_buffer = [0u8; 8192];
        
        let start_time = std::time::Instant::now();
        let mut headers_parsed = false;
        let mut expected_body_length: Option<usize> = None;
        let mut headers_end_pos: Option<usize> = None;
        
        loop {
            if start_time.elapsed() > self.config.request_timeout {
                return Err(GurtError::timeout("Request timeout"));
            }
            
            match timeout(Duration::from_millis(100), tls_stream.read(&mut temp_buffer)).await {
                Ok(Ok(0)) => break,
                Ok(Ok(n)) => {
                    buffer.extend_from_slice(&temp_buffer[..n]);
                    
                    if !headers_parsed {
                        if let Some(pos) = buffer.windows(4).position(|w| w == b"\r\n\r\n") {
                            headers_end_pos = Some(pos + 4);
                            headers_parsed = true;
                            
                            let headers_section = std::str::from_utf8(&buffer[..pos])
                                .map_err(|e| GurtError::invalid_message(format!("Invalid UTF-8 in headers: {}", e)))?;
                            
                            for line in headers_section.lines().skip(1) {
                                if line.to_lowercase().starts_with("content-length:") {
                                    if let Some(length_str) = line.split(':').nth(1) {
                                        expected_body_length = length_str.trim().parse().ok();
                                    }
                                }
                            }
                        }
                    }
                    
                    if headers_parsed {
                        if let (Some(headers_end), Some(expected_len)) = (headers_end_pos, expected_body_length) {
                            if buffer.len() >= headers_end + expected_len {
                                break;
                            }
                        } else if expected_body_length.is_none() && headers_parsed {
                            break;
                        }
                    }
                },
                Ok(Err(e)) => return Err(GurtError::connection(format!("Read error: {}", e))),
                Err(_) => continue,
            }
        }
        
        let response = GurtResponse::parse_bytes(&buffer)?;
        
        self.return_connection_to_pool(host, port, tls_stream);
        
        Ok(response)
    }
    
    pub async fn get(&self, url: &str) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        
        let request = GurtRequest::new(GurtMethod::GET, path.to_string())
            .with_header("User-Agent", &self.config.user_agent)
            .with_header("Accept", "*/*");
        
        self.send_request(&host, port, request).await
    }
    
    pub async fn post(&self, url: &str, body: &str) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        
        let request = GurtRequest::new(GurtMethod::POST, path.to_string())
            .with_header("User-Agent", &self.config.user_agent)
            .with_header("Content-Type", "text/plain")
            .with_string_body(body);
        
        self.send_request(&host, port, request).await
    }
    
    pub async fn post_json<T: serde::Serialize>(&self, url: &str, data: &T) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        let json_body = serde_json::to_string(data)?;
        
        let request = GurtRequest::new(GurtMethod::POST, path.to_string())
            .with_header("User-Agent", &self.config.user_agent)
            .with_header("Content-Type", "application/json")
            .with_string_body(json_body);
        
        self.send_request(&host, port, request).await
    }

    pub async fn put(&self, url: &str, body: &str) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        
        let request = GurtRequest::new(GurtMethod::PUT, path.to_string())
            .with_header("User-Agent", &self.config.user_agent)
            .with_header("Content-Type", "text/plain")
            .with_string_body(body);
        
        self.send_request(&host, port, request).await
    }

    pub async fn put_json<T: serde::Serialize>(&self, url: &str, data: &T) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        let json_body = serde_json::to_string(data)?;
        
        let request = GurtRequest::new(GurtMethod::PUT, path.to_string())
            .with_header("User-Agent", &self.config.user_agent)
            .with_header("Content-Type", "application/json")
            .with_string_body(json_body);
        
        self.send_request(&host, port, request).await
    }

    pub async fn delete(&self, url: &str) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        
        let request = GurtRequest::new(GurtMethod::DELETE, path.to_string())
            .with_header("User-Agent", &self.config.user_agent);
        
        self.send_request(&host, port, request).await
    }

    pub async fn head(&self, url: &str) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        
        let request = GurtRequest::new(GurtMethod::HEAD, path.to_string())
            .with_header("User-Agent", &self.config.user_agent);
        
        self.send_request(&host, port, request).await
    }

    pub async fn options(&self, url: &str) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        
        let request = GurtRequest::new(GurtMethod::OPTIONS, path.to_string())
            .with_header("User-Agent", &self.config.user_agent);
        
        self.send_request(&host, port, request).await
    }

    pub async fn patch(&self, url: &str, body: &str) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        
        let request = GurtRequest::new(GurtMethod::PATCH, path.to_string())
            .with_header("User-Agent", &self.config.user_agent)
            .with_header("Content-Type", "text/plain")
            .with_string_body(body);
        
        self.send_request(&host, port, request).await
    }

    pub async fn patch_json<T: serde::Serialize>(&self, url: &str, data: &T) -> Result<GurtResponse> {
        let (host, port, path) = self.parse_gurt_url(url)?;
        let json_body = serde_json::to_string(data)?;
        
        let request = GurtRequest::new(GurtMethod::PATCH, path.to_string())
            .with_header("User-Agent", &self.config.user_agent)
            .with_header("Content-Type", "application/json")
            .with_string_body(json_body);
        
        self.send_request(&host, port, request).await
    }
    
    pub async fn send_request(&self, host: &str, port: u16, mut request: GurtRequest) -> Result<GurtResponse> {
        let resolved_host = self.resolve_domain(host).await?;
        
        request = request.with_header("Host", host);
        
        self.send_request_internal(&resolved_host, port, request, Some(host)).await
    }
    
    fn parse_gurt_url(&self, url: &str) -> Result<(String, u16, String)> {
        let parsed_url = Url::parse(url).map_err(|e| GurtError::invalid_message(format!("Invalid URL: {}", e)))?;
        
        if parsed_url.scheme() != "gurt" {
            return Err(GurtError::invalid_message("URL must use gurt:// scheme"));
        }
        
        let host = parsed_url.host_str().ok_or_else(|| GurtError::invalid_message("URL must have a host"))?.to_string();
        let port = parsed_url.port().unwrap_or(DEFAULT_PORT);
        let mut path = if parsed_url.path().is_empty() { "/" } else { parsed_url.path() }.to_string();
        
        if let Some(query) = parsed_url.query() {
            path = format!("{}?{}", path, query);
        }
        
        Ok((host, port, path))
    }
    
    async fn resolve_domain(&self, domain: &str) -> Result<String> {
        match self.dns_cache.lock() {
            Ok(cache) => {
                if let Some(cached_ip) = cache.get(domain) {
                    debug!("Using cached DNS resolution for {}: {}", domain, cached_ip);
                    return Ok(cached_ip.clone());
                }
            },
            Err(e) => {
                debug!("DNS cache lock poisoned: {}", e);
                // Continue without cache
            }
        }
        
        if self.is_ip_address(domain) {
            return Ok(domain.to_string());
        }
        
        if domain == "localhost" {
            return Ok("127.0.0.1".to_string());
        }
        
        debug!("Resolving domain {} via DNS API", domain);
        
        if !self.is_ip_address(&self.config.dns_server_ip) && self.config.dns_server_ip != "localhost" {
            return Err(GurtError::invalid_message("DNS server must be an IP address or 'localhost'"));
        }
        
        let dns_server_ip = if self.config.dns_server_ip == "localhost" {
            "127.0.0.1".to_string()
        } else {
            self.config.dns_server_ip.clone()
        };
        
        let dns_request_body = serde_json::json!({
            "domain": domain
        }).to_string();
        let dns_request = GurtRequest::new(GurtMethod::POST, "/resolve-full".to_string())
            .with_header("Host", &self.config.dns_server_ip)
            .with_header("Content-Type", "application/json")
            .with_string_body(dns_request_body);
        
        let dns_response = self.send_request_internal(&dns_server_ip, self.config.dns_server_port, dns_request, None).await?;
        
        if dns_response.status_code != 200 {
            return Err(GurtError::invalid_message(format!(
                "DNS resolution failed for {}: {} {}", 
                domain, dns_response.status_code, dns_response.status_message
            )));
        }
        
        let response_text = String::from_utf8_lossy(&dns_response.body);
        let dns_data: serde_json::Value = serde_json::from_str(&response_text)
            .map_err(|e| GurtError::invalid_message(format!("Invalid DNS response JSON: {}", e)))?;
        
        if let Some(records) = dns_data.get("records").and_then(|r| r.as_array()) {
            for record in records {
                if let (Some(record_type), Some(value)) = (
                    record.get("type").and_then(|t| t.as_str()),
                    record.get("value").and_then(|v| v.as_str())
                ) {
                    if record_type == "A" {
                        debug!("Resolved {} to {}", domain, value);
                        
                        if let Ok(mut cache) = self.dns_cache.lock() {
                            cache.insert(domain.to_string(), value.to_string());
                        }
                        
                        return Ok(value.to_string());
                    }
                }
            }
        }
        
        Err(GurtError::invalid_message(format!("No A record found for domain {}", domain)))
    }
    
    fn is_ip_address(&self, addr: &str) -> bool {
        use std::net::IpAddr;
        addr.parse::<IpAddr>().is_ok()
    }

    
}

impl Default for GurtClient {
    fn default() -> Self {
        Self::new()
    }
}

impl Clone for GurtClient {
    fn clone(&self) -> Self {
        Self {
            config: self.config.clone(),
            connection_pool: self.connection_pool.clone(),
            dns_cache: self.dns_cache.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_url_parsing() {
        let client = GurtClient::new();
        
        let (host, port, path) = client.parse_gurt_url("gurt://example.com/test").unwrap();
        assert_eq!(host, "example.com");
        assert_eq!(port, DEFAULT_PORT);
        assert_eq!(path, "/test");
        
        let (host, port, path) = client.parse_gurt_url("gurt://example.com:8080/api/v1").unwrap();
        assert_eq!(host, "example.com");
        assert_eq!(port, 8080);
        assert_eq!(path, "/api/v1");
    }
    
    #[test]
    fn test_connection_pooling_config() {
        let config = GurtClientConfig {
            enable_connection_pooling: true,
            max_connections_per_host: 8,
            ..Default::default()
        };
        
        let client = GurtClient::with_config(config);
        assert!(client.config.enable_connection_pooling);
        assert_eq!(client.config.max_connections_per_host, 8);
    }
    
    #[test]
    fn test_connection_key() {
        let key1 = ConnectionKey {
            host: "example.com".to_string(),
            port: 4878,
        };
        
        let key2 = ConnectionKey {
            host: "example.com".to_string(),
            port: 4878,
        };
        
        let key3 = ConnectionKey {
            host: "other.com".to_string(),
            port: 4878,
        };
        
        assert_eq!(key1, key2);
        assert_ne!(key1, key3);
    }

    #[tokio::test]
    async fn test_host_header_preserved_with_dns_resolution() {
        use crate::message::{GurtMethod, GurtRequest};
        
        let mut config = GurtClientConfig::default();
        config.enable_connection_pooling = false;
        let client = GurtClient::with_config(config);
        
        {
            let mut dns_cache = client.dns_cache.lock().unwrap();
            dns_cache.insert("arson.dev".to_string(), "1.1.1.1".to_string());
        }
        
        let request = GurtRequest::new(GurtMethod::GET, "/test".to_string());

        let original_host = "arson.dev";
        
        let mut test_request = request.clone();
        test_request = test_request.with_header("Host", original_host);
        
        assert_eq!(test_request.headers.get("host").unwrap(), original_host);
        
        let resolved = client.resolve_domain("arson.dev").await.unwrap();
        assert_eq!(resolved, "1.1.1.1");
        
        let request_with_host = GurtRequest::new(GurtMethod::GET, "/test".to_string())
            .with_header("Host", original_host);
        
        assert_eq!(request_with_host.headers.get("host").unwrap(), "arson.dev");
    }

    #[test]
    fn test_handshake_request_uses_original_host() {
        use crate::message::{GurtMethod, GurtRequest};
        
        let original_host = "arson.dev";
        
        let handshake_request = GurtRequest::new(GurtMethod::HANDSHAKE, "/".to_string())
            .with_header("Host", original_host)
            .with_header("User-Agent", "GURT-Client/1.0.0");
        
        assert_eq!(handshake_request.headers.get("host").unwrap(), "arson.dev");
        assert_ne!(handshake_request.headers.get("host").unwrap(), "1.1.1.1");
        
        assert_eq!(handshake_request.method, GurtMethod::HANDSHAKE);
        assert_eq!(handshake_request.path, "/");
        
        assert!(handshake_request.headers.contains_key("user-agent"));
    }

}