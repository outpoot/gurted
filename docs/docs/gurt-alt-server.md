
---
sidebar_position: 5
---

# GURT Alternative JavaScript Server Library

The GURT alternative JavaScript server library provides a framework for building HTTP-like servers that use the GURT protocol. It features automatic TLS handling and route-based request handling.

## Installation

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

## Creating a Server

### Basic Server

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

## Route Handlers

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
## Response Building
Response headers follow a similar format to HTTP headers.
```javascript
socket.write(`GURT/1.0.0 200 OK\r\ncontent-type: text/plain`);
```
The protocol: ```GURT/1.0.0```

Status code:```200 OK```

Content type: ```text/plain```



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

For production, generate certificates with GurtCA:

```bash
git clone https://github.com/outpoot/gurted
cd gurted\protocol\gurtca
cargo build --release
cd target/release
chmod +x gurtca
./gurtca request your-site.web
```

## Deployment

```bash
cd path/to/index/file/
node index.js
```
