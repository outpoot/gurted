---
sidebar_position: 3
---

# GURT Client Library

The GURT client library (for Rust) provides a high-level, HTTP-like interface for making requests to GURT servers. It handles TLS encryption, protocol handshakes, and connection management automatically.

## Bindings
- **Godot** by Gurted - [🔗 link](https://gurted.com/download)
- No bidings for other languages are currently available.

## Installation

Install via Cargo:
```bash
cargo add gurtlib
```

## Quick Start

```rust
use gurtlib::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    let client = GurtClient::new();
    
    // Make a GET request
    let response = client.get("gurt://example.com/").await?;
    
    println!("Status: {}", response.status_code);
    println!("Body: {}", response.text()?);
    
    Ok(())
}
```

## Creating a Client

### Default Client

```rust
let client = GurtClient::new();
```

### Custom Configuration

```rust
use tokio::time::Duration;

let config = GurtClientConfig {
    connect_timeout: Duration::from_secs(10),
    request_timeout: Duration::from_secs(30),
    handshake_timeout: Duration::from_secs(5),
    user_agent: "MyApp/1.0.0".to_string(),
    max_redirects: 5,
};

let client = GurtClient::with_config(config);
```

## Making Requests

### GET Requests

```rust
let response = client.get("gurt://api.example.com/users").await?;

if response.is_success() {
    println!("Success: {}", response.text()?);
} else {
    println!("Error: {} {}", response.status_code, response.status_message);
}
```

### POST Requests

#### Text Data
```rust
let response = client.post("gurt://api.example.com/submit", "Hello, GURT!").await?;
```

#### JSON Data
```rust
use serde_json::json;

let data = json!({
    "name": "John Doe",
    "email": "john@example.com"
});

let response = client.post_json("gurt://api.example.com/users", &data).await?;
```

### PUT Requests

```rust
// Text data
let response = client.put("gurt://api.example.com/resource/123", "Updated content").await?;

// JSON data
let update_data = json!({"status": "completed"});
let response = client.put_json("gurt://api.example.com/tasks/456", &update_data).await?;
```

### DELETE Requests

```rust
let response = client.delete("gurt://api.example.com/users/123").await?;
```

### HEAD Requests

```rust
let response = client.head("gurt://api.example.com/large-file").await?;

// Check headers without downloading body
let content_length = response.headers.get("content-length");
```

### OPTIONS Requests

```rust
let response = client.options("gurt://api.example.com/endpoint").await?;

// Check allowed methods
let allowed_methods = response.headers.get("allow");
```

### PATCH Requests

```rust
let patch_data = json!({"name": "Updated Name"});
let response = client.patch_json("gurt://api.example.com/users/123", &patch_data).await?;
```

## Response Handling

### Response Structure

```rust
pub struct GurtResponse {
    pub version: String,
    pub status_code: u16,
    pub status_message: String,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}
```

### Accessing Response Data

```rust
let response = client.get("gurt://api.example.com/data").await?;

// Status information
println!("Status Code: {}", response.status_code);
println!("Status Message: {}", response.status_message);

// Headers
for (name, value) in &response.headers {
    println!("{}: {}", name, value);
}

// Body as string
let text = response.text()?;

// Body as bytes
let bytes = &response.body;

// Parse JSON response
let json_data: serde_json::Value = serde_json::from_slice(&response.body)?;
```

### Status Code Checking

```rust
if response.is_success() {
    // 2xx status codes
    println!("Request successful");
} else if response.is_client_error() {
    // 4xx status codes
    println!("Client error: {}", response.status_message);
} else if response.is_server_error() {
    // 5xx status codes
    println!("Server error: {}", response.status_message);
}
```

## Protocol Implementation

The GURT client automatically handles the complete GURT protocol:

1. **TCP Connection**: Establishes initial connection to the server
2. **Handshake**: Sends `HANDSHAKE` request and waits for `101 Switching Protocols`
3. **TLS Upgrade**: Upgrades the connection to TLS 1.3 with GURT ALPN
4. **Request/Response**: Sends the actual HTTP-style request over encrypted connection

All of this happens transparently when you call methods like `get()`, `post()`, etc.

## URL Parsing

The client automatically parses `gurt://` URLs:

```rust
// These are all valid GURT URLs:
client.get("gurt://example.com/").await?;              // Port 4878 (default)
client.get("gurt://example.com:8080/api").await?;      // Custom port
client.get("gurt://192.168.1.100/test").await?;        // IP address
client.get("gurt://localhost:4878/dev").await?;        // Localhost
```

### URL Components

The client extracts:
- **Host**: Domain name or IP address
- **Port**: Specified port or default (4878)
- **Path**: Request path (defaults to `/`)

## Error Handling

### Error Types

```rust
use gurtlib::GurtError;

match client.get("gurt://invalid-url").await {
    Ok(response) => {
        // Handle successful response
    }
    Err(GurtError::InvalidMessage(msg)) => {
        println!("Invalid request: {}", msg);
    }
    Err(GurtError::Connection(msg)) => {
        println!("Connection error: {}", msg);
    }
    Err(GurtError::Timeout(msg)) => {
        println!("Request timeout: {}", msg);
    }
    Err(GurtError::Io(err)) => {
        println!("IO error: {}", err);
    }
    Err(err) => {
        println!("Other error: {}", err);
    }
}
```

### Timeout Configuration

```rust
let config = GurtClientConfig {
    connect_timeout: Duration::from_secs(5),    // Connection timeout
    request_timeout: Duration::from_secs(30),   // Overall request timeout
    handshake_timeout: Duration::from_secs(3),  // GURT handshake timeout
    ..Default::default()
};
```

## Why Rust-first?
Rust was chosen for the official GURT protocol implementation due to its embedded nature.

To keep the core organized & not write identical code in GDScript, we used a GDExtension. A GDExtension can be created with a multitude of languages, but Rust was the one that provided the best performance, size, and programming ergonomics.

We expect the community to implement bindings for other languages, such as Python and JavaScript, to make GURT accessible for everybody!

## Example: Building a GURT API Client

```rust
use gurtlib::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
struct CreateUser {
    name: String,
    email: String,
}

#[derive(Deserialize)]
struct User {
    id: u64,
    name: String,
    email: String,
}

struct ApiClient {
    client: GurtClient,
    base_url: String,
}

impl ApiClient {
    fn new(base_url: String) -> Self {
        Self {
            client: GurtClient::new(),
            base_url,
        }
    }
    
    async fn create_user(&self, user: CreateUser) -> Result<User> {
        let url = format!("{}/users", self.base_url);
        let response = self.client.post_json(&url, &user).await?;
        
        if !response.is_success() {
            return Err(GurtError::invalid_message(
                format!("API error: {}", response.status_message)
            ));
        }
        
        let user: User = serde_json::from_slice(&response.body)?;
        Ok(user)
    }
    
    async fn get_user(&self, id: u64) -> Result<User> {
        let url = format!("{}/users/{}", self.base_url, id);
        let response = self.client.get(&url).await?;
        
        if response.status_code == 404 {
            return Err(GurtError::invalid_message("User not found".to_string()));
        }
        
        if !response.is_success() {
            return Err(GurtError::invalid_message(
                format!("API error: {}", response.status_message)
            ));
        }
        
        let user: User = serde_json::from_slice(&response.body)?;
        Ok(user)
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let api = ApiClient::new("gurt://api.example.com".to_string());
    
    // Create a user
    let new_user = CreateUser {
        name: "Alice".to_string(),
        email: "alice@example.com".to_string(),
    };
    
    let user = api.create_user(new_user).await?;
    println!("Created user: {} (ID: {})", user.name, user.id);
    
    // Retrieve the user
    let retrieved_user = api.get_user(user.id).await?;
    println!("Retrieved user: {}", retrieved_user.name);
    
    Ok(())
}
```
