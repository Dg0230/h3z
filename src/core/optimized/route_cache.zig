//! Fixed LRU cache for route lookups with proper memory management
//! Provides O(1) cache lookups for frequently accessed routes

const std = @import("std");
const HttpMethod = @import("../../http/method.zig").HttpMethod;

/// Cache key combining method and path with owned memory
const CacheKey = struct {
    method: HttpMethod,
    path: []u8, // Owned memory
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, method: HttpMethod, path: []const u8) !CacheKey {
        const owned_path = try allocator.dupe(u8, path);
        return CacheKey{
            .method = method,
            .path = owned_path,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CacheKey) void {
        self.allocator.free(self.path);
    }

    pub fn hash(self: CacheKey) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(@tagName(self.method));
        hasher.update(self.path);
        return hasher.final();
    }

    pub fn eql(a: CacheKey, b: CacheKey) bool {
        return a.method == b.method and std.mem.eql(u8, a.path, b.path);
    }
};

/// Cached route entry with proper cleanup
const CacheEntry = struct {
    handler: ?*const fn (*@import("../event.zig").H3Event) anyerror!void,
    params: std.HashMap([]u8, []u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    access_time: i64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CacheEntry {
        return CacheEntry{
            .handler = null,
            .params = std.HashMap([]u8, []u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .access_time = std.time.timestamp(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CacheEntry) void {
        // Free all parameter keys and values
        var iter = self.params.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.params.deinit();
    }

    pub fn updateAccess(self: *CacheEntry) void {
        self.access_time = std.time.timestamp();
    }

    pub fn setParam(self: *CacheEntry, key: []const u8, value: []const u8) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.params.put(owned_key, owned_value);
    }
};

/// LRU node for doubly-linked list with owned key
const LRUNode = struct {
    key: CacheKey,
    prev: ?*LRUNode = null,
    next: ?*LRUNode = null,

    pub fn init(key: CacheKey) LRUNode {
        return LRUNode{ .key = key };
    }

    pub fn deinit(self: *LRUNode) void {
        self.key.deinit();
    }
};

/// Fixed high-performance LRU cache for route lookups
pub const RouteCache = struct {
    // Hash map for O(1) lookups
    cache: std.HashMap(CacheKey, CacheEntry, CacheKeyContext, std.hash_map.default_max_load_percentage),

    // LRU tracking with doubly-linked list
    lru_map: std.HashMap(CacheKey, *LRUNode, CacheKeyContext, std.hash_map.default_max_load_percentage),
    head: ?*LRUNode = null,
    tail: ?*LRUNode = null,

    // Configuration
    max_size: usize,
    allocator: std.mem.Allocator,

    // Statistics
    hits: usize = 0,
    misses: usize = 0,
    evictions: usize = 0,

    const CacheKeyContext = struct {
        pub fn hash(self: @This(), key: CacheKey) u64 {
            _ = self;
            return key.hash();
        }

        pub fn eql(self: @This(), a: CacheKey, b: CacheKey) bool {
            _ = self;
            return a.eql(b);
        }
    };

    pub fn init(allocator: std.mem.Allocator, max_size: usize) RouteCache {
        return RouteCache{
            .cache = std.HashMap(CacheKey, CacheEntry, CacheKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .lru_map = std.HashMap(CacheKey, *LRUNode, CacheKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .max_size = max_size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RouteCache) void {
        // Clean up cache entries
        var cache_iter = self.cache.iterator();
        while (cache_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.cache.clearAndFree();

        // Clean up LRU linked list
        var current = self.head;
        while (current) |node| {
            const next = node.next;
            node.deinit();
            self.allocator.destroy(node);
            current = next;
        }

        self.lru_map.clearAndFree();
    }

    /// Get cached route result
    pub fn get(self: *RouteCache, method: HttpMethod, path: []const u8) ?*CacheEntry {
        // Create temporary key for lookup (no allocation)
        const temp_key = CacheKey{
            .method = method,
            .path = @constCast(path), // Safe because we only use it for lookup
            .allocator = undefined, // Not used for lookup
        };

        if (self.cache.getPtr(temp_key)) |entry| {
            self.hits += 1;
            entry.updateAccess();
            self.moveToHead(temp_key);
            return entry;
        }

        self.misses += 1;
        return null;
    }

    /// Put route result in cache with proper memory management
    pub fn put(self: *RouteCache, method: HttpMethod, path: []const u8, handler: ?*const fn (*@import("../event.zig").H3Event) anyerror!void, params: anytype) !void {
        // Create owned key
        var key = try CacheKey.init(self.allocator, method, path);
        errdefer key.deinit();

        // Check if already exists
        const temp_key = CacheKey{
            .method = method,
            .path = @constCast(path),
            .allocator = undefined,
        };

        if (self.cache.contains(temp_key)) {
            if (self.cache.getPtr(temp_key)) |entry| {
                entry.handler = handler;
                entry.updateAccess();
                self.moveToHead(temp_key);
            }
            key.deinit(); // Clean up unused key
            return;
        }

        // Evict if at capacity
        if (self.cache.count() >= self.max_size) {
            try self.evictLRU();
        }

        // Create new entry
        var entry = CacheEntry.init(self.allocator);
        entry.handler = handler;

        // Copy parameters with proper memory management
        var param_iter = params.iterator();
        while (param_iter.next()) |param| {
            try entry.setParam(param.key_ptr.*, param.value_ptr.*);
        }

        // Add to cache
        try self.cache.put(key, entry);

        // Add to LRU tracking
        const node = try self.allocator.create(LRUNode);
        node.* = LRUNode.init(key);
        try self.lru_map.put(key, node);
        self.addToHead(node);
    }

    /// Move node to head of LRU list (most recently used)
    fn moveToHead(self: *RouteCache, temp_key: CacheKey) void {
        if (self.lru_map.get(temp_key)) |node| {
            self.removeNode(node);
            self.addToHead(node);
        }
    }

    /// Add node to head of LRU list
    fn addToHead(self: *RouteCache, node: *LRUNode) void {
        node.prev = null;
        node.next = self.head;

        if (self.head) |head| {
            head.prev = node;
        }
        self.head = node;

        if (self.tail == null) {
            self.tail = node;
        }
    }

    /// Remove node from LRU list
    fn removeNode(self: *RouteCache, node: *LRUNode) void {
        if (node.prev) |prev| {
            prev.next = node.next;
        } else {
            self.head = node.next;
        }

        if (node.next) |next| {
            next.prev = node.prev;
        } else {
            self.tail = node.prev;
        }
    }

    /// Evict least recently used entry
    fn evictLRU(self: *RouteCache) !void {
        if (self.tail) |tail| {
            const key = tail.key;

            // Remove from cache
            if (self.cache.getPtr(key)) |entry| {
                entry.deinit();
            }
            _ = self.cache.remove(key);

            // Remove from LRU tracking
            self.removeNode(tail);
            _ = self.lru_map.remove(key);
            tail.deinit();
            self.allocator.destroy(tail);

            self.evictions += 1;
        }
    }

    /// Get cache statistics
    pub fn getStats(self: *const RouteCache) struct {
        hits: usize,
        misses: usize,
        evictions: usize,
        hit_ratio: f64,
        size: usize,
        max_size: usize,
    } {
        const total_requests = self.hits + self.misses;
        const hit_ratio = if (total_requests > 0)
            @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total_requests))
        else
            0.0;

        return .{
            .hits = self.hits,
            .misses = self.misses,
            .evictions = self.evictions,
            .hit_ratio = hit_ratio,
            .size = self.cache.count(),
            .max_size = self.max_size,
        };
    }

    /// Clear all cached entries
    pub fn clear(self: *RouteCache) void {
        // Clean up cache entries
        var cache_iter = self.cache.iterator();
        while (cache_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.cache.clearRetainingCapacity();

        // Clean up LRU nodes
        var current = self.head;
        while (current) |node| {
            const next = node.next;
            node.deinit();
            self.allocator.destroy(node);
            current = next;
        }
        self.lru_map.clearRetainingCapacity();

        self.head = null;
        self.tail = null;
        self.hits = 0;
        self.misses = 0;
        self.evictions = 0;
    }
};

test "Fixed RouteCache basic operations" {
    var cache = RouteCache.init(std.testing.allocator, 3);
    defer cache.deinit();

    const testHandler = struct {
        fn handler(event: *@import("../event.zig").H3Event) !void {
            _ = event;
        }
    }.handler;

    // Test cache miss
    const result1 = cache.get(.GET, "/test");
    try std.testing.expect(result1 == null);

    // Test cache put and hit
    var empty_params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(std.testing.allocator);
    defer empty_params.deinit();

    try cache.put(.GET, "/test", testHandler, empty_params);

    const result2 = cache.get(.GET, "/test");
    try std.testing.expect(result2 != null);
    try std.testing.expect(result2.?.handler == testHandler);

    // Check statistics
    const stats = cache.getStats();
    try std.testing.expect(stats.hits == 1);
    try std.testing.expect(stats.misses == 1);
    try std.testing.expect(stats.hit_ratio == 0.5);
}
