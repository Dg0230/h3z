//! HTTP method enumeration and utilities

const std = @import("std");

/// HTTP methods as defined in RFC 7231 and other RFCs
pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
    TRACE,
    CONNECT,

    /// Parse HTTP method from string
    pub fn fromString(method_str: []const u8) ?HttpMethod {
        if (std.mem.eql(u8, method_str, "GET")) return .GET;
        if (std.mem.eql(u8, method_str, "POST")) return .POST;
        if (std.mem.eql(u8, method_str, "PUT")) return .PUT;
        if (std.mem.eql(u8, method_str, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, method_str, "PATCH")) return .PATCH;
        if (std.mem.eql(u8, method_str, "HEAD")) return .HEAD;
        if (std.mem.eql(u8, method_str, "OPTIONS")) return .OPTIONS;
        if (std.mem.eql(u8, method_str, "TRACE")) return .TRACE;
        if (std.mem.eql(u8, method_str, "CONNECT")) return .CONNECT;
        return null;
    }

    /// Convert HTTP method to string
    pub fn toString(self: HttpMethod) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .PATCH => "PATCH",
            .HEAD => "HEAD",
            .OPTIONS => "OPTIONS",
            .TRACE => "TRACE",
            .CONNECT => "CONNECT",
        };
    }

    /// Check if method typically has a request body
    pub fn hasBody(self: HttpMethod) bool {
        return switch (self) {
            .POST, .PUT, .PATCH => true,
            .GET, .DELETE, .HEAD, .OPTIONS, .TRACE, .CONNECT => false,
        };
    }

    /// Check if method is safe (read-only)
    pub fn isSafe(self: HttpMethod) bool {
        return switch (self) {
            .GET, .HEAD, .OPTIONS, .TRACE => true,
            .POST, .PUT, .DELETE, .PATCH, .CONNECT => false,
        };
    }

    /// Check if method is idempotent
    pub fn isIdempotent(self: HttpMethod) bool {
        return switch (self) {
            .GET, .PUT, .DELETE, .HEAD, .OPTIONS, .TRACE => true,
            .POST, .PATCH, .CONNECT => false,
        };
    }
};

test "HttpMethod.fromString" {
    try std.testing.expectEqual(HttpMethod.GET, HttpMethod.fromString("GET").?);
    try std.testing.expectEqual(HttpMethod.POST, HttpMethod.fromString("POST").?);
    try std.testing.expectEqual(@as(?HttpMethod, null), HttpMethod.fromString("INVALID"));
}

test "HttpMethod.toString" {
    try std.testing.expectEqualStrings("GET", HttpMethod.GET.toString());
    try std.testing.expectEqualStrings("POST", HttpMethod.POST.toString());
    try std.testing.expectEqualStrings("DELETE", HttpMethod.DELETE.toString());
}

test "HttpMethod.hasBody" {
    try std.testing.expect(HttpMethod.POST.hasBody());
    try std.testing.expect(HttpMethod.PUT.hasBody());
    try std.testing.expect(HttpMethod.PATCH.hasBody());
    try std.testing.expect(!HttpMethod.GET.hasBody());
    try std.testing.expect(!HttpMethod.DELETE.hasBody());
}

test "HttpMethod.isSafe" {
    try std.testing.expect(HttpMethod.GET.isSafe());
    try std.testing.expect(HttpMethod.HEAD.isSafe());
    try std.testing.expect(!HttpMethod.POST.isSafe());
    try std.testing.expect(!HttpMethod.PUT.isSafe());
}

test "HttpMethod.isIdempotent" {
    try std.testing.expect(HttpMethod.GET.isIdempotent());
    try std.testing.expect(HttpMethod.PUT.isIdempotent());
    try std.testing.expect(HttpMethod.DELETE.isIdempotent());
    try std.testing.expect(!HttpMethod.POST.isIdempotent());
    try std.testing.expect(!HttpMethod.PATCH.isIdempotent());
}
