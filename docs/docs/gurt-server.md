---
sidebar_position: 4
---

# GURT Server Library

The GURT server library provides a framework for building HTTP-like servers that use the GURT protocol. It features automatic TLS handling, route-based request handling, and middleware support.

## Installation

Add the GURT library to your `Cargo.toml`:

```toml
[dependencies]
gurtlib = "0.1"
tokio = { version = "1.0", features = ["full"] }
tracing = "0.1"
tracing-subscriber = "0.3"
serde_json = "1.0"
```

## Quick Start

```rust
use gurtlib::prelude::*;
use serde_json::json;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    
    let server = GurtServer::with_tls_certificates("cert.pem", "key.pem")?
        .get("/", |_ctx| async {
            Ok(GurtResponse::ok().with_string_body("<h1>Hello, GURT!</h1>"))
        })
        .get("/api/users", |_ctx| async {
            let users = json!(["Alice", "Bob"]);
            Ok(GurtResponse::ok().with_json_body(&users))
        });
    
    println!("GURT server starting on gurt://127.0.0.1:4878");
    server.listen("127.0.0.1:4878").await
}
```

## Creating a Server

### Basic Server

```rust
let server = GurtServer::new();
```

### Server with TLS Certificates

```rust
// Load TLS certificates during server creation
let server = GurtServer::with_tls_certificates("cert.pem", "key.pem")?;

// Or load certificates later
let mut server = GurtServer::new();
server.load_tls_certificates("cert.pem", "key.pem")?;
```

## Route Handlers

### Method-Specific Routes

```rust
let server = GurtServer::with_tls_certificates("cert.pem", "key.pem")?
    .get("/", |_ctx| async {
        Ok(GurtResponse::ok().with_string_body("GET request"))
    })
    .post("/submit", |ctx| async {
        let body = ctx.text()?;
        println!("Received: {}", body);
        Ok(GurtResponse::new(GurtStatusCode::Created).with_string_body("Created"))
    })
    .put("/update", |_ctx| async {
        Ok(GurtResponse::ok().with_string_body("Updated"))
    })
    .delete("/delete", |_ctx| async {
        Ok(GurtResponse::new(GurtStatusCode::NoContent))
    })
    .patch("/partial", |_ctx| async {
        Ok(GurtResponse::ok().with_string_body("Patched"))
    });
```

### Any Method Route

```rust
let server = server.any("/webhook", |ctx| async {
    match ctx.method() {
        GurtMethod::GET => Ok(GurtResponse::ok().with_string_body("GET webhook")),
        GurtMethod::POST => Ok(GurtResponse::ok().with_string_body("POST webhook")),
        _ => Ok(GurtResponse::new(GurtStatusCode::MethodNotAllowed)),
    }
});
```

### Route Patterns

```rust
let server = server
    .get("/users", |_ctx| async {
        Ok(GurtResponse::ok().with_string_body("All users"))
    })
    .get("/users/*", |ctx| async {
        // Matches /users/123, /users/profile, etc.
        let path = ctx.path();
        Ok(GurtResponse::ok().with_string_body(format!("User path: {}", path)))
    })
    .get("/api/*", |_ctx| async {
        // Matches any path starting with /api/
        Ok(GurtResponse::ok().with_string_body("API endpoint"))
    });
```

## Server Context

The `ServerContext` provides access to request information:

```rust
.post("/analyze", |ctx| async {
    // Client information
    println!("Client IP: {}", ctx.client_ip());
    println!("Client Port: {}", ctx.client_port());
    
    // Request details
    println!("Method: {:?}", ctx.method());
    println!("Path: {}", ctx.path());
    
    // Headers
    if let Some(content_type) = ctx.header("content-type") {
        println!("Content-Type: {}", content_type);
    }
    
    // Iterate all headers
    for (name, value) in ctx.headers() {
        println!("{}: {}", name, value);
    }
    
    // Body data
    let body_bytes = ctx.body();
    let body_text = ctx.text()?;
    
    Ok(GurtResponse::ok().with_string_body("Analyzed"))
})
```

## Response Building

### Basic Responses

```rust
// Success responses
GurtResponse::ok()                                   // 200 OK
GurtResponse::new(GurtStatusCode::Created)           // 201 Created
GurtResponse::new(GurtStatusCode::Accepted)          // 202 Accepted
GurtResponse::new(GurtStatusCode::NoContent)         // 204 No Content

// Client error responses
GurtResponse::bad_request()                          // 400 Bad Request
GurtResponse::new(GurtStatusCode::Unauthorized)      // 401 Unauthorized
GurtResponse::new(GurtStatusCode::Forbidden)         // 403 Forbidden
GurtResponse::not_found()                            // 404 Not Found
GurtResponse::new(GurtStatusCode::MethodNotAllowed)  // 405 Method Not Allowed

// Server error responses
GurtResponse::internal_server_error()                 // 500 Internal Server Error
GurtResponse::new(GurtStatusCode::NotImplemented)     // 501 Not Implemented
GurtResponse::new(GurtStatusCode::ServiceUnavailable) // 503 Service Unavailable
```

### Response with Body

```rust
// String body
GurtResponse::ok().with_string_body("Hello, World!")

// JSON body
use serde_json::json;
let data = json!({"message": "Hello", "status": "success"});
GurtResponse::ok().with_json_body(&data)

// Binary body
let image_data = std::fs::read("image.png")?;
GurtResponse::ok()
    .with_header("content-type", "image/png")
    .with_body(image_data)
```

### Response with Headers

```rust
GurtResponse::ok()
    .with_string_body("Custom response")
    .with_header("x-custom-header", "custom-value")
    .with_header("cache-control", "no-cache")
    .with_header("content-type", "text/plain; charset=utf-8")
```

## Advanced Examples

### JSON API Server

```rust
use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Serialize, Deserialize)]
struct User {
    id: u64,
    name: String,
    email: String,
}

let server = GurtServer::with_tls_certificates("cert.pem", "key.pem")?
    .get("/api/users", |ctx| async {
        let users = vec![
            User { id: 1, name: "Alice".to_string(), email: "alice@example.com".to_string() },
            User { id: 2, name: "Bob".to_string(), email: "bob@example.com".to_string() },
        ];
        
        Ok(GurtResponse::ok()
            .with_header("content-type", "application/json")
            .with_json_body(&users))
    })
    .post("/api/users", |ctx| async {
        let body = ctx.text()?;
        let user: User = serde_json::from_str(&body)
            .map_err(|_| GurtError::invalid_message("Invalid JSON"))?;
        
        // Save user to database here...
        println!("Creating user: {}", user.name);
        
        Ok(GurtResponse::new(GurtStatusCode::Created)
            .with_header("content-type", "application/json")
            .with_json_body(&user)?)
    })
    .get("/api/users/*", |ctx| async {
        let path = ctx.path();
        if let Some(user_id) = path.strip_prefix("/api/users/") {
            if let Ok(id) = user_id.parse::<u64>() {
                // Get user from database here...
                let user = User {
                    id,
                    name: format!("User {}", id),
                    email: format!("user{}@example.com", id),
                };
                
                Ok(GurtResponse::ok()
                    .with_header("content-type", "application/json")
                    .with_json_body(&user))
            } else {
                Ok(GurtResponse::bad_request()
                    .with_string_body("Invalid user ID"))
            }
        } else {
            Ok(GurtResponse::not_found())
        }
    });
```

### File Server

```rust
use std::path::Path;
use tokio::fs;

let server = server.get("/files/*", |ctx| async {
    let path = ctx.path();
    let file_path = path.strip_prefix("/files/").unwrap_or("");
    
    // Security: prevent directory traversal
    if file_path.contains("..") {
        return Ok(GurtResponse::new(GurtStatusCode::Forbidden)
            .with_string_body("Access denied"));
    }
    
    let full_path = format!("./static/{}", file_path);
    
    match fs::read(&full_path).await {
        Ok(data) => {
            let content_type = match Path::new(&full_path).extension()
                .and_then(|ext| ext.to_str()) {
                Some("html") => "text/html",
                Some("css") => "text/css",
                Some("js") => "application/javascript",
                Some("json") => "application/json",
                Some("png") => "image/png",
                Some("jpg") | Some("jpeg") => "image/jpeg",
                Some("gif") => "image/gif",
                _ => "application/octet-stream",
            };
            
            Ok(GurtResponse::ok()
                .with_header("content-type", content_type)
                .with_body(data))
        }
        Err(_) => {
            Ok(GurtResponse::not_found()
                .with_string_body("File not found"))
        }
    }
});
```

### Middleware Pattern

```rust
// Request logging middleware
async fn log_request(ctx: &ServerContext) -> Result<()> {
    println!("{} {} from {}", 
        ctx.method(), 
        ctx.path(), 
        ctx.client_ip()
    );
    Ok(())
}

// Authentication middleware
async fn require_auth(ctx: &ServerContext) -> Result<()> {
    if let Some(auth_header) = ctx.header("authorization") {
        if auth_header.starts_with("Bearer ") {
            // Validate token here...
            return Ok(());
        }
    }
    Err(GurtError::invalid_message("Authentication required"))
}

let server = server
    .get("/protected", |ctx| async {
        // Apply middleware
        log_request(ctx).await?;
        require_auth(ctx).await?;
        
        Ok(GurtResponse::ok()
            .with_string_body("Protected content"))
    })
    .post("/api/data", |ctx| async {
        log_request(ctx).await?;
        
        // Handle request
        Ok(GurtResponse::ok()
            .with_string_body("Data processed"))
    });
```

### Error Handling

```rust
let server = server.post("/api/process", |ctx| async {
    match process_data(ctx).await {
        Ok(result) => {
            Ok(GurtResponse::ok()
                .with_json_body(&result))
        }
        Err(ProcessError::ValidationError(msg)) => {
            Ok(GurtResponse::bad_request()
                .with_json_body(&json!({"error": msg})))
        }
        Err(ProcessError::NotFound) => {
            Ok(GurtResponse::not_found()
                .with_json_body(&json!({"error": "Resource not found"})))
        }
        Err(_) => {
            Ok(GurtResponse::internal_server_error()
                .with_json_body(&json!({"error": "Internal server error"})))
        }
    }
});

async fn process_data(ctx: &ServerContext) -> Result<serde_json::Value, ProcessError> {
    // Your processing logic here
    todo!()
}

#[derive(Debug)]
enum ProcessError {
    ValidationError(String),
    NotFound,
    InternalError,
}
```

## TLS Configuration

### Development Certificates

For development, use `mkcert` to generate trusted local certificates:

```bash
# Install mkcert
choco install mkcert  # Windows
brew install mkcert   # macOS
# or download from GitHub releases

# Install local CA
mkcert -install

# Generate certificates
mkcert localhost 127.0.0.1 ::1
```

### Production Certificates

For production, generate certificates with OpenSSL:

```bash
# Generate private key
openssl genpkey -algorithm RSA -out server.key -pkcs8

# Generate certificate signing request
openssl req -new -key server.key -out server.csr

# Generate self-signed certificate
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

# Or in one step
openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -nodes
```

## Listening and Deployment

```rust
// Listen on all interfaces
server.listen("0.0.0.0:4878").await?;

// Listen on specific interface
server.listen("127.0.0.1:8080").await?;

// Listen on IPv6
server.listen("[::1]:4878").await?;
```

## Testing

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use gurtlib::GurtClient;
    
    #[tokio::test]
    async fn test_server() {
        let server = GurtServer::with_tls_certificates("test-cert.pem", "test-key.pem")
            .unwrap()
            .get("/test", |_ctx| async {
                Ok(GurtResponse::ok().with_string_body("test response"))
            });
        
        // Start server in background
        tokio::spawn(async move {
            server.listen("127.0.0.1:9999").await.unwrap();
        });
        
        // Give server time to start
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        
        // Test with client
        let client = GurtClient::new();
        let response = client.get("gurt://127.0.0.1:9999/test").await.unwrap();
        
        assert_eq!(response.status_code, 200);
        assert_eq!(response.text().unwrap(), "test response");
    }
}
```
