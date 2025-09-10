use crate::config::GurtConfig;
use gurtlib::{prelude::*, GurtMethod, GurtStatusCode};
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tracing::{warn, debug};

#[derive(Debug)]
pub struct RateLimitData {
    requests: Vec<Instant>,
    connections: u32,
}

impl RateLimitData {
    fn new() -> Self {
        Self {
            requests: Vec::new(),
            connections: 0,
        }
    }

    fn cleanup_old_requests(&mut self, window: Duration) {
        let cutoff = Instant::now() - window;
        self.requests.retain(|&request_time| request_time > cutoff);
    }

    fn add_request(&mut self) {
        self.requests.push(Instant::now());
    }

    fn request_count(&self) -> usize {
        self.requests.len()
    }

    fn increment_connections(&mut self) {
        self.connections += 1;
    }

    fn decrement_connections(&mut self) {
        if self.connections > 0 {
            self.connections -= 1;
        }
    }

    fn connection_count(&self) -> u32 {
        self.connections
    }
}

pub struct SecurityMiddleware {
    config: Arc<GurtConfig>,
    rate_limit_data: Arc<Mutex<HashMap<IpAddr, RateLimitData>>>,
}

impl SecurityMiddleware {
    pub fn new(config: Arc<GurtConfig>) -> Self {
        Self {
            config,
            rate_limit_data: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn is_method_allowed(&self, method: &GurtMethod) -> bool {
        if let Some(security) = &self.config.security {
            let method_str = method.to_string();
            security.allowed_methods.contains(&method_str)
        } else {
            true
        }
    }

    pub fn check_rate_limit(&self, client_ip: IpAddr) -> bool {
        if let Some(security) = &self.config.security {
            let mut data = self.rate_limit_data.lock().unwrap();
            let rate_data = data.entry(client_ip).or_insert_with(RateLimitData::new);
            
            rate_data.cleanup_old_requests(Duration::from_secs(60));
            
            if rate_data.request_count() >= security.rate_limit_requests as usize {
                warn!("Rate limit exceeded for IP {}: {} requests in the last minute", 
                      client_ip, rate_data.request_count());
                return false;
            }
            
            rate_data.add_request();
            debug!("Request from {}: {}/{} requests in the last minute", 
                   client_ip, rate_data.request_count(), security.rate_limit_requests);
        }
        
        true
    }

    pub fn check_connection_limit(&self, client_ip: IpAddr) -> bool {
        if let Some(security) = &self.config.security {
            let mut data = self.rate_limit_data.lock().unwrap();
            let rate_data = data.entry(client_ip).or_insert_with(RateLimitData::new);
            
            if rate_data.connection_count() >= security.rate_limit_connections {
                warn!("Connection limit exceeded for IP {}: {} concurrent connections", 
                      client_ip, rate_data.connection_count());
                return false;
            }
        }
        
        true
    }

    pub fn register_connection(&self, client_ip: IpAddr) {
        if self.config.security.is_some() {
            let mut data = self.rate_limit_data.lock().unwrap();
            let rate_data = data.entry(client_ip).or_insert_with(RateLimitData::new);
            rate_data.increment_connections();
            debug!("Connection registered for {}: {} concurrent connections", 
                   client_ip, rate_data.connection_count());
        }
    }

    pub fn unregister_connection(&self, client_ip: IpAddr) {
        if self.config.security.is_some() {
            let mut data = self.rate_limit_data.lock().unwrap();
            if let Some(rate_data) = data.get_mut(&client_ip) {
                rate_data.decrement_connections();
                debug!("Connection unregistered for {}: {} concurrent connections remaining", 
                       client_ip, rate_data.connection_count());
            }
        }
    }

    pub fn create_method_not_allowed_response(&self) -> std::result::Result<GurtResponse, GurtError> {
        let response = GurtResponse::new(GurtStatusCode::MethodNotAllowed)
            .with_header("Content-Type", "text/html");
        Ok(response)
    }

    pub fn create_rate_limit_response(&self) -> std::result::Result<GurtResponse, GurtError> {
        let response = GurtResponse::new(GurtStatusCode::TooManyRequests)
            .with_header("Content-Type", "text/html")
            .with_header("Retry-After", "60");
        Ok(response)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::IpAddr;
    use std::sync::Arc;
    use std::time::Duration;

    fn create_test_config() -> Arc<GurtConfig> {
        let mut config = crate::config::GurtConfig::default();
        config.security = Some(crate::config::SecurityConfig {
            deny_files: vec!["*.secret".to_string(), "private/*".to_string()],
            allowed_methods: vec!["GET".to_string(), "POST".to_string()],
            rate_limit_requests: 5,
            rate_limit_connections: 2,
        });
        Arc::new(config)
    }

    #[test]
    fn test_rate_limit_data_initialization() {
        let data = RateLimitData::new();
        
        assert_eq!(data.request_count(), 0);
        assert_eq!(data.connection_count(), 0);
    }

    #[test]
    fn test_rate_limit_data_request_tracking() {
        let mut data = RateLimitData::new();
        
        data.add_request();
        data.add_request();
        assert_eq!(data.request_count(), 2);
        
        data.cleanup_old_requests(Duration::from_secs(0));
        assert_eq!(data.request_count(), 0);
    }

    #[test]
    fn test_rate_limit_data_connection_tracking() {
        let mut data = RateLimitData::new();
        
        data.increment_connections();
        data.increment_connections();
        assert_eq!(data.connection_count(), 2);
        
        data.decrement_connections();
        assert_eq!(data.connection_count(), 1);
        
        data.decrement_connections();
        data.decrement_connections();
        assert_eq!(data.connection_count(), 0);
    }

    #[test]
    fn test_security_middleware_initialization() {
        let config = create_test_config();
        let middleware = SecurityMiddleware::new(config.clone());
        
        assert!(middleware.rate_limit_data.lock().unwrap().is_empty());
    }

    #[test]
    fn test_connection_tracking() {
        let config = create_test_config();
        let middleware = SecurityMiddleware::new(config.clone());
        let ip: IpAddr = "127.0.0.1".parse().unwrap();
        
        middleware.register_connection(ip);
        {
            let data = middleware.rate_limit_data.lock().unwrap();
            assert_eq!(data.get(&ip).unwrap().connection_count(), 1);
        }
        
        middleware.unregister_connection(ip);
        {
            let data = middleware.rate_limit_data.lock().unwrap();
            assert_eq!(data.get(&ip).unwrap().connection_count(), 0);
        }
    }

    #[test]
    fn test_rate_limiting_requests() {
        let config = create_test_config();
        let middleware = SecurityMiddleware::new(config.clone());
        let ip: IpAddr = "127.0.0.1".parse().unwrap();
        
        for _ in 0..5 {
            assert!(middleware.check_rate_limit(ip));
        }
        
        assert!(!middleware.check_rate_limit(ip));
    }

    #[test]
    fn test_connection_limiting() {
        let config = create_test_config();
        let middleware = SecurityMiddleware::new(config.clone());
        let ip: IpAddr = "127.0.0.1".parse().unwrap();
        
        middleware.register_connection(ip);
        middleware.register_connection(ip);
        
        assert!(!middleware.check_connection_limit(ip));
    }

    #[test]
    fn test_method_validation() {
        let config = create_test_config();
        let middleware = SecurityMiddleware::new(config.clone());
        
        assert!(middleware.is_method_allowed(&GurtMethod::GET));
        assert!(middleware.is_method_allowed(&GurtMethod::POST));
        
        assert!(!middleware.is_method_allowed(&GurtMethod::PUT));
        assert!(!middleware.is_method_allowed(&GurtMethod::DELETE));
    }

    #[test]
    fn test_multiple_ips_isolation() {
        let config = create_test_config();
        let middleware = SecurityMiddleware::new(config.clone());
        let ip1: IpAddr = "127.0.0.1".parse().unwrap();
        let ip2: IpAddr = "127.0.0.2".parse().unwrap();
        
        for _ in 0..6 {
            middleware.check_rate_limit(ip1);
        }
        
        assert!(middleware.check_rate_limit(ip2));
        assert!(!middleware.check_rate_limit(ip1));
    }

    #[test]
    fn test_response_creation() {
        let config = create_test_config();
        let middleware = SecurityMiddleware::new(config.clone());
        
        let response = middleware.create_method_not_allowed_response().unwrap();
        assert_eq!(response.status_code, 405);
        
        let response = middleware.create_rate_limit_response().unwrap();
        assert_eq!(response.status_code, 429);
    }
}
