# ZH3 HTTP Server

ZH3 includes a complete HTTP server implementation that allows you to run real web servers with your applications.

## 🚀 Quick Start

### Basic Server

```zig
const std = @import("std");
const zh3 = @import("zh3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = zh3.H3.init(allocator);
    defer app.deinit();

    _ = app.get("/", homeHandler);

    // Start server on port 3000
    try zh3.serve(&app, .{ .port = 3000 });
}

fn homeHandler(event: *zh3.H3Event) !void {
    try zh3.utils.send(event, "Hello from ZH3 HTTP Server!");
}
```

### Run the Server

```bash
# Build and run
zig build run-http_server

# Or build first, then run
zig build
./zig-out/bin/http_server
```

## 🔧 Server Configuration

### ServeOptions

```zig
pub const ServeOptions = struct {
    port: u16 = 3000,           // Server port
    host: []const u8 = "127.0.0.1",  // Bind address
    backlog: u32 = 128,         // Connection backlog
};
```

### Examples

```zig
// Default configuration (127.0.0.1:3000)
try zh3.serve(&app, .{});

// Custom port
try zh3.serve(&app, .{ .port = 8080 });

// Custom host and port
try zh3.serve(&app, .{
    .host = "0.0.0.0",
    .port = 8080
});

// Full configuration
try zh3.serve(&app, .{
    .host = "0.0.0.0",
    .port = 8080,
    .backlog = 256,
});
```

## 🌐 HTTP Features

### Supported HTTP Methods
- ✅ GET
- ✅ POST
- ✅ PUT
- ✅ DELETE
- ✅ PATCH
- ✅ OPTIONS
- ✅ HEAD

### Request Parsing
- ✅ HTTP/1.1 protocol
- ✅ Request line parsing (method, URL, version)
- ✅ Header parsing
- ✅ Query parameter extraction
- ✅ Request body handling
- ✅ URL path parameters

### Response Generation
- ✅ Status codes
- ✅ Custom headers
- ✅ Response body
- ✅ Content-Type handling
- ✅ CORS headers

## 📋 Complete Example

Here's a comprehensive example showing various features:

```zig
const std = @import("std");
const zh3 = @import("zh3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = zh3.H3.init(allocator);
    defer app.deinit();

    // Middleware
    _ = app.use(zh3.utils.logger);
    _ = app.use(zh3.utils.cors("*"));

    // Routes
    _ = app.get("/", homeHandler);
    _ = app.get("/api/health", healthHandler);
    _ = app.get("/api/users/:id", getUserHandler);
    _ = app.post("/api/users", createUserHandler);
    _ = app.put("/api/users/:id", updateUserHandler);
    _ = app.delete("/api/users/:id", deleteUserHandler);

    std.log.info("🚀 Server starting on http://127.0.0.1:3000", .{});

    try zh3.serve(&app, .{
        .host = "127.0.0.1",
        .port = 3000,
    });
}

fn homeHandler(event: *zh3.H3Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>ZH3 Server</title></head>
        \\<body>
        \\  <h1>Welcome to ZH3!</h1>
        \\  <p>Your HTTP server is running.</p>
        \\</body>
        \\</html>
    ;

    try event.setHeader("Content-Type", "text/html");
    try zh3.utils.send(event, html);
}

fn healthHandler(event: *zh3.H3Event) !void {
    const health = .{
        .status = "healthy",
        .timestamp = std.time.timestamp(),
        .server = "ZH3",
    };

    try zh3.utils.sendJsonValue(event, health);
}

fn getUserHandler(event: *zh3.H3Event) !void {
    const user_id = zh3.utils.getParam(event, "id") orelse {
        try zh3.utils.badRequest(event, "Missing user ID");
        return;
    };

    const user = .{
        .id = user_id,
        .name = "John Doe",
        .email = "john@example.com",
    };

    try zh3.utils.sendJsonValue(event, user);
}

fn createUserHandler(event: *zh3.H3Event) !void {
    const CreateUserRequest = struct {
        name: []const u8,
        email: []const u8,
    };

    const req = zh3.utils.readJson(event, CreateUserRequest) catch {
        try zh3.utils.badRequest(event, "Invalid JSON");
        return;
    };

    const user = .{
        .id = "123",
        .name = req.name,
        .email = req.email,
        .created_at = std.time.timestamp(),
    };

    event.setStatus(.created);
    try zh3.utils.sendJsonValue(event, user);
}

fn updateUserHandler(event: *zh3.H3Event) !void {
    const user_id = zh3.utils.getParam(event, "id") orelse {
        try zh3.utils.badRequest(event, "Missing user ID");
        return;
    };

    const response = .{
        .message = "User updated",
        .user_id = user_id,
        .updated_at = std.time.timestamp(),
    };

    try zh3.utils.sendJsonValue(event, response);
}

fn deleteUserHandler(event: *zh3.H3Event) !void {
    const user_id = zh3.utils.getParam(event, "id") orelse {
        try zh3.utils.badRequest(event, "Missing user ID");
        return;
    };

    _ = user_id;
    event.setStatus(.no_content);
    try zh3.utils.send(event, "");
}
```

## 🧪 Testing Your Server

### Using curl

```bash
# GET request
curl http://localhost:3000/

# GET with path parameter
curl http://localhost:3000/api/users/123

# POST with JSON
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice", "email": "alice@example.com"}'

# PUT request
curl -X PUT http://localhost:3000/api/users/123 \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice Updated"}'

# DELETE request
curl -X DELETE http://localhost:3000/api/users/123
```

### Using a Web Browser

Navigate to `http://localhost:3000` to see your HTML pages.

## 🔧 Server Architecture

### Request Flow

1. **Accept Connection** - Server accepts incoming TCP connections
2. **Parse Request** - HTTP request is parsed into H3Event
3. **Route Matching** - URL is matched against registered routes
4. **Middleware Chain** - Middleware functions are executed in order
5. **Handler Execution** - Route handler processes the request
6. **Response Generation** - HTTP response is formatted and sent

### Connection Handling

- **Single-threaded** - Current implementation handles one connection at a time
- **Blocking I/O** - Uses synchronous network operations
- **Memory efficient** - Fixed buffer sizes for request/response

### Future Improvements

- **Multi-threading** - Handle multiple connections concurrently
- **Async I/O** - Non-blocking network operations
- **HTTP/2 support** - Modern HTTP protocol features
- **WebSocket support** - Real-time communication
- **Static file serving** - Built-in file server
- **Request streaming** - Handle large request bodies
- **Response compression** - Gzip/deflate support

## 🛡️ Production Considerations

### Security
- Input validation
- Request size limits
- Rate limiting
- HTTPS/TLS support

### Performance
- Connection pooling
- Keep-alive connections
- Response caching
- Load balancing

### Monitoring
- Request logging
- Error tracking
- Performance metrics
- Health checks

## 📚 API Reference

### Functions

```zig
// Start server with options
pub fn serve(app: *H3, options: ServeOptions) !void

// Start server with defaults
pub fn serveDefault(app: *H3) !void
```

### Types

```zig
pub const ServeOptions = struct {
    port: u16 = 3000,
    host: []const u8 = "127.0.0.1",
    backlog: u32 = 128,
};

pub const Server = struct {
    // Server implementation
};
```

## 🎯 Next Steps

1. **Try the examples** - Run the provided HTTP server examples
2. **Build your API** - Create your own REST API
3. **Add middleware** - Implement custom middleware
4. **Deploy** - Run your server in production
5. **Contribute** - Help improve the HTTP server implementation

The ZH3 HTTP server provides a solid foundation for building web applications and APIs with Zig!
