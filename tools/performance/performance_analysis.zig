//! Performance analysis tool for H3 framework
//! This tool helps identify performance bottlenecks and memory issues

const std = @import("std");
const h3 = @import("h3");

const ITERATIONS = 1000;
const ROUTE_COUNT = 100;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🔍 H3 Performance Analysis Tool", .{});
    std.log.info("================================", .{});

    // Test 1: Basic app creation and route registration
    try testAppCreation(allocator);

    // Test 2: Route lookup performance
    try testRouteLookup(allocator);

    // Test 3: Event pool performance
    try testEventPool(allocator);

    // Test 4: Memory usage analysis
    try testMemoryUsage(allocator);

    // Test 5: Middleware performance
    try testMiddlewarePerformance(allocator);

    std.log.info("", .{});
    std.log.info("✅ Performance analysis completed", .{});
}

fn testAppCreation(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("📊 Test 1: App Creation Performance", .{});
    std.log.info("-----------------------------------", .{});

    const start_time = std.time.nanoTimestamp();

    // Test standard app creation
    {
        const app_start = std.time.nanoTimestamp();
        var app = try h3.createApp(allocator);
        defer app.deinit();
        const app_end = std.time.nanoTimestamp();
        const app_time = app_end - app_start;

        std.log.info("Standard app creation: {d:.2}μs", .{@as(f64, @floatFromInt(app_time)) / 1000.0});
    }

    // Test fast app creation
    {
        const fast_start = std.time.nanoTimestamp();
        var app = try h3.createFastApp(allocator);
        defer app.deinit();
        const fast_end = std.time.nanoTimestamp();
        const fast_time = fast_end - fast_start;

        std.log.info("Fast app creation: {d:.2}μs", .{@as(f64, @floatFromInt(fast_time)) / 1000.0});
    }

    const end_time = std.time.nanoTimestamp();
    const total_time = end_time - start_time;
    std.log.info("Total test time: {d:.2}ms", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
}

fn testRouteLookup(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("📊 Test 2: Route Lookup Performance", .{});
    std.log.info("-----------------------------------", .{});

    var app = try h3.createFastApp(allocator);
    defer app.deinit();

    const testHandler = struct {
        fn handler(event: *h3.Event) !void {
            try event.sendText("OK");
        }
    }.handler;

    // Add many routes
    const route_start = std.time.nanoTimestamp();
    for (0..ROUTE_COUNT) |i| {
        var path_buffer: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(path_buffer[0..], "/api/route{d}", .{i});
        _ = app.get(path, testHandler);
    }
    const route_end = std.time.nanoTimestamp();
    const route_time = route_end - route_start;

    std.log.info("Added {d} routes in: {d:.2}ms", .{ ROUTE_COUNT, @as(f64, @floatFromInt(route_time)) / 1_000_000.0 });

    // Test route lookup performance
    const lookup_start = std.time.nanoTimestamp();
    for (0..ITERATIONS) |_| {
        const route = app.findRoute(.GET, "/api/route25");
        _ = route;
    }
    const lookup_end = std.time.nanoTimestamp();
    const lookup_time = lookup_end - lookup_start;
    const avg_lookup = @as(f64, @floatFromInt(lookup_time)) / @as(f64, @floatFromInt(ITERATIONS));

    std.log.info("Route lookup ({d} iterations): {d:.2}μs avg", .{ ITERATIONS, avg_lookup / 1000.0 });
    std.log.info("Total routes: {d}", .{app.getRouteCount()});
}

fn testEventPool(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("📊 Test 3: Event Pool Performance", .{});
    std.log.info("----------------------------------", .{});

    var pool = h3.EventPool.init(allocator, 50);
    defer pool.deinit();

    // Warm up the pool
    try pool.warmUp(25);

    // Test pool performance
    const pool_start = std.time.nanoTimestamp();
    for (0..ITERATIONS) |_| {
        const event = try pool.acquire();
        defer pool.release(event);

        // Simulate some work
        try event.setContext("test", "value");
    }
    const pool_end = std.time.nanoTimestamp();
    const pool_time = pool_end - pool_start;
    const avg_pool = @as(f64, @floatFromInt(pool_time)) / @as(f64, @floatFromInt(ITERATIONS));

    const stats = pool.getStats();
    std.log.info("Event pool ({d} iterations): {d:.2}μs avg", .{ ITERATIONS, avg_pool / 1000.0 });
    std.log.info("Pool reuse ratio: {d:.2}%", .{stats.reuse_ratio * 100});
    std.log.info("Pool hits: {d}, misses: {d}", .{ stats.reuse_count, stats.created_count });

    // Test direct allocation for comparison
    const direct_start = std.time.nanoTimestamp();
    for (0..ITERATIONS) |_| {
        var event = h3.Event.init(allocator);
        defer event.deinit();

        // Simulate some work
        try event.setContext("test", "value");
    }
    const direct_end = std.time.nanoTimestamp();
    const direct_time = direct_end - direct_start;
    const avg_direct = @as(f64, @floatFromInt(direct_time)) / @as(f64, @floatFromInt(ITERATIONS));

    std.log.info("Direct allocation ({d} iterations): {d:.2}μs avg", .{ ITERATIONS, avg_direct / 1000.0 });

    const improvement = (avg_direct - avg_pool) / avg_direct * 100;
    std.log.info("Pool improvement: {d:.1}%", .{improvement});
}

fn testMemoryUsage(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("📊 Test 4: Memory Usage Analysis", .{});
    std.log.info("---------------------------------", .{});

    // Test memory usage with different configurations
    const memory_config = h3.MemoryConfig{
        .enable_event_pool = true,
        .event_pool_size = 100,
        .allocation_strategy = .performance,
    };

    var memory_manager = try h3.MemoryManager.init(allocator, memory_config);
    defer memory_manager.deinit();

    // Simulate memory usage
    const mem_start = std.time.nanoTimestamp();
    var events: [50]*h3.Event = undefined;

    for (0..50) |i| {
        events[i] = try memory_manager.acquireEvent();
        try events[i].setContext("test", "value");
    }

    for (0..50) |i| {
        memory_manager.releaseEvent(events[i]);
    }

    const mem_end = std.time.nanoTimestamp();
    const mem_time = mem_end - mem_start;

    const stats = memory_manager.getStats();
    std.log.info("Memory test time: {d:.2}ms", .{@as(f64, @floatFromInt(mem_time)) / 1_000_000.0});
    std.log.info("Memory efficiency: {d:.2}%", .{memory_manager.getPoolEfficiency() * 100});
    std.log.info("Total allocated: {d} bytes", .{stats.total_allocated});
    std.log.info("Current usage: {d} bytes", .{stats.current_usage});
    std.log.info("Peak usage: {d} bytes", .{stats.peak_usage});
    std.log.info("Pool hits: {d}, misses: {d}", .{ stats.pool_hits, stats.pool_misses });

    if (memory_manager.isMemoryHealthy()) {
        std.log.info("✅ Memory usage is healthy", .{});
    } else {
        std.log.warn("⚠️  Memory usage needs attention", .{});
    }
}

fn testMiddlewarePerformance(allocator: std.mem.Allocator) !void {
    std.log.info("", .{});
    std.log.info("📊 Test 5: Middleware Performance", .{});
    std.log.info("----------------------------------", .{});

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

        const fast_start = std.time.nanoTimestamp();

        for (0..ITERATIONS / 10) |_| {
            var event = h3.Event.init(allocator);
            defer event.deinit();

            event.request.method = .GET;
            try event.request.parseUrl("/test");

            app.handle(&event) catch {};
        }

        const fast_end = std.time.nanoTimestamp();
        const fast_time = fast_end - fast_start;
        const avg_fast = @as(f64, @floatFromInt(fast_time)) / @as(f64, @floatFromInt(ITERATIONS / 10));

        std.log.info("Fast middleware ({d} requests): {d:.2}μs avg", .{ ITERATIONS / 10, avg_fast / 1000.0 });
        std.log.info("Fast middleware count: {d}", .{app.getFastMiddlewareCount()});
    }

    // Test legacy middleware
    {
        var app = try h3.createApp(allocator);
        defer app.deinit();

        _ = app.use(h3.middleware.logger);
        _ = app.use(h3.middleware.cors);
        _ = app.get("/test", testHandler);

        const legacy_start = std.time.nanoTimestamp();

        for (0..ITERATIONS / 10) |_| {
            var event = h3.Event.init(allocator);
            defer event.deinit();

            event.request.method = .GET;
            try event.request.parseUrl("/test");

            app.handle(&event) catch {};
        }

        const legacy_end = std.time.nanoTimestamp();
        const legacy_time = legacy_end - legacy_start;
        const avg_legacy = @as(f64, @floatFromInt(legacy_time)) / @as(f64, @floatFromInt(ITERATIONS / 10));

        std.log.info("Legacy middleware ({d} requests): {d:.2}μs avg", .{ ITERATIONS / 10, avg_legacy / 1000.0 });
        std.log.info("Legacy middleware count: {d}", .{app.getMiddlewareCount()});
    }
}
