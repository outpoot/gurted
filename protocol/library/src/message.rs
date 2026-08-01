use crate::{GurtError, Result, GURT_VERSION};
use crate::protocol::{GurtStatusCode, PROTOCOL_PREFIX, HEADER_SEPARATOR, BODY_SEPARATOR};
use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use std::fmt;
use chrono::Utc;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum GurtMethod {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    OPTIONS,
    PATCH,
    HANDSHAKE,
}

impl GurtMethod {
    pub fn parse(s: &str) -> Result<Self> {
        match s.to_uppercase().as_str() {
            "GET" => Ok(Self::GET),
            "POST" => Ok(Self::POST),
            "PUT" => Ok(Self::PUT),
            "DELETE" => Ok(Self::DELETE),
            "HEAD" => Ok(Self::HEAD),
            "OPTIONS" => Ok(Self::OPTIONS),
            "PATCH" => Ok(Self::PATCH),
            "HANDSHAKE" => Ok(Self::HANDSHAKE),
            _ => Err(GurtError::InvalidMessage(format!("Unsupported method: {}", s))),
        }
    }
}

impl fmt::Display for GurtMethod {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            Self::GET => "GET",
            Self::POST => "POST",
            Self::PUT => "PUT",
            Self::DELETE => "DELETE",
            Self::HEAD => "HEAD",
            Self::OPTIONS => "OPTIONS",
            Self::PATCH => "PATCH",
            Self::HANDSHAKE => "HANDSHAKE",
        };
        write!(f, "{}", s)
    }
}

pub type GurtHeaders = HashMap<String, String>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GurtRequest {
    pub method: GurtMethod,
    pub path: String,
    pub version: String,
    pub headers: GurtHeaders,
    pub body: Vec<u8>,
}

impl GurtRequest {
    pub fn new(method: GurtMethod, path: String) -> Self {
        Self {
            method,
            path,
            version: GURT_VERSION.to_string(),
            headers: GurtHeaders::new(),
            body: Vec::new(),
        }
    }
    
    pub fn with_header<K: Into<String>, V: Into<String>>(mut self, key: K, value: V) -> Self {
        self.headers.insert(key.into().to_lowercase(), value.into());
        self
    }
    
    pub fn with_body<B: Into<Vec<u8>>>(mut self, body: B) -> Self {
        self.body = body.into();
        self
    }
    
    pub fn with_string_body<S: AsRef<str>>(mut self, body: S) -> Self {
        self.body = body.as_ref().as_bytes().to_vec();
        self
    }
    
    pub fn header(&self, key: &str) -> Option<&String> {
        self.headers.get(&key.to_lowercase())
    }
    
    pub fn text(&self) -> Result<String> {
        std::str::from_utf8(&self.body)
            .map(|s| s.to_string())
            .map_err(|e| GurtError::InvalidMessage(format!("Invalid UTF-8 body: {}", e)))
    }
    
    pub fn parse(data: &str) -> Result<Self> {
        Self::parse_bytes(data.as_bytes())
    }
    
    pub fn parse_bytes(data: &[u8]) -> Result<Self> {
        let body_separator = BODY_SEPARATOR.as_bytes();
        let body_separator_pos = data.windows(body_separator.len())
            .position(|window| window == body_separator);
        
        let (headers_section, body) = if let Some(pos) = body_separator_pos {
            let headers_part = &data[..pos];
            let body_part = &data[pos + body_separator.len()..];
            (headers_part, body_part.to_vec())
        } else {
            (data, Vec::new())
        };
        
        let headers_str = std::str::from_utf8(headers_section)
            .map_err(|_| GurtError::InvalidMessage("Invalid UTF-8 in headers".to_string()))?;
        
        let lines: Vec<&str> = headers_str.split(HEADER_SEPARATOR).collect();
        
        if lines.is_empty() {
            return Err(GurtError::InvalidMessage("Empty request".to_string()));
        }
        
        let request_line = lines[0];
        let parts: Vec<&str> = request_line.split_whitespace().collect();
        
        if parts.len() != 3 {
            return Err(GurtError::InvalidMessage("Invalid request line format".to_string()));
        }
        
        let method = GurtMethod::parse(parts[0])?;
        let path = parts[1].to_string();
        
        if !parts[2].starts_with(PROTOCOL_PREFIX) {
            return Err(GurtError::InvalidMessage("Invalid protocol identifier".to_string()));
        }
        
        let version_str = &parts[2][PROTOCOL_PREFIX.len()..];
        let version = version_str.to_string();
        
        let mut headers = GurtHeaders::new();
        
        for line in lines.iter().skip(1) {
            if line.is_empty() {
                break;
            }
            
            if let Some(colon_pos) = line.find(':') {
                let key = line[..colon_pos].trim().to_lowercase();
                let value = line[colon_pos + 1..].trim().to_string();
                headers.insert(key, value);
            }
        }
        
        Ok(Self {
            method,
            path,
            version,
            headers,
            body,
        })
    }
    
    pub fn to_string(&self) -> String {
        let mut message = format!("{} {} {}{}{}", 
            self.method, self.path, PROTOCOL_PREFIX, self.version, HEADER_SEPARATOR);
        
        let mut headers = self.headers.clone();
        if !headers.contains_key("content-length") {
            headers.insert("content-length".to_string(), self.body.len().to_string());
        }
        
        if !headers.contains_key("user-agent") {
            headers.insert("user-agent".to_string(), format!("GURT-Client/{}", GURT_VERSION));
        }
        
        for (key, value) in &headers {
            message.push_str(&format!("{}: {}{}", key, value, HEADER_SEPARATOR));
        }
        
        message.push_str(HEADER_SEPARATOR);
        
        if !self.body.is_empty() {
            if let Ok(body_str) = std::str::from_utf8(&self.body) {
                message.push_str(body_str);
            }
        }
        
        message
    }
    
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut message = format!("{} {} {}{}{}", 
            self.method, self.path, PROTOCOL_PREFIX, self.version, HEADER_SEPARATOR);
        
        let mut headers = self.headers.clone();
        if !headers.contains_key("content-length") {
            headers.insert("content-length".to_string(), self.body.len().to_string());
        }
        
        if !headers.contains_key("user-agent") {
            headers.insert("user-agent".to_string(), format!("GURT-Client/{}", GURT_VERSION));
        }
        
        for (key, value) in &headers {
            message.push_str(&format!("{}: {}{}", key, value, HEADER_SEPARATOR));
        }
        
        message.push_str(HEADER_SEPARATOR);
        
        let mut bytes = message.into_bytes();
        bytes.extend_from_slice(&self.body);
        
        bytes
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GurtResponse {
    pub version: String,
    pub status_code: u16,
    pub status_message: String,
    pub headers: GurtHeaders,
    pub body: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct GurtResponseHead {
    pub version: String,
    pub status_code: u16,
    pub status_message: String,
    pub headers: GurtHeaders,
}

impl GurtResponse {
    pub fn new(status_code: GurtStatusCode) -> Self {
        Self {
            version: GURT_VERSION.to_string(),
            status_code: status_code as u16,
            status_message: status_code.message().to_string(),
            headers: GurtHeaders::new(),
            body: Vec::new(),
        }
    }
    
    pub fn ok() -> Self {
        Self::new(GurtStatusCode::Ok)
    }
    
    pub fn not_found() -> Self {
        Self::new(GurtStatusCode::NotFound)
    }
    
    pub fn bad_request() -> Self {
        Self::new(GurtStatusCode::BadRequest)
    }
    
    pub fn forbidden() -> Self {
        Self::new(GurtStatusCode::Forbidden)
    }
    
    pub fn internal_server_error() -> Self {
        Self::new(GurtStatusCode::InternalServerError)
    }
    
    pub fn with_header<K: Into<String>, V: Into<String>>(mut self, key: K, value: V) -> Self {
        self.headers.insert(key.into().to_lowercase(), value.into());
        self
    }
    
    pub fn with_body<B: Into<Vec<u8>>>(mut self, body: B) -> Self {
        self.body = body.into();
        self
    }
    
    pub fn with_string_body<S: AsRef<str>>(mut self, body: S) -> Self {
        self.body = body.as_ref().as_bytes().to_vec();
        self
    }
    
    pub fn with_json_body<T: Serialize>(mut self, data: &T) -> Result<Self> {
        let json = serde_json::to_string(data)?;
        self.body = json.into_bytes();
        self.headers.insert("content-type".to_string(), "application/json".to_string());
        Ok(self)
    }
    
    pub fn header(&self, key: &str) -> Option<&String> {
        self.headers.get(&key.to_lowercase())
    }
    
    pub fn text(&self) -> Result<String> {
        std::str::from_utf8(&self.body)
            .map(|s| s.to_owned())
            .map_err(|e| GurtError::InvalidMessage(format!("Invalid UTF-8 body: {}", e)))
    }
    
    pub fn is_success(&self) -> bool {
        self.status_code >= 200 && self.status_code < 300
    }
    
    pub fn is_client_error(&self) -> bool {
        self.status_code >= 400 && self.status_code < 500
    }
    
    pub fn is_server_error(&self) -> bool {
        self.status_code >= 500
    }
    
    pub fn parse(data: &str) -> Result<Self> {
        Self::parse_bytes(data.as_bytes())
    }
    
    pub fn parse_bytes(data: &[u8]) -> Result<Self> {
        let body_separator = BODY_SEPARATOR.as_bytes();
        let body_separator_pos = data.windows(body_separator.len())
            .position(|window| window == body_separator);
        
        let (headers_section, body) = if let Some(pos) = body_separator_pos {
            let headers_part = &data[..pos];
            let body_part = &data[pos + body_separator.len()..];
            (headers_part, body_part.to_vec())
        } else {
            (data, Vec::new())
        };
        
        let headers_str = std::str::from_utf8(headers_section)
            .map_err(|_| GurtError::InvalidMessage("Invalid UTF-8 in headers".to_string()))?;
        
        let lines: Vec<&str> = headers_str.split(HEADER_SEPARATOR).collect();
        
        if lines.is_empty() {
            return Err(GurtError::InvalidMessage("Empty response".to_string()));
        }
        
        let status_line = lines[0];
        let parts: Vec<&str> = status_line.splitn(3, ' ').collect();
        
        if parts.len() < 2 {
            return Err(GurtError::InvalidMessage("Invalid status line format".to_string()));
        }
        
        if !parts[0].starts_with(PROTOCOL_PREFIX) {
            return Err(GurtError::InvalidMessage("Invalid protocol identifier".to_string()));
        }
        
        let version_str = &parts[0][PROTOCOL_PREFIX.len()..];
        let version = version_str.to_string();
        
        let status_code: u16 = parts[1].parse()
            .map_err(|_| GurtError::InvalidMessage("Invalid status code".to_string()))?;
        
        let status_message = if parts.len() > 2 {
            parts[2].to_string()
        } else {
            GurtStatusCode::from_u16(status_code)
                .map(|sc| sc.message().to_string())
                .unwrap_or_else(|| "Unknown".to_string())
        };
        
        let mut headers = GurtHeaders::new();
        
        for line in lines.iter().skip(1) {
            if line.is_empty() {
                break;
            }
            
            if let Some(colon_pos) = line.find(':') {
                let key = line[..colon_pos].trim().to_lowercase();
                let value = line[colon_pos + 1..].trim().to_string();
                headers.insert(key, value);
            }
        }
        
        Ok(Self {
            version,
            status_code,
            status_message,
            headers,
            body,
        })
    }
    
    pub fn to_string(&self) -> String {
        let mut message = format!("{}{} {} {}{}", 
            PROTOCOL_PREFIX, self.version, self.status_code, self.status_message, HEADER_SEPARATOR);
        
        let mut headers = self.headers.clone();
        if !headers.contains_key("content-length") {
            headers.insert("content-length".to_string(), self.body.len().to_string());
        }
        
        if !headers.contains_key("server") {
            headers.insert("server".to_string(), format!("GURT/{}", GURT_VERSION));
        }
        
        if !headers.contains_key("date") {
            let now = Utc::now();
            let date_str = now.format("%a, %d %b %Y %H:%M:%S GMT").to_string();
            headers.insert("date".to_string(), date_str);
        }
        
        for (key, value) in &headers {
            message.push_str(&format!("{}: {}{}", key, value, HEADER_SEPARATOR));
        }
        
        message.push_str(HEADER_SEPARATOR);
        
        if !self.body.is_empty() {
            if let Ok(body_str) = std::str::from_utf8(&self.body) {
                message.push_str(body_str);
            }
        }
        
        message
    }
    
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut message = format!("{}{} {} {}{}", 
            PROTOCOL_PREFIX, self.version, self.status_code, self.status_message, HEADER_SEPARATOR);
        
        let mut headers = self.headers.clone();
        if !headers.contains_key("content-length") {
            headers.insert("content-length".to_string(), self.body.len().to_string());
        }
        
        if !headers.contains_key("server") {
            headers.insert("server".to_string(), format!("GURT/{}", GURT_VERSION));
        }
        
        if !headers.contains_key("date") {
            let now = Utc::now();
            let date_str = now.format("%a, %d %b %Y %H:%M:%S GMT").to_string();
            headers.insert("date".to_string(), date_str);
        }
        
        for (key, value) in &headers {
            message.push_str(&format!("{}: {}{}", key, value, HEADER_SEPARATOR));
        }
        
        message.push_str(HEADER_SEPARATOR);
        
        let mut bytes = message.into_bytes();
        bytes.extend_from_slice(&self.body);
        
        bytes
    }
}

#[derive(Debug, Clone)]
pub enum GurtMessage {
    Request(GurtRequest),
    Response(GurtResponse),
}

impl GurtMessage {
    pub fn parse(data: &str) -> Result<Self> {
        Self::parse_bytes(data.as_bytes())
    }
    
    pub fn parse_bytes(data: &[u8]) -> Result<Self> {
        let header_separator = HEADER_SEPARATOR.as_bytes();
        let first_line_end = data.windows(header_separator.len())
            .position(|window| window == header_separator)
            .unwrap_or(data.len());
        
        let first_line = std::str::from_utf8(&data[..first_line_end])
            .map_err(|_| GurtError::InvalidMessage("Invalid UTF-8 in first line".to_string()))?;
        
        if first_line.starts_with(PROTOCOL_PREFIX) {
            Ok(GurtMessage::Response(GurtResponse::parse_bytes(data)?))
        } else {
            Ok(GurtMessage::Request(GurtRequest::parse_bytes(data)?))
        }
    }
    
    pub fn is_request(&self) -> bool {
        matches!(self, GurtMessage::Request(_))
    }
    
    pub fn is_response(&self) -> bool {
        matches!(self, GurtMessage::Response(_))
    }
    
    pub fn as_request(&self) -> Option<&GurtRequest> {
        match self {
            GurtMessage::Request(req) => Some(req),
            _ => None,
        }
    }
    
    pub fn as_response(&self) -> Option<&GurtResponse> {
        match self {
            GurtMessage::Response(res) => Some(res),
            _ => None,
        }
    }
}

impl fmt::Display for GurtMessage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            GurtMessage::Request(req) => write!(f, "{}", req.to_string()),
            GurtMessage::Response(res) => write!(f, "{}", res.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_request_parsing() {
        let raw = "GET /test GURT/1.0.0\r\nHost: example.com\r\nAccept: text/html\r\n\r\ntest body";
        let request = GurtRequest::parse(raw).expect("Failed to parse request");
        
        assert_eq!(request.method, GurtMethod::GET);
        assert_eq!(request.path, "/test");
        assert_eq!(request.version, GURT_VERSION.to_string());
        assert_eq!(request.header("host"), Some(&"example.com".to_string()));
        assert_eq!(request.header("accept"), Some(&"text/html".to_string()));
        assert_eq!(request.text().unwrap(), "test body");
    }
    
    #[test]
    fn test_response_parsing() {
        let raw = "GURT/1.0.0 200 OK\r\nContent-Type: text/html\r\n\r\n<html></html>";
        let response = GurtResponse::parse(raw).expect("Failed to parse response");
        
        assert_eq!(response.version, GURT_VERSION.to_string());
        assert_eq!(response.status_code, 200);
        assert_eq!(response.status_message, "OK");
        assert_eq!(response.header("content-type"), Some(&"text/html".to_string()));
        assert_eq!(response.text().unwrap(), "<html></html>");
    }
    
    #[test]
    fn test_request_building() {
        let request = GurtRequest::new(GurtMethod::GET, "/test".to_string())
            .with_header("Host", "example.com")
            .with_string_body("test body");
        
        let raw = request.to_string();
        let parsed = GurtRequest::parse(&raw).expect("Failed to parse built request");
        
        assert_eq!(parsed.method, request.method);
        assert_eq!(parsed.path, request.path);
        assert_eq!(parsed.body, request.body);
    }
    
    #[test]
    fn test_response_building() {
        let response = GurtResponse::ok()
            .with_header("Content-Type", "text/html")
            .with_string_body("<html></html>");
        
        let raw = response.to_string();
        let parsed = GurtResponse::parse(&raw).expect("Failed to parse built response");
        
        assert_eq!(parsed.status_code, response.status_code);
        assert_eq!(parsed.body, response.body);
    }
}