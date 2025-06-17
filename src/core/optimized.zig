//! Optimized H3 components for high-performance applications
//! This module exports optimized versions of core H3 components

pub const RouteCache = @import("optimized/route_cache.zig").RouteCache;
pub const EventPool = @import("optimized/event_pool.zig").EventPool;
pub const MemoryManager = @import("optimized/memory_manager.zig").MemoryManager;
pub const MemoryConfig = @import("optimized/memory_manager.zig").MemoryConfig;
pub const AllocationStrategy = @import("optimized/memory_manager.zig").AllocationStrategy;
pub const FastMiddleware = @import("optimized/fast_middleware.zig");

// Re-export commonly used types
pub const PoolStats = @import("optimized/event_pool.zig").PoolStats;
pub const MemoryStats = @import("optimized/memory_manager.zig").MemoryStats;

test {
    @import("std").testing.refAllDecls(@This());
}
