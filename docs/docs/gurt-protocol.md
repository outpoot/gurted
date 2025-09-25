---
sidebar_position: 2
---

# GURT Protocol

**GURT** (version 1.0.0) is a TCP-based application protocol designed as an HTTP-like alternative with built-in TLS 1.3 encryption. It serves as the foundation for the Gurted ecosystem, enabling secure communication between clients and servers using the `gurt://` URL scheme.

## Overview

GURT provides a familiar HTTP-like syntax while offering security through mandatory TLS 1.3 encryption. Unlike HTTP where encryption is optional (HTTPS), all GURT connections are encrypted by default.

### Key Features

- **HTTP-like syntax** with familiar methods (GET, POST, PUT, DELETE, etc.)
- **Built-in required TLS 1.3 encryption** for all connections
- **Binary and text data support**
- **Status codes** compatible with HTTP semantics
- **Default port**: 4878
- **ALPN identifier**: `GURT/1.0`

## URL Scheme

GURT uses the `gurt://` URL scheme:

```
gurt://example.com/path
gurt://192.168.1.100:4878/api/data
gurt://localhost:4878/hello
```

The protocol automatically defaults to port 4878.

## Communication Flow

Every GURT session must begin with a `HANDSHAKE` request:

```http
HANDSHAKE / GURT/1.0.0\r\n
host: example.com\r\n
user-agent: GURT-Client/1.0.0\r\n
\r\n
```

Server responds with protocol confirmation:

```http
GURT/1.0.0 101 SWITCHING_PROTOCOLS\r\n
gurt-version: 1.0.0\r\n
encryption: TLS/1.3\r\n
alpn: GURT/1.0\r\n
server: GURT/1.0.0\r\n
date: Wed, 01 Jan 2020 00:00:00 GMT\r\n
\r\n
```

## Message Format

### Request Structure

```http
METHOD /path GURT/1.0.0\r\n
header-name: header-value\r\n
content-length: 123\r\n
user-agent: GURT-Client/1.0.0\r\n
\r\n
[message body]
```

**Components:**
- **Method line**: `METHOD /path GURT/1.0.0`
- **Headers**: Lowercase names, colon-separated values
- **Header terminator**: `\r\n\r\n`
- **Body**: Optional message content

### Response Structure

```http
GURT/1.0.0 200 OK\r\n
content-type: application/json\r\n
content-length: 123\r\n
server: GURT/1.0.0\r\n
date: Wed, 01 Jan 2020 00:00:00 GMT\r\n
\r\n
[response body]
```

**Components:**
- **Status line**: `GURT/1.0.0 <code> <message>`
- **Headers**: Lowercase names, required for responses
- **Body**: Optional response content

## HTTP Methods

GURT supports all standard HTTP methods:

| Method | Purpose | Body Allowed |
|--------|---------|--------------|
| `GET` | Retrieve resource | No |
| `POST` | Create/submit data | Yes |
| `PUT` | Update/replace resource | Yes |
| `DELETE` | Remove resource | No |
| `HEAD` | Get headers only | No |
| `OPTIONS` | Get allowed methods | No |
| `PATCH` | Partial update | Yes |
| `HANDSHAKE` | Protocol handshake | No |

## Status Codes

GURT uses HTTP-compatible status codes:

### Success (2xx)
- `200 OK` - Request successful
- `201 CREATED` - Resource created
- `202 ACCEPTED` - Request accepted for processing
- `204 NO_CONTENT` - Success with no response body

### Protocol (1xx)
- `101 SWITCHING_PROTOCOLS` - Handshake successful

### Client Error (4xx)
- `400 BAD_REQUEST` - Invalid request format
- `401 UNAUTHORIZED` - Authentication required
- `403 FORBIDDEN` - Access denied
- `404 NOT_FOUND` - Resource not found
- `405 METHOD_NOT_ALLOWED` - Method not supported
- `408 TIMEOUT` - Request timeout
- `413 TOO_LARGE` - Request too large
- `415 UNSUPPORTED_MEDIA_TYPE` - Unsupported content type

### Server Error (5xx)
- `500 INTERNAL_SERVER_ERROR` - Server error
- `501 NOT_IMPLEMENTED` - Method not implemented
- `502 BAD_GATEWAY` - Gateway error
- `503 SERVICE_UNAVAILABLE` - Service unavailable
- `504 GATEWAY_TIMEOUT` - Gateway timeout

## Security

All connections must use TLS 1.3 for encryption. This means you have to generate and use a valid TLS certificate for your GURT server.

### Setup for Production

For production deployments, you'll need to install GurtCA from the Github repository for Gurted, and use it to request certificates for your domain.

1. **Generate production certificates with GurtCA:**
   ```bash
   gurtca request yourdomain.real --output ./certs
   ```

2. **Deploy with production certificates:**
   ```bash
   cargo run --release serve --cert ./certs/yourdomain.real.crt --key ./certs/yourdomain.real.key --host 0.0.0.0 --port 4878
   ```

Be careful, your `.key` file is the private key, do not share it with anyone!

### Development Environment Setup

To set up a development environment for GURT, follow these steps:
1. **Install mkcert:**
   ```bash
   # Windows (with Chocolatey)
   choco install mkcert
   
   # Or download from: https://github.com/FiloSottile/mkcert/releases
   ```

2. **Install local CA in system:**
   ```bash
   mkcert -install
   ```
   This installs a local CA in your **system certificate store**.

3. **Generate localhost certificates:**
   ```bash
   cd gurted/protocol/cli
   mkcert localhost 127.0.0.1 ::1
   ```
   This creates:
   - `localhost+2.pem` (certificate)
   - `localhost+2-key.pem` (private key)

4. **Start GURT server with certificates:**
   ```bash
   gurty serve --cert localhost+2.pem --key localhost+2-key.pem
   ```
Install Gurty, the official GURT server tool, [on the Gurted.com download page](https://gurted.com/download/)

## Protocol Limits

| Parameter | Limit |
|-----------|-------|
| Maximum message size | 10 MB |
| Default connection timeout | 10 seconds |
| Default request timeout | 30 seconds |
| Default handshake timeout | 5 seconds |
| Maximum connection pool size | 10 connections |
| Pool idle timeout | 300 seconds |

## Example Session

Complete GURT communication example:

```http
# Client connects and sends handshake
HANDSHAKE / GURT/1.0.0\r\n
host: example.com\r\n
user-agent: GURT-Client/1.0.0\r\n
\r\n

# Server confirms protocol
GURT/1.0.0 101 SWITCHING_PROTOCOLS\r\n
gurt-version: 1.0.0\r\n
encryption: TLS/1.3\r\n
alpn: GURT/1.0\r\n
server: GURT/1.0.0\r\n
date: Wed, 14 Aug 2025 12:00:00 GMT\r\n
\r\n

# All further communication is encrypted
# Client sends JSON data
POST /api/data GURT/1.0.0\r\n
host: example.com\r\n
content-type: application/json\r\n
content-length: 17\r\n
user-agent: GURT-Client/1.0.0\r\n
\r\n
{"foo":"bar","x":1}

# Server responds with JSON
GURT/1.0.0 200 OK\r\n
content-type: application/json\r\n
content-length: 16\r\n
server: GURT/1.0.0\r\n
date: Wed, 14 Aug 2025 12:00:01 GMT\r\n
\r\n
{"result":"ok"}
```

## Domain Resolution

GURT integrates with Gurted's custom DNS system:

### Direct IP Access
```
gurt://192.168.1.100:4878/
gurt://localhost:4878/api
```

### Domain Resolution
```
gurt://example.real/  # Resolves via Gurted DNS
```

The Gurted DNS server resolves domains in the format `name.tld` to IP addresses, enabling human-readable domain names for GURT services. This is done automatically by your GURT browser and is documented in the [DNS System documentation](./dns-system.md).

## Implementation

GURT is implemented in Rust with the following components:

- **Protocol Library**: Core protocol implementation, reusable as a Rust crate
- **CLI Tool (Gurty)**: Server setup and management
- **Godot Extension**: Browser integration for Flumi


## Alternative JavaScript implementation

GURT is also implemented in Node.js:

### Installation

Add the GURT library to your Node.js project:

```bash
npm i gurtjs
```
Then add these lines to your ```index.js``` file:
```javascript
const fs = require("fs");
const GURTServer = require("gurtjs/server");
```
or add these to ```index.js``` if creating an ES Module:
```javascript
import fs = from "fs";
import GURTServer from "gurtjs/server";
```

### Creating a Server


```javascript
const server = new GURTServer({});

// Start the server
server.listen(4878, () => {
console.log("GURT server listening on port 4878");
});
```

### Server with TLS Certificates

```javascript
const  server  =  new  GURTServer({
	tls: {
		key:  fs.readFileSync("example-website.web.key"),
		cert:  fs.readFileSync("example-website.web.crt"),
		//these files should be placed in the same directory as index.js
	},
	isServer:  true,
	forceServername:  "example-website.web",
	debug:  true,
	isLocalCert:  false,
	requestCert:  false, // do not require client certificate
	rejectUnauthorized:  false  // accept unverified clients
});

// Start the server
server.listen(4878, () => {
console.log("GURT server listening on port 4878");
});
```


### Method-Specific Routes
Typically, code blocks like these are placed after the server variable is defined and before the server is started.

GET route:
```javascript
server.get("/", ({ socket }) => {
  const body = "<body><p>Hello World</p></body>";
  socket.write(
    `GURT/1.0.0 200 OK\r\ncontent-type: text/plain\r\ncontent-length: ${Buffer.byteLength(
 body
 )}\r\nserver: GURT/1.0.0\r\n\r\n${body}`
  );
});
```
POST route:
```javascript
server.post("/submit", ({ socket, body }) => {
  console.log("[POST body]", body.trim());
  const resBody = "POST received";
  socket.write(
    `GURT/1.0.0 200 OK\r\ncontent-type: text/plain\r\ncontent-length: ${Buffer.byteLength(
 resBody
 )}\r\nserver: GURT/1.0.0\r\n\r\n${resBody}`
  );
});
```
PATCH route:
```javascript
server.patch("/update", ({ socket, body }) => {
  console.log("[PATCH body]", body.trim());
  const resBody = "PATCH received";
  socket.write(
    `GURT/1.0.0 200 OK\r\ncontent-type: text/plain\r\ncontent-length: ${Buffer.byteLength(
 resBody
 )}\r\nserver: GURT/1.0.0\r\n\r\n${resBody}`
  );
});
```
OPTIONS route:
```javascript
server.options("/", ({ socket }) => {
  const resBody = "";
  const response =
    `GURT/1.0.0 204 No Content\r\n` +
    "allow: GET, POST, PATCH, OPTIONS, HEAD\r\n" +
    "server: GURT/1.0.0\r\n\r\n" +
    resBody;
  socket.write(response);
});
```
HEAD route:
```javascript
server.head("/", ({ socket }) => {
  const resBody = "";
  const response =
    `GURT/1.0.0 200 OK\r\n` +
    "content-type: text/plain\r\n" +
    `content-length: 11\r\n` + // matches "Hello GET World"
    "server: GURT/1.0.0\r\n\r\n" +
    resBody;
  socket.write(response);
});
```
Any method can use the url variable to retrieve the connected client's url:
```javascript
server.get("/url", ({ socket, url }) => {
  console.log("[GET url]", url);
  const body = "<body><p>You connected from the url: " + url + "</p></body>";
  socket.write(
    `GURT/1.0.0 200 OK\r\ncontent-type: text/plain\r\ncontent-length: ${Buffer.byteLength(
 body
 )}\r\nserver: GURT/1.0.0\r\n\r\n${body}`
  );
});
```
### Response Building
Response headers follow a similar format to HTTP headers.
```javascript
socket.write(`GURT/1.0.0 200 OK\r\ncontent-type: text/plain`);
```
The protocol: ```GURT/1.0.0```

Status code:```200 OK```

Content type: ```text/plain```


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

For production, generate certificates with GurtCA:

```bash
git clone https://github.com/outpoot/gurted
cd gurted\protocol\gurtca
cargo build --release
cd target/release
chmod +x gurtca
./gurtca request your-site.web
```

### Deployment

```bash
cd path/to/index/file/
node index.js
```
