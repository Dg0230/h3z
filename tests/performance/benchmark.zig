//! Performance benchmarks for H3 framework optimizations
//! Compares old vs new implementations

const std = @import("std");
const testing = std.testing;
const h3 = @import("h3");

const BENCHMARK_ITERATIONS = 1000;
const ROUTE_COUNT = 50;

// Benchmark route lookup performance
test "Benchmark: Route lookup performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create app with many routes
    var app = try h3.createFastApp(allocator);
    defer app.deinit();

    const testHandler = struct {
        fn handler(event: *h3.Event) !void {
            try event.sendText("OK");
        }
    }.handler;

    // Add many routes
    for (0..ROUTE_COUNT) |i| {
        var path_buffer: [64]u8 = undefined;
        const path = std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{i}) catch continue;
        _ = app.get(path, testHandler);
    }

    // Simple benchmark
    const start_time = std.time.nanoTimestamp();

    for (0..BENCHMARK_ITERATIONS) |_| {
        const route = app.findRoute(.GET, "/api/route25");
        _ = route;
    }

    const end_time = std.time.nanoTimestamp();
    const total_time = @as(u64, @intCast(end_time - start_time));
    const avg_time = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(BENCHMARK_ITERATIONS));

    std.log.info("Route lookup benchmark:", .{});
    std.log.info("  Iterations: {d}", .{BENCHMARK_ITERATIONS});
    std.log.info("  Avg time: {d:.2}μs", .{avg_time / 1000.0});

    // Should be reasonably fast
    try testing.expect(avg_time < 50_000); // Less than 50μs per lookup
}

// Benchmark middleware execution
test "Benchmark: Fast middleware vs legacy middleware" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const testHandler = struct {
        fn handler(event: *h3.Event) !void {
            try event.sendText("OK");
        }
    }.handler;

    // Test fast middleware
    {
        var app = try h3.createFastApp(allocator);
        defer app.deinit();

        _ = app.useFast(h3.fastMiddleware.logger);
        _ = app.useFast(h3.fastMiddleware.cors);
        _ = app.get("/test", testHandler);

        const start_time = std.time.nanoTimestamp();

        for (0..BENCHMARK_ITERATIONS / 10) |_| {
            var event = h3.Event.init(allocator);
            defer event.deinit();

            event.request.method = .GET;
            event.request.parseUrl("/test") catch continue;

            app.handle(&event) catch continue;
        }

        const end_time = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end_time - start_time));
        const avg_time = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(BENCHMARK_ITERATIONS / 10));

        std.log.info("Fast middleware execution:", .{});
        std.log.info("  Avg time: {d:.2}μs", .{avg_time / 1000.0});
    }

    // Test legacy middleware
    {
        var app = try h3.createApp(allocator);
        defer app.deinit();

        _ = app.use(h3.middleware.logger);
        _ = app.use(h3.middleware.cors);
        _ = app.get("/test", testHandler);

        const start_time = std.time.nanoTimestamp();

        for (0..BENCHMARK_ITERATIONS / 10) |_| {
            var event = h3.Event.init(allocator);
            defer event.deinit();

            event.request.method = .GET;
            event.request.parseUrl("/test") catch continue;

            app.handle(&event) catch continue;
        }

        const end_time = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end_time - start_time));
        const avg_time = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(BENCHMARK_ITERATIONS / 10));

        std.log.info("Legacy middleware execution:", .{});
        std.log.info("  Avg time: {d:.2}μs", .{avg_time / 1000.0});
    }
}

// Benchmark event pool performance
test "Benchmark: Event pool vs direct allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test with event pool
    {
        var pool = h3.EventPool.init(allocator, 50);
        defer pool.deinit();

        try pool.warmUp(25);

        const start_time = std.time.nanoTimestamp();

        for (0..BENCHMARK_ITERATIONS) |_| {
            const event = pool.acquire() catch continue;
            defer pool.release(event);

            // Simulate some work
            event.setContext("test", "value") catch {};
        }

        const end_time = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end_time - start_time));
        const avg_time = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(BENCHMARK_ITERATIONS));

        std.log.info("Event pool allocation:", .{});
        std.log.info("  Avg time: {d:.2}μs", .{avg_time / 1000.0});

        const stats = pool.getStats();
        std.log.info("  Reuse ratio: {d:.2}%", .{stats.reuse_ratio * 100});
    }

    // Test direct allocation
    {
        const start_time = std.time.nanoTimestamp();

        for (0..BENCHMARK_ITERATIONS) |_| {
            var event = h3.Event.init(allocator);
            defer event.deinit();

            // Simulate some work
            event.setContext("test", "value") catch {};
        }

        const end_time = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end_time - start_time));
        const avg_time = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(BENCHMARK_ITERATIONS));

        std.log.info("Direct allocation:", .{});
        std.log.info("  Avg time: {d:.2}μs", .{avg_time / 1000.0});
    }
}

// Simple performance test
test "Benchmark: Basic performance test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test app creation and basic operations
    {
        var app = try h3.createFastApp(allocator);
        defer app.deinit();

        const testHandler = struct {
            fn handler(event: *h3.Event) !void {
                try event.sendText("OK");
            }
        }.handler;

        // Add some routes
        _ = app.get("/", testHandler);
        _ = app.get("/test", testHandler);
        _ = app.post("/api/data", testHandler);

        // Add middleware
        _ = app.useFast(h3.fastMiddleware.logger);
        _ = app.useFast(h3.fastMiddleware.cors);

        std.log.info("✅ Fast app created successfully with routes and middleware", .{});
        std.log.info("   Routes: {d}", .{app.getRouteCount()});
        std.log.info("   Fast middlewares: {d}", .{app.getFastMiddlewareCount()});
    }

    // Test standard app for comparison
    {
        var app = try h3.createApp(allocator);
        defer app.deinit();

        const testHandler = struct {
            fn handler(event: *h3.Event) !void {
                try event.sendText("OK");
            }
        }.handler;

        _ = app.get("/", testHandler);
        _ = app.get("/test", testHandler);
        _ = app.post("/api/data", testHandler);

        _ = app.use(h3.middleware.logger);
        _ = app.use(h3.middleware.cors);

        std.log.info("✅ Standard app created successfully", .{});
        std.log.info("   Routes: {d}", .{app.getRouteCount()});
        std.log.info("   Legacy middlewares: {d}", .{app.getMiddlewareCount()});
    }
}
