// src/protocol.rs
use std::fmt;

pub const GURT_VERSION: &str = "1.0.0";
pub const DEFAULT_PORT: u16 = 4878;

pub const PROTOCOL_PREFIX: &str = "GURT/";

pub const HEADER_SEPARATOR: &str = "\r\n";
pub const BODY_SEPARATOR: &str = "\r\n\r\n";

pub const DEFAULT_HANDSHAKE_TIMEOUT: u64 = 5;
pub const DEFAULT_REQUEST_TIMEOUT: u64 = 30;
pub const DEFAULT_CONNECTION_TIMEOUT: u64 = 10;

pub const MAX_MESSAGE_SIZE: usize = 10 * 1024 * 1024;

pub const MAX_POOL_SIZE: usize = 10;
pub const POOL_IDLE_TIMEOUT: u64 = 300;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GurtStatusCode {
    // Success
    Ok = 200,
    Created = 201,
    Accepted = 202,
    NoContent = 204,

    // Handshake
    SwitchingProtocols = 101,

    // Client errors
    BadRequest = 400,
    Unauthorized = 401,
    Forbidden = 403,
    NotFound = 404,
    MethodNotAllowed = 405,
    Timeout = 408,
    TooLarge = 413,
    UnsupportedMediaType = 415,
    TooManyRequests = 429,

    // Server errors
    InternalServerError = 500,
    NotImplemented = 501,
    BadGateway = 502,
    ServiceUnavailable = 503,
    GatewayTimeout = 504,
}

impl GurtStatusCode {
    pub fn from_u16(code: u16) -> Option<Self> {
        match code {
            200 => Some(Self::Ok),
            201 => Some(Self::Created),
            202 => Some(Self::Accepted),
            204 => Some(Self::NoContent),
            101 => Some(Self::SwitchingProtocols),
            400 => Some(Self::BadRequest),
            401 => Some(Self::Unauthorized),
            403 => Some(Self::Forbidden),
            404 => Some(Self::NotFound),
            405 => Some(Self::MethodNotAllowed),
            408 => Some(Self::Timeout),
            413 => Some(Self::TooLarge),
            415 => Some(Self::UnsupportedMediaType),
            429 => Some(Self::TooManyRequests),
            500 => Some(Self::InternalServerError),
            501 => Some(Self::NotImplemented),
            502 => Some(Self::BadGateway),
            503 => Some(Self::ServiceUnavailable),
            504 => Some(Self::GatewayTimeout),
            _ => None,
        }
    }

    pub fn message(&self) -> &'static str {
        match self {
            Self::Ok => "OK",
            Self::Created => "CREATED",
            Self::Accepted => "ACCEPTED",
            Self::NoContent => "NO_CONTENT",
            Self::SwitchingProtocols => "SWITCHING_PROTOCOLS",
            Self::BadRequest => "BAD_REQUEST",
            Self::Unauthorized => "UNAUTHORIZED",
            Self::Forbidden => "FORBIDDEN",
            Self::NotFound => "NOT_FOUND",
            Self::MethodNotAllowed => "METHOD_NOT_ALLOWED",
            Self::Timeout => "TIMEOUT",
            Self::TooLarge => "TOO_LARGE",
            Self::UnsupportedMediaType => "UNSUPPORTED_MEDIA_TYPE",
            Self::TooManyRequests => "TOO_MANY_REQUESTS",
            Self::InternalServerError => "INTERNAL_SERVER_ERROR",
            Self::NotImplemented => "NOT_IMPLEMENTED",
            Self::BadGateway => "BAD_GATEWAY",
            Self::ServiceUnavailable => "SERVICE_UNAVAILABLE",
            Self::GatewayTimeout => "GATEWAY_TIMEOUT",
        }
    }

    pub fn is_success(&self) -> bool {
        matches!(
            self,
            Self::Ok | Self::Created | Self::Accepted | Self::NoContent
        )
    }

    pub fn is_client_error(&self) -> bool {
        (*self as u16) >= 400 && (*self as u16) < 500
    }

    pub fn is_server_error(&self) -> bool {
        (*self as u16) >= 500
    }
}

impl From<GurtStatusCode> for u16 {
    fn from(code: GurtStatusCode) -> Self {
        code as u16
    }
}

impl fmt::Display for GurtStatusCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", *self as u16)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_messages() {
        assert_eq!(GurtStatusCode::Ok.message(), "OK");
        assert!(GurtStatusCode::from_u16(404).unwrap().is_client_error());
    }
}