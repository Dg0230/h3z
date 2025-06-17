const std = @import("std");
const h3 = @import("h3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🧪 Memory Leak Test", .{});
    std.log.info("==================", .{});

    // Test event pool memory management
    var pool = h3.optimized.EventPool.init(allocator, 10);
    defer pool.deinit();

    std.log.info("Testing event pool memory management...", .{});

    // Simulate 100 request cycles
    for (0..100) |i| {
        const event = try pool.acquire();

        // Simulate setting context and params (this was causing leaks)
        try event.setContext("request_id", "12345");
        try event.setContext("user_id", "user123");
        try event.setParam("param1", "value1");
        try event.setParam("param2", "value2");

        // Release the event back to pool
        pool.release(event);

        if (i % 10 == 0) {
            std.log.info("Completed {} cycles", .{i + 1});
        }
    }

    const stats = pool.getStats();
    std.log.info("Pool stats:", .{});
    std.log.info("  Created: {}", .{stats.created_count});
    std.log.info("  Reused: {}", .{stats.reuse_count});
    std.log.info("  Pool size: {}", .{stats.pool_size});
    std.log.info("  Reuse ratio: {d:.1}%", .{stats.reuse_ratio * 100});

    std.log.info("✅ Memory leak test completed", .{});
}
