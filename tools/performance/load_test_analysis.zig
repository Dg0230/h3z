//! Load test analysis to identify performance degradation patterns
//! This simulates increasing load to identify bottlenecks

const std = @import("std");
const h3 = @import("h3");

const MAX_REQUESTS = 10000;
const BATCH_SIZE = 100;
const ROUTE_COUNT = 50;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🚀 H3 Load Test Analysis", .{});
    std.log.info("========================", .{});

    // Test increasing load patterns
    try testIncreasingLoad(allocator);

    // Test memory pressure
    try testMemoryPressure(allocator);

    // Test route cache performance
    try testRouteCachePerformance(allocator);

    // Test concurrent-like behavior
    try testConcurrentBehavior(allocator);

    std.log.info("", .{});
    std.log.info("✅ Load test analysis completed", .{});
}

fn testIncreasingLoad(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("📈 Test 1: Increasing Load Pattern", .{});
    std.log.info("----------------------------------", .{});

    var app = try h3.createFastApp(allocator);
    defer app.deinit();

    const testHandler = struct {
        fn handler(event: *h3.Event) !void {
            // Simulate some work
            var sum: u64 = 0;
            for (0..100) |i| {
                sum += i;
            }
            try event.sendText("OK");
        }
    }.handler;

    // Add routes
    for (0..ROUTE_COUNT) |i| {
        var path_buffer: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{i});
        _ = app.get(path, testHandler);
    }

    // Add middleware
    _ = app.useFast(h3.fastMiddleware.logger);
    _ = app.useFast(h3.fastMiddleware.cors);

    std.log.info("Testing with {d} routes and 2 middlewares", .{ROUTE_COUNT});

    var batch_count: usize = 0;
    var total_requests: usize = 0;
    var response_times = std.ArrayList(i128).init(allocator);
    defer response_times.deinit();

    while (total_requests < MAX_REQUESTS) {
        batch_count += 1;
        const batch_start = std.time.nanoTimestamp();

        for (0..BATCH_SIZE) |i| {
            const request_start = std.time.nanoTimestamp();

            var event = h3.Event.init(allocator);
            defer event.deinit();

            event.request.method = .GET;
            const route_idx = (total_requests + i) % ROUTE_COUNT;
            var path_buffer: [64]u8 = undefined;
            const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{route_idx});
            try event.request.parseUrl(path);

            app.handle(&event) catch {};

            const request_end = std.time.nanoTimestamp();
            const request_time = request_end - request_start;
            try response_times.append(request_time);
        }

        const batch_end = std.time.nanoTimestamp();
        const batch_time = batch_end - batch_start;
        _ = batch_time; // Suppress unused variable warning

        total_requests += BATCH_SIZE;

        if (batch_count % 10 == 0) {
            // Calculate statistics for recent requests
            const recent_start = if (response_times.items.len >= 1000) response_times.items.len - 1000 else 0;
            const recent_times = response_times.items[recent_start..];

            var sum: i128 = 0;
            var min_time: i128 = std.math.maxInt(i128);
            var max_time: i128 = 0;

            for (recent_times) |time| {
                sum += time;
                if (time < min_time) min_time = time;
                if (time > max_time) max_time = time;
            }

            const avg_time = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(recent_times.len));

            std.log.info("Batch {d:3}: {d:5} requests, avg: {d:6.2}μs, min: {d:6.2}μs, max: {d:6.2}μs", .{
                batch_count,
                total_requests,
                avg_time / 1000.0,
                @as(f64, @floatFromInt(min_time)) / 1000.0,
                @as(f64, @floatFromInt(max_time)) / 1000.0,
            });
        }
    }

    // Final analysis
    var sum: i128 = 0;
    var min_time: i128 = std.math.maxInt(i128);
    var max_time: i128 = 0;

    for (response_times.items) |time| {
        sum += time;
        if (time < min_time) min_time = time;
        if (time > max_time) max_time = time;
    }

    const avg_time = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(response_times.items.len));

    std.log.info("", .{});
    std.log.info("📊 Final Statistics:", .{});
    std.log.info("Total requests: {d}", .{total_requests});
    std.log.info("Average response time: {d:.2}μs", .{avg_time / 1000.0});
    std.log.info("Min response time: {d:.2}μs", .{@as(f64, @floatFromInt(min_time)) / 1000.0});
    std.log.info("Max response time: {d:.2}μs", .{@as(f64, @floatFromInt(max_time)) / 1000.0});

    // Check for performance degradation
    const first_1000 = response_times.items[0..@min(1000, response_times.items.len)];
    const last_1000_start = if (response_times.items.len >= 1000) response_times.items.len - 1000 else 0;
    const last_1000 = response_times.items[last_1000_start..];

    var first_sum: i128 = 0;
    var last_sum: i128 = 0;

    for (first_1000) |time| first_sum += time;
    for (last_1000) |time| last_sum += time;

    const first_avg = @as(f64, @floatFromInt(first_sum)) / @as(f64, @floatFromInt(first_1000.len));
    const last_avg = @as(f64, @floatFromInt(last_sum)) / @as(f64, @floatFromInt(last_1000.len));

    const degradation = (last_avg - first_avg) / first_avg * 100;

    std.log.info("First 1000 avg: {d:.2}μs", .{first_avg / 1000.0});
    std.log.info("Last 1000 avg: {d:.2}μs", .{last_avg / 1000.0});

    if (degradation > 10) {
        std.log.warn("⚠️  Performance degradation detected: {d:.1}%", .{degradation});
    } else {
        std.log.info("✅ Performance stable: {d:.1}% change", .{degradation});
    }
}

fn testMemoryPressure(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("🧠 Test 2: Memory Pressure Analysis", .{});
    std.log.info("-----------------------------------", .{});

    // Test with different event pool sizes
    const pool_sizes = [_]usize{ 10, 50, 100, 200 };

    for (pool_sizes) |pool_size| {
        var pool = h3.EventPool.init(allocator, pool_size);
        defer pool.deinit();

        try pool.warmUp(pool_size / 2);

        const test_start = std.time.nanoTimestamp();

        // Simulate high memory pressure
        for (0..1000) |_| {
            const event = try pool.acquire();
            defer pool.release(event);

            // Simulate memory-intensive operations
            try event.setContext("key1", "value1");
            try event.setContext("key2", "value2");
            try event.setContext("key3", "value3");
            try event.setParam("param1", "value1");
            try event.setParam("param2", "value2");
        }

        const test_end = std.time.nanoTimestamp();
        const test_time = test_end - test_start;
        const avg_time = @as(f64, @floatFromInt(test_time)) / 1000.0;

        const stats = pool.getStats();

        std.log.info("Pool size {d:3}: {d:6.2}μs avg, reuse: {d:5.1}%, hits: {d:4}, misses: {d:3}", .{
            pool_size,
            avg_time / 1000.0,
            stats.reuse_ratio * 100,
            stats.reuse_count,
            stats.created_count,
        });
    }
}

fn testRouteCachePerformance(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("🗺️  Test 3: Route Cache Performance", .{});
    std.log.info("----------------------------------", .{});

    const RouteCache = h3.optimized.RouteCache;
    var cache = RouteCache.init(allocator, 100);
    defer cache.deinit();

    const testHandler = struct {
        fn handler(event: *h3.Event) !void {
            try event.sendText("OK");
        }
    }.handler;

    // Test cache performance with different access patterns
    const patterns = [_]struct { name: []const u8, description: []const u8 }{
        .{ .name = "sequential", .description = "Sequential access pattern" },
        .{ .name = "random", .description = "Random access pattern" },
        .{ .name = "hotspot", .description = "80/20 hotspot pattern" },
    };

    for (patterns) |pattern| {
        std.log.info("", .{});
        std.log.info("Testing {s}: {s}", .{ pattern.name, pattern.description });

        // Clear cache for each test
        cache.clear();

        // Pre-populate cache
        for (0..50) |i| {
            var path_buffer: [64]u8 = undefined;
            const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{i});
            var empty_params = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
            defer empty_params.deinit();
            try cache.put(.GET, path, testHandler, empty_params);
        }

        const test_start = std.time.nanoTimestamp();
        var hits: usize = 0;
        var misses: usize = 0;

        for (0..1000) |i| {
            var route_idx: usize = undefined;

            if (std.mem.eql(u8, pattern.name, "sequential")) {
                route_idx = i % 50;
            } else if (std.mem.eql(u8, pattern.name, "random")) {
                route_idx = @as(usize, @intCast(std.crypto.random.int(u32))) % 50;
            } else { // hotspot
                if (i % 10 < 8) {
                    route_idx = i % 10; // 80% access to first 10 routes
                } else {
                    route_idx = 10 + (i % 40); // 20% access to remaining routes
                }
            }

            var path_buffer: [64]u8 = undefined;
            const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{route_idx});

            if (cache.get(.GET, path)) |_| {
                hits += 1;
            } else {
                misses += 1;
            }
        }

        const test_end = std.time.nanoTimestamp();
        const test_time = test_end - test_start;
        const avg_time = @as(f64, @floatFromInt(test_time)) / 1000.0;

        const cache_stats = cache.getStats();

        std.log.info("  Time: {d:.2}μs avg, Hit ratio: {d:.1}%, Hits: {d}, Misses: {d}", .{
            avg_time / 1000.0,
            cache_stats.hit_ratio * 100,
            hits,
            misses,
        });
    }
}

fn testConcurrentBehavior(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("🔄 Test 4: Concurrent-like Behavior", .{});
    std.log.info("------------------------------------", .{});

    // Simulate concurrent behavior by interleaving operations
    var app = try h3.createFastApp(allocator);
    defer app.deinit();

    const testHandler = struct {
        fn handler(event: *h3.Event) !void {
            // Simulate variable processing time
            var sum: u64 = 0;
            const work_amount = @as(usize, @intCast(std.crypto.random.int(u32))) % 200 + 50;
            for (0..work_amount) |i| {
                sum += i;
            }
            try event.sendText("OK");
        }
    }.handler;

    // Add routes
    for (0..20) |i| {
        var path_buffer: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{i});
        _ = app.get(path, testHandler);
    }

    // Add middleware
    _ = app.useFast(h3.fastMiddleware.logger);
    _ = app.useFast(h3.fastMiddleware.cors);

    // Simulate multiple "concurrent" requests with overlapping lifecycles
    var active_events = std.ArrayList(*h3.Event).init(allocator);
    defer {
        for (active_events.items) |event| {
            event.deinit();
            allocator.destroy(event);
        }
        active_events.deinit();
    }

    const max_concurrent = 10;
    var total_processed: usize = 0;
    var response_times = std.ArrayList(i128).init(allocator);
    defer response_times.deinit();

    const test_start = std.time.nanoTimestamp();

    while (total_processed < 1000) {
        // Start new requests if we have capacity
        while (active_events.items.len < max_concurrent and total_processed + active_events.items.len < 1000) {
            const event = try allocator.create(h3.Event);
            event.* = h3.Event.init(allocator);

            event.request.method = .GET;
            const route_idx = @as(usize, @intCast(std.crypto.random.int(u32))) % 20;
            var path_buffer: [64]u8 = undefined;
            const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{route_idx});
            try event.request.parseUrl(path);

            try event.setContext("start_time", "timestamp");
            try active_events.append(event);
        }

        // Process all active requests
        while (active_events.items.len > 0) {
            const event = active_events.items[0];
            const request_start = std.time.nanoTimestamp();

            app.handle(event) catch {};

            const request_end = std.time.nanoTimestamp();
            const request_time = request_end - request_start;
            try response_times.append(request_time);

            // Remove completed request
            event.deinit();
            allocator.destroy(event);
            _ = active_events.swapRemove(0);
            total_processed += 1;
        }
    }

    const test_end = std.time.nanoTimestamp();
    const total_time = test_end - test_start;

    // Calculate statistics
    var sum: i128 = 0;
    var min_time: i128 = std.math.maxInt(i128);
    var max_time: i128 = 0;

    for (response_times.items) |time| {
        sum += time;
        if (time < min_time) min_time = time;
        if (time > max_time) max_time = time;
    }

    const avg_time = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(response_times.items.len));
    const throughput = @as(f64, @floatFromInt(total_processed)) / (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);

    std.log.info("Processed {d} requests with max {d} concurrent", .{ total_processed, max_concurrent });
    std.log.info("Total time: {d:.2}ms", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
    std.log.info("Average response time: {d:.2}μs", .{avg_time / 1000.0});
    std.log.info("Min response time: {d:.2}μs", .{@as(f64, @floatFromInt(min_time)) / 1000.0});
    std.log.info("Max response time: {d:.2}μs", .{@as(f64, @floatFromInt(max_time)) / 1000.0});
    std.log.info("Throughput: {d:.1} requests/second", .{throughput});
}
