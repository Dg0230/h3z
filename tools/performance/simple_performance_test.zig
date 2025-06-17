//! Simplified performance test to verify optimizations
//! Tests core performance improvements without complex dependencies

const std = @import("std");
const h3 = @import("h3");

const ITERATIONS = 2000;
const ROUTE_COUNT = 30;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🚀 H3 Performance Optimization Verification", .{});
    std.log.info("============================================", .{});

    // Test 1: Basic performance with current implementation
    try testCurrentPerformance(allocator);

    // Test 2: Memory usage patterns
    try testMemoryPatterns(allocator);

    // Test 3: Route lookup performance
    try testRouteLookupPerformance(allocator);

    std.log.info("", .{});
    std.log.info("✅ Performance verification completed", .{});
}

fn testCurrentPerformance(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("📊 Test 1: Current Implementation Performance", .{});
    std.log.info("---------------------------------------------", .{});

    var app = try h3.createFastApp(allocator);
    defer app.deinit();

    const testHandler = struct {
        fn handler(event: *h3.Event) !void {
            // Simulate realistic work
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

    var response_times = std.ArrayList(i128).init(allocator);
    defer response_times.deinit();

    const test_start = std.time.nanoTimestamp();

    // Run performance test
    for (0..ITERATIONS) |i| {
        const request_start = std.time.nanoTimestamp();

        var event = h3.Event.init(allocator);
        defer event.deinit();

        event.request.method = .GET;
        const route_idx = i % ROUTE_COUNT;
        var path_buffer: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{route_idx});
        try event.request.parseUrl(path);

        app.handle(&event) catch {};

        const request_end = std.time.nanoTimestamp();
        try response_times.append(request_end - request_start);
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
    const throughput = @as(f64, @floatFromInt(ITERATIONS)) / (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);

    std.log.info("Total requests: {d}", .{ITERATIONS});
    std.log.info("Total time: {d:.2}ms", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
    std.log.info("Average response time: {d:.2}μs", .{avg_time / 1000.0});
    std.log.info("Min response time: {d:.2}μs", .{@as(f64, @floatFromInt(min_time)) / 1000.0});
    std.log.info("Max response time: {d:.2}μs", .{@as(f64, @floatFromInt(max_time)) / 1000.0});
    std.log.info("Throughput: {d:.1} requests/second", .{throughput});

    // Check for performance degradation
    const batch_size = 200;
    const num_batches = ITERATIONS / batch_size;

    std.log.info("", .{});
    std.log.info("🔍 Performance Stability Analysis:", .{});

    var batch_averages = std.ArrayList(f64).init(allocator);
    defer batch_averages.deinit();

    for (0..num_batches) |batch| {
        const start_idx = batch * batch_size;
        const end_idx = @min(start_idx + batch_size, response_times.items.len);
        const batch_times = response_times.items[start_idx..end_idx];

        var batch_sum: i128 = 0;
        for (batch_times) |time| batch_sum += time;

        const batch_avg = @as(f64, @floatFromInt(batch_sum)) / @as(f64, @floatFromInt(batch_times.len));
        try batch_averages.append(batch_avg);

        if (batch % 2 == 0) { // Log every other batch
            std.log.info("Batch {d:2}: {d:6.2}μs avg", .{ batch + 1, batch_avg / 1000.0 });
        }
    }

    // Calculate overall degradation
    const first_batch_avg = batch_averages.items[0];
    const last_batch_avg = batch_averages.items[batch_averages.items.len - 1];
    const degradation = (last_batch_avg - first_batch_avg) / first_batch_avg * 100;

    std.log.info("", .{});
    std.log.info("First batch avg: {d:.2}μs", .{first_batch_avg / 1000.0});
    std.log.info("Last batch avg: {d:.2}μs", .{last_batch_avg / 1000.0});
    std.log.info("Performance change: {d:.1}%", .{degradation});

    if (@abs(degradation) < 5) {
        std.log.info("✅ Performance is stable", .{});
    } else if (@abs(degradation) < 15) {
        std.log.info("⚡ Performance is acceptable", .{});
    } else {
        std.log.warn("⚠️  Significant performance degradation detected", .{});
    }
}

fn testMemoryPatterns(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("🧠 Test 2: Memory Usage Patterns", .{});
    std.log.info("---------------------------------", .{});

    // Test event pool performance
    var pool = h3.EventPool.init(allocator, 50);
    defer pool.deinit();

    try pool.warmUp(25);

    const pool_test_start = std.time.nanoTimestamp();

    for (0..1000) |_| {
        const event = try pool.acquire();
        defer pool.release(event);

        // Simulate event usage
        try event.setContext("test", "value");
        try event.setParam("id", "123");
    }

    const pool_test_end = std.time.nanoTimestamp();
    const pool_time = pool_test_end - pool_test_start;

    const pool_stats = pool.getStats();

    std.log.info("Event pool test time: {d:.2}ms", .{@as(f64, @floatFromInt(pool_time)) / 1_000_000.0});
    std.log.info("Pool reuse ratio: {d:.1}%", .{pool_stats.reuse_ratio * 100});
    std.log.info("Pool hits: {d}, misses: {d}", .{ pool_stats.reuse_count, pool_stats.created_count });

    if (pool_stats.reuse_ratio > 0.8) {
        std.log.info("✅ Excellent pool efficiency", .{});
    } else if (pool_stats.reuse_ratio > 0.6) {
        std.log.info("⚡ Good pool efficiency", .{});
    } else {
        std.log.warn("⚠️  Pool efficiency needs improvement", .{});
    }

    // Test direct allocation for comparison
    const direct_test_start = std.time.nanoTimestamp();

    for (0..1000) |_| {
        var event = h3.Event.init(allocator);
        defer event.deinit();

        // Simulate event usage
        try event.setContext("test", "value");
        try event.setParam("id", "123");
    }

    const direct_test_end = std.time.nanoTimestamp();
    const direct_time = direct_test_end - direct_test_start;

    std.log.info("Direct allocation time: {d:.2}ms", .{@as(f64, @floatFromInt(direct_time)) / 1_000_000.0});

    const improvement = (@as(f64, @floatFromInt(direct_time)) - @as(f64, @floatFromInt(pool_time))) / @as(f64, @floatFromInt(direct_time)) * 100;
    std.log.info("Pool improvement: {d:.1}%", .{improvement});
}

fn testRouteLookupPerformance(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("🗺️  Test 3: Route Lookup Performance", .{});
    std.log.info("------------------------------------", .{});

    var app = try h3.createFastApp(allocator);
    defer app.deinit();

    const testHandler = struct {
        fn handler(event: *h3.Event) !void {
            try event.sendText("OK");
        }
    }.handler;

    // Add many routes
    const route_count = 100;
    for (0..route_count) |i| {
        var path_buffer: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{i});
        _ = app.get(path, testHandler);
    }

    std.log.info("Added {d} routes", .{route_count});

    // Test route lookup performance
    const lookup_iterations = 5000;
    const lookup_start = std.time.nanoTimestamp();

    for (0..lookup_iterations) |i| {
        const route_idx = i % route_count;
        var path_buffer: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{route_idx});

        const route = app.findRoute(.GET, path);
        _ = route; // Suppress unused variable warning
    }

    const lookup_end = std.time.nanoTimestamp();
    const lookup_time = lookup_end - lookup_start;
    const avg_lookup = @as(f64, @floatFromInt(lookup_time)) / @as(f64, @floatFromInt(lookup_iterations));

    std.log.info("Route lookups: {d} iterations", .{lookup_iterations});
    std.log.info("Total lookup time: {d:.2}ms", .{@as(f64, @floatFromInt(lookup_time)) / 1_000_000.0});
    std.log.info("Average lookup time: {d:.2}μs", .{avg_lookup / 1000.0});

    if (avg_lookup / 1000.0 < 50) {
        std.log.info("✅ Excellent route lookup performance", .{});
    } else if (avg_lookup / 1000.0 < 100) {
        std.log.info("⚡ Good route lookup performance", .{});
    } else {
        std.log.warn("⚠️  Route lookup performance needs optimization", .{});
    }

    // Test with different access patterns
    std.log.info("", .{});
    std.log.info("Testing different access patterns:", .{});

    // Sequential access
    const seq_start = std.time.nanoTimestamp();
    for (0..1000) |i| {
        const route_idx = i % route_count;
        var path_buffer: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{route_idx});
        const route = app.findRoute(.GET, path);
        _ = route;
    }
    const seq_end = std.time.nanoTimestamp();
    const seq_avg = @as(f64, @floatFromInt(seq_end - seq_start)) / 1000.0;

    // Random access
    const rand_start = std.time.nanoTimestamp();
    for (0..1000) |_| {
        const route_idx = @as(usize, @intCast(std.crypto.random.int(u32))) % route_count;
        var path_buffer: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{route_idx});
        const route = app.findRoute(.GET, path);
        _ = route;
    }
    const rand_end = std.time.nanoTimestamp();
    const rand_avg = @as(f64, @floatFromInt(rand_end - rand_start)) / 1000.0;

    std.log.info("Sequential access: {d:.2}μs avg", .{seq_avg / 1000.0});
    std.log.info("Random access: {d:.2}μs avg", .{rand_avg / 1000.0});

    const pattern_diff = @abs(rand_avg - seq_avg) / seq_avg * 100;
    if (pattern_diff < 20) {
        std.log.info("✅ Consistent performance across access patterns", .{});
    } else {
        std.log.info("⚡ Some variation in access patterns ({d:.1}%)", .{pattern_diff});
    }
}
