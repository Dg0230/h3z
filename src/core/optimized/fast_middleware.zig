//! Optimized fast middleware system with minimal overhead
//! Reduces per-request allocation and execution time

const std = @import("std");
const H3Event = @import("../event.zig").H3Event;
const Handler = @import("../handler.zig").Handler;

/// Optimized fast middleware function type with minimal overhead
pub const FastMiddleware = *const fn (*H3Event) anyerror!MiddlewareResult;

/// Middleware execution result
pub const MiddlewareResult = enum {
    continue_chain,
    terminate_early,
    error_occurred,
};

/// Optimized middleware chain with pre-compiled execution
pub const FastMiddlewareChain = struct {
    middlewares: [MAX_MIDDLEWARES]FastMiddleware,
    count: u8,

    // Pre-compiled execution flags
    has_logger: bool = false,
    has_cors: bool = false,
    has_security: bool = false,
    has_timing: bool = false,

    const MAX_MIDDLEWARES = 16; // Reasonable limit for performance

    pub fn init() FastMiddlewareChain {
        return FastMiddlewareChain{
            .middlewares = undefined,
            .count = 0,
        };
    }

    pub fn deinit(self: *FastMiddlewareChain) void {
        _ = self;
        // No cleanup needed for function pointers
    }

    /// Add a fast middleware to the chain
    pub fn use(self: *FastMiddlewareChain, middleware: FastMiddleware) !*FastMiddlewareChain {
        if (self.count >= MAX_MIDDLEWARES) {
            return error.TooManyMiddlewares;
        }

        self.middlewares[self.count] = middleware;
        self.count += 1;

        // Update execution flags for optimization
        self.updateExecutionFlags(middleware);

        return self;
    }

    /// Update execution flags based on middleware type
    fn updateExecutionFlags(self: *FastMiddlewareChain, middleware: FastMiddleware) void {
        // Compare function pointers to known middleware
        if (middleware == OptimizedMiddleware.logger) {
            self.has_logger = true;
        } else if (middleware == OptimizedMiddleware.cors) {
            self.has_cors = true;
        } else if (middleware == OptimizedMiddleware.security) {
            self.has_security = true;
        } else if (middleware == OptimizedMiddleware.timing) {
            self.has_timing = true;
        }
    }

    /// Execute the middleware chain with optimizations
    pub fn execute(self: *const FastMiddlewareChain, event: *H3Event, final_handler: Handler) !void {
        // Fast path for common middleware combinations
        if (self.count <= 3 and self.has_logger and self.has_cors) {
            try self.executeCommonPattern(event, final_handler);
            return;
        }

        // General execution path
        try self.executeGeneral(event, final_handler);
    }

    /// Execute common middleware pattern (logger + cors + optional security)
    fn executeCommonPattern(self: *const FastMiddlewareChain, event: *H3Event, final_handler: Handler) !void {
        // Inline common middleware execution for better performance

        // Logger (if present)
        if (self.has_logger) {
            // Inline simple logging to avoid function call overhead
            const method = event.getMethod();
            const path = event.getPath();
            std.log.info("{s} {s}", .{ method.toString(), path });
        }

        // CORS (if present)
        if (self.has_cors) {
            // Inline CORS headers
            try event.setHeader("Access-Control-Allow-Origin", "*");
            try event.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
            try event.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

            if (event.getMethod() == .OPTIONS) {
                event.setStatus(.no_content);
                return;
            }
        }

        // Security headers (if present)
        if (self.has_security) {
            try event.setHeader("X-Content-Type-Options", "nosniff");
            try event.setHeader("X-Frame-Options", "DENY");
            try event.setHeader("X-XSS-Protection", "1; mode=block");
        }

        // Execute final handler
        try final_handler(event);
    }

    /// Execute middleware chain in general case
    fn executeGeneral(self: *const FastMiddlewareChain, event: *H3Event, final_handler: Handler) !void {
        for (0..self.count) |i| {
            const result = try self.middlewares[i](event);
            switch (result) {
                .continue_chain => continue,
                .terminate_early => return,
                .error_occurred => return error.MiddlewareError,
            }
        }

        // Execute final handler
        try final_handler(event);
    }

    /// Execute with error handling
    pub fn executeWithErrorHandling(
        self: *const FastMiddlewareChain,
        event: *H3Event,
        final_handler: Handler,
        error_handler: ?*const fn (*H3Event, anyerror) anyerror!void,
    ) !void {
        self.execute(event, final_handler) catch |err| {
            if (error_handler) |handler| {
                try handler(event, err);
            } else {
                return err;
            }
        };
    }

    /// Get middleware count
    pub fn getCount(self: *const FastMiddlewareChain) u8 {
        return self.count;
    }

    /// Clear all middlewares
    pub fn clear(self: *FastMiddlewareChain) void {
        self.count = 0;
        self.has_logger = false;
        self.has_cors = false;
        self.has_security = false;
        self.has_timing = false;
    }
};

/// Optimized common middleware implementations
pub const OptimizedMiddleware = struct {
    /// Optimized logger middleware with minimal allocations
    pub fn logger(event: *H3Event) !MiddlewareResult {
        // Use stack buffer for formatting to avoid allocations
        var buffer: [256]u8 = undefined;
        const method = event.getMethod();
        const path = event.getPath();

        const log_msg = std.fmt.bufPrint(buffer[0..], "{s} {s}", .{ method.toString(), path }) catch "LOG_ERROR";
        std.log.info("{s}", .{log_msg});

        return .continue_chain;
    }

    /// Optimized CORS middleware
    pub fn cors(event: *H3Event) !MiddlewareResult {
        try event.setHeader("Access-Control-Allow-Origin", "*");
        try event.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        try event.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

        if (event.getMethod() == .OPTIONS) {
            event.setStatus(.no_content);
            return .terminate_early;
        }

        return .continue_chain;
    }

    /// Optimized security headers middleware
    pub fn security(event: *H3Event) !MiddlewareResult {
        try event.setHeader("X-Content-Type-Options", "nosniff");
        try event.setHeader("X-Frame-Options", "DENY");
        try event.setHeader("X-XSS-Protection", "1; mode=block");
        try event.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains");

        return .continue_chain;
    }

    /// Optimized timing middleware (start)
    pub fn timing(event: *H3Event) !MiddlewareResult {
        const start_time = std.time.nanoTimestamp();
        try event.setContext("start_time", std.mem.asBytes(&start_time));

        return .continue_chain;
    }

    /// Optimized timing middleware (end)
    pub fn timingEnd(event: *H3Event) !MiddlewareResult {
        if (event.getContext("start_time")) |start_ptr| {
            const start_time = @as(*const i128, @ptrCast(@alignCast(start_ptr))).*;
            const end_time = std.time.nanoTimestamp();
            const duration = end_time - start_time;
            const duration_ms = @as(f64, @floatFromInt(duration)) / 1_000_000.0;

            // Use stack buffer for timing header
            var buffer: [32]u8 = undefined;
            const timing_header = std.fmt.bufPrint(buffer[0..], "{d:.2}", .{duration_ms}) catch "0";
            try event.setHeader("X-Response-Time", timing_header);
        }

        return .continue_chain;
    }

    /// Rate limiting middleware (simple implementation)
    pub fn rateLimit(event: *H3Event) !MiddlewareResult {
        // Simple rate limiting based on IP (in production, use a proper rate limiter)
        const client_ip = event.getHeader("x-forwarded-for") orelse "unknown";
        _ = client_ip; // TODO: Implement actual rate limiting logic

        return .continue_chain;
    }

    /// Request ID middleware
    pub fn requestId(event: *H3Event) !MiddlewareResult {
        // Generate a simple request ID
        const timestamp = std.time.timestamp();
        var buffer: [32]u8 = undefined;
        const request_id = std.fmt.bufPrint(buffer[0..], "req_{d}", .{timestamp}) catch "req_unknown";
        try event.setHeader("X-Request-ID", request_id);

        return .continue_chain;
    }
};

/// Middleware builder for fluent API
pub const MiddlewareBuilder = struct {
    chain: FastMiddlewareChain,

    pub fn init() MiddlewareBuilder {
        return MiddlewareBuilder{
            .chain = FastMiddlewareChain.init(),
        };
    }

    pub fn logger(self: *MiddlewareBuilder) !*MiddlewareBuilder {
        _ = try self.chain.use(OptimizedMiddleware.logger);
        return self;
    }

    pub fn cors(self: *MiddlewareBuilder) !*MiddlewareBuilder {
        _ = try self.chain.use(OptimizedMiddleware.cors);
        return self;
    }

    pub fn security(self: *MiddlewareBuilder) !*MiddlewareBuilder {
        _ = try self.chain.use(OptimizedMiddleware.security);
        return self;
    }

    pub fn timing(self: *MiddlewareBuilder) !*MiddlewareBuilder {
        _ = try self.chain.use(OptimizedMiddleware.timing);
        return self;
    }

    pub fn timingEnd(self: *MiddlewareBuilder) !*MiddlewareBuilder {
        _ = try self.chain.use(OptimizedMiddleware.timingEnd);
        return self;
    }

    pub fn rateLimit(self: *MiddlewareBuilder) !*MiddlewareBuilder {
        _ = try self.chain.use(OptimizedMiddleware.rateLimit);
        return self;
    }

    pub fn requestId(self: *MiddlewareBuilder) !*MiddlewareBuilder {
        _ = try self.chain.use(OptimizedMiddleware.requestId);
        return self;
    }

    pub fn custom(self: *MiddlewareBuilder, middleware: FastMiddleware) !*MiddlewareBuilder {
        _ = try self.chain.use(middleware);
        return self;
    }

    pub fn build(self: *MiddlewareBuilder) FastMiddlewareChain {
        return self.chain;
    }
};

test "Optimized FastMiddlewareChain basic operations" {
    var chain = FastMiddlewareChain.init();
    defer chain.deinit();

    _ = try chain.use(OptimizedMiddleware.logger);
    _ = try chain.use(OptimizedMiddleware.cors);

    try std.testing.expectEqual(@as(u8, 2), chain.getCount());
    try std.testing.expect(chain.has_logger);
    try std.testing.expect(chain.has_cors);
}

test "MiddlewareBuilder fluent API" {
    var builder = MiddlewareBuilder.init();

    var b = try builder.logger();
    b = try b.cors();
    b = try b.security();
    b = try b.timing();
    b = try b.timingEnd();

    const chain = builder.build();
    try std.testing.expectEqual(@as(u8, 5), chain.getCount());
}
