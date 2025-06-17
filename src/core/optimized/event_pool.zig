//! Fixed event pool for high-performance H3Event object reuse
//! Reduces memory allocation overhead by reusing event objects with proper cleanup

const std = @import("std");
const H3Event = @import("../event.zig").H3Event;

/// Fixed pool for reusing H3Event objects with improved memory management
pub const EventPool = struct {
    events: std.ArrayList(*H3Event),
    allocator: std.mem.Allocator,
    max_size: usize,
    created_count: usize,
    reuse_count: usize,

    // Arena allocator for temporary allocations during reset
    arena: std.heap.ArenaAllocator,

    /// Initialize a new event pool with arena allocator
    pub fn init(allocator: std.mem.Allocator, max_size: usize) EventPool {
        return EventPool{
            .events = std.ArrayList(*H3Event).init(allocator),
            .allocator = allocator,
            .max_size = max_size,
            .created_count = 0,
            .reuse_count = 0,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    /// Deinitialize the pool and free all events
    pub fn deinit(self: *EventPool) void {
        for (self.events.items) |event| {
            event.deinit();
            self.allocator.destroy(event);
        }
        self.events.deinit();
        self.arena.deinit();
    }

    /// Acquire an event from the pool or create a new one
    pub fn acquire(self: *EventPool) !*H3Event {
        if (self.events.items.len > 0) {
            const event = self.events.orderedRemove(self.events.items.len - 1);

            // Efficiently reset event object with arena allocator
            try self.resetEvent(event);

            self.reuse_count += 1;
            return event;
        }

        // Create a new event
        const event = try self.allocator.create(H3Event);
        event.* = H3Event.init(self.allocator);
        self.created_count += 1;
        return event;
    }

    /// Release an event back to the pool
    pub fn release(self: *EventPool, event: *H3Event) void {
        if (self.events.items.len < self.max_size) {
            // Put the object back into the pool
            // Reset will be performed on next acquire for better performance
            self.events.append(event) catch {
                // Only destroy the object if adding to pool fails
                event.deinit();
                self.allocator.destroy(event);
            };
        } else {
            // Pool is full, destroy the object
            event.deinit();
            self.allocator.destroy(event);
        }
    }

    /// Efficiently reset an event object with minimal allocations
    fn resetEvent(self: *EventPool, event: *H3Event) !void {
        // Reset arena allocator for temporary operations
        _ = self.arena.reset(.retain_capacity);
        _ = self.arena.allocator(); // Suppress unused variable warning

        // Properly free all allocated memory in maps before clearing
        var context_iter = event.context.iterator();
        while (context_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        event.context.clearRetainingCapacity();

        var params_iter = event.params.iterator();
        while (params_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        event.params.clearRetainingCapacity();

        var query_iter = event.query.iterator();
        while (query_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        event.query.clearRetainingCapacity();

        // Reset request object efficiently
        event.request.method = .GET;
        event.request.url = "";
        event.request.version = "HTTP/1.1";

        // Free and reset path only if it's not a common path
        if (event.request.path.len > 0) {
            // Only free if it's not a static string
            if (!isStaticPath(event.request.path)) {
                self.allocator.free(event.request.path);
            }
        }
        event.request.path = "";

        // Free request body if it exists
        if (event.request.body) |body| {
            self.allocator.free(body);
            event.request.body = null;
        }

        // Free query string if it exists
        if (event.request.query) |query| {
            self.allocator.free(query);
            event.request.query = null;
        }

        // Clear request headers efficiently
        var header_iter = event.request.headers.iterator();
        while (header_iter.next()) |entry| {
            // Free header values that were allocated
            if (!isStaticString(entry.key_ptr.*)) {
                self.allocator.free(entry.key_ptr.*);
            }
            if (!isStaticString(entry.value_ptr.*)) {
                self.allocator.free(entry.value_ptr.*);
            }
        }
        event.request.headers.clearRetainingCapacity();

        // Reset response object
        event.response.status = .ok;
        event.response.version = "HTTP/1.1";

        if (event.response.body_owned and event.response.body != null) {
            self.allocator.free(event.response.body.?);
        }
        event.response.body = null;
        event.response.body_owned = false;
        event.response.sent = false;
        event.response.finished = false;

        // Clear response headers efficiently
        var resp_header_iter = event.response.headers.iterator();
        while (resp_header_iter.next()) |entry| {
            if (!isStaticString(entry.key_ptr.*)) {
                self.allocator.free(entry.key_ptr.*);
            }
            if (!isStaticString(entry.value_ptr.*)) {
                self.allocator.free(entry.value_ptr.*);
            }
        }
        event.response.headers.clearRetainingCapacity();
    }

    /// Check if a path is a common static path that shouldn't be freed
    fn isStaticPath(path: []const u8) bool {
        const static_paths = [_][]const u8{
            "/",
            "/health",
            "/api",
            "/static",
            "",
        };

        for (static_paths) |static_path| {
            if (std.mem.eql(u8, path, static_path)) {
                return true;
            }
        }
        return false;
    }

    /// Check if a string is likely a static string that shouldn't be freed
    fn isStaticString(str: []const u8) bool {
        // Simple heuristic: very short strings or common headers are likely static
        if (str.len == 0 or str.len > 1000) return true;

        const common_headers = [_][]const u8{
            "content-type",
            "content-length",
            "connection",
            "host",
            "user-agent",
            "accept",
            "authorization",
        };

        for (common_headers) |header| {
            if (std.ascii.eqlIgnoreCase(str, header)) {
                return true;
            }
        }
        return false;
    }

    /// Get pool statistics
    pub fn getStats(self: *const EventPool) PoolStats {
        return PoolStats{
            .pool_size = self.events.items.len,
            .max_size = self.max_size,
            .created_count = self.created_count,
            .reuse_count = self.reuse_count,
            .reuse_ratio = if (self.created_count > 0)
                @as(f64, @floatFromInt(self.reuse_count)) / @as(f64, @floatFromInt(self.created_count + self.reuse_count))
            else
                0.0,
        };
    }

    /// Reset pool statistics
    pub fn resetStats(self: *EventPool) void {
        self.created_count = 0;
        self.reuse_count = 0;
    }

    /// Warm up the pool by pre-allocating events
    pub fn warmUp(self: *EventPool, count: usize) !void {
        const actual_count = @min(count, self.max_size);

        for (0..actual_count) |_| {
            const event = try self.allocator.create(H3Event);
            event.* = H3Event.init(self.allocator);
            try self.events.append(event);
            self.created_count += 1;
        }
    }

    /// Shrink pool to target size with proper cleanup
    pub fn shrink(self: *EventPool, target_size: usize) void {
        while (self.events.items.len > target_size) {
            const event = self.events.orderedRemove(self.events.items.len - 1);
            event.deinit();
            self.allocator.destroy(event);
        }
    }

    /// Perform maintenance on the pool (cleanup, optimization)
    pub fn maintenance(self: *EventPool) void {
        // Reset arena allocator to free temporary memory
        _ = self.arena.reset(.free_all);

        // Optionally shrink the pool if it's much larger than needed
        const optimal_size = @max(self.max_size / 4, 10);
        if (self.events.items.len > optimal_size * 2) {
            self.shrink(optimal_size);
        }
    }
};

/// Pool statistics for monitoring
pub const PoolStats = struct {
    pool_size: usize,
    max_size: usize,
    created_count: usize,
    reuse_count: usize,
    reuse_ratio: f64,
};

/// Global event pool instance with thread safety
var global_pool: ?EventPool = null;
var global_pool_mutex: std.Thread.Mutex = .{};

/// Initialize global event pool
pub fn initGlobalPool(allocator: std.mem.Allocator, max_size: usize) void {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();

    if (global_pool == null) {
        global_pool = EventPool.init(allocator, max_size);
    }
}

/// Deinitialize global event pool
pub fn deinitGlobalPool() void {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();

    if (global_pool) |*pool| {
        pool.deinit();
        global_pool = null;
    }
}

/// Acquire from global pool
pub fn acquireGlobal() !*H3Event {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();

    if (global_pool) |*pool| {
        return pool.acquire();
    }
    return error.GlobalPoolNotInitialized;
}

/// Release to global pool
pub fn releaseGlobal(event: *H3Event) void {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();

    if (global_pool) |*pool| {
        pool.release(event);
    }
}

/// Perform maintenance on global pool
pub fn maintenanceGlobal() void {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();

    if (global_pool) |*pool| {
        pool.maintenance();
    }
}

test "Fixed EventPool basic operations" {
    var pool = EventPool.init(std.testing.allocator, 5);
    defer pool.deinit();

    // Acquire events
    const event1 = try pool.acquire();
    const event2 = try pool.acquire();

    // Release events
    pool.release(event1);
    pool.release(event2);

    // Acquire again should reuse
    const event3 = try pool.acquire();
    pool.release(event3);

    const stats = pool.getStats();
    try std.testing.expect(stats.reuse_count > 0);
}

test "Fixed EventPool warm up and maintenance" {
    var pool = EventPool.init(std.testing.allocator, 10);
    defer pool.deinit();

    try pool.warmUp(5);
    try std.testing.expectEqual(@as(usize, 5), pool.events.items.len);

    const event = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 4), pool.events.items.len);

    pool.release(event);
    try std.testing.expectEqual(@as(usize, 5), pool.events.items.len);

    // Test maintenance
    pool.maintenance();
    try std.testing.expect(pool.events.items.len <= 10);
}
