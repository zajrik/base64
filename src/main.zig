const std = @import("std");

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const WindowIterator = std.mem.WindowIterator;

const window = std.mem.window;

const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualStrings = std.testing.expectEqualStrings;

const Base64 = struct {
    /// All base64 characters, effectively mapping base64 decimal representations
    /// (0 through 63) to their base64 encoded representation.
    const table: *const [64]u8 =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ++
        "abcdefghijklmnopqrstuvwxyz" ++
        "0123456789+/";

    /// Returns the base64 encoded character for the given decimal `index` (`0`-`63`).
    fn charAt(index: u6) u8 {
        return table[index];
    }

    /// Returns the base64 decimal index for the given `char`, or `null` for `'='`.
    fn decodeChar(char: u8) ?u6 {
        return for (table, 0..) |c, i| {
            if (c == char) break @intCast(i);
        } else null;
    }

    /// Convert the given `data` to a base64-encoded string.
    ///
    /// Returns the encoded string.
    pub fn encode(alloc: Allocator, data: []const u8) ![]const u8 {
        if (data.len == 0) return "";

        var out: ArrayList(u8) = .empty;
        var iter: WindowIterator(u8) = window(u8, data, 3, 3);

        while (iter.next()) |it| {
            var chunk: [3]u8 = @splat(0);
            @memcpy(chunk[0..it.len], it);

            const segment: EncodedBase64Segment = .encode(&chunk);

            switch (it.len) {
                3 => try out.appendSlice(alloc, &.{
                    segment.@"0",
                    segment.@"1",
                    segment.@"2",
                    segment.@"3",
                }),

                2 => try out.appendSlice(alloc, &.{
                    segment.@"0",
                    segment.@"1",
                    segment.@"2",
                    '=',
                }),
                1 => try out.appendSlice(alloc, &.{
                    segment.@"0",
                    segment.@"1",
                    '=',
                    '=',
                }),

                else => unreachable,
            }
        }

        return out.toOwnedSlice(alloc);
    }

    /// Decode the given base64-encoded `data`.
    ///
    /// `data` must be at least 4 bytes.
    ///
    /// Returns the decoded bytes.
    pub fn decode(alloc: Allocator, data: []const u8) ![]const u8 {
        if (data.len < 4) return error.InvalidInput;

        var out: ArrayList(u8) = .empty;
        var iter: WindowIterator(u8) = window(u8, data, 4, 4);

        while (iter.next()) |it| {
            var chunk: [4]u8 = @splat(0);
            @memcpy(chunk[0..it.len], it);

            const segment: DecodedBase64Segment = .decode(&chunk);

            try out.append(alloc, segment.@"0");
            if (segment.@"1" > 0) try out.append(alloc, segment.@"1");
            if (segment.@"2" > 0) try out.append(alloc, segment.@"2");
        }

        return out.toOwnedSlice(alloc);
    }
};

/// A 32-bit segment of base64-encoded data, encoded from 24 bits of input data.
const EncodedBase64Segment = packed struct(u32) {
    @"3": u8,
    @"2": u8,
    @"1": u8,
    @"0": u8,

    /// 24 bits of data sliced into 6-bit base64 character indices.
    const Indices = packed struct(u24) { @"3": u6, @"2": u6, @"1": u6, @"0": u6 };

    /// Convert the given chunk of bytes into an `EncodedBase64Segment`.
    pub fn encode(chunk: *const [3]u8) EncodedBase64Segment {
        const segment: u24 =
            @as(u24, chunk[0]) << 16 |
            @as(u16, chunk[1]) << 8 |
            chunk[2];

        const indices: Indices = @bitCast(segment);

        return .{
            .@"0" = Base64.charAt(indices.@"0"),
            .@"1" = Base64.charAt(indices.@"1"),
            .@"2" = Base64.charAt(indices.@"2"),
            .@"3" = Base64.charAt(indices.@"3"),
        };
    }
};

/// A 24-bit segment of binary data, decoded from 32-bits of base64-encoded data.
const DecodedBase64Segment = packed struct(u24) {
    @"2": u8,
    @"1": u8,
    @"0": u8,

    /// Decode the given chunk of base64-encoded bytes.
    pub fn decode(chunk: *const [4]u8) DecodedBase64Segment {
        var chars: [4]u6 = undefined;

        for (chunk, 0..) |char, i| {
            chars[i] = Base64.decodeChar(char) orelse 0;
        }

        const segment: u24 =
            @as(u24, chars[0]) << 18 |
            @as(u18, chars[1]) << 12 |
            @as(u12, chars[2]) << 6 |
            chars[3];

        return @bitCast(segment);
    }
};

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();

    std.debug.print("{s}\n", .{try Base64.encode(a, "hello world!!")});
    std.debug.print("{s}\n", .{try Base64.decode(a, "aGVsbG8gd29ybGQhIQ==")});
}

// /// Lookup table mapping base64 encoded characters to their decimal representation
// /// for decoding.
// ///
// /// Doesn't actually work for decoding since field names need to be comptime-known
// /// to access them via `@field()`. Didn't realize that when I got this idea lol
// const reverse_table: t: {
//     const Type = std.builtin.Type;
//     const Attributes = Type.StructField.Attributes;

//     const field_types: [64]type = @splat(u6);

//     var field_names: [64][]const u8 = undefined;
//     var field_attrs: [64]Attributes = undefined;

//     for (table, 0..) |char, i| {
//         field_names[i] = &.{char};
//         field_attrs[i] = .{ .default_value_ptr = &i, .@"comptime" = true };
//     }

//     break :t @Struct(.auto, null, &field_names, &field_types, &field_attrs);
// } = .{};

test "base64" {
    var arena: Arena = .init(std.testing.allocator);
    const a: Allocator = arena.allocator();
    defer arena.deinit();

    try expectEqual('A', Base64.charAt(0));
    try expectEqual('a', Base64.charAt(26));

    try expectEqual('S', Base64.charAt(18));
    try expectEqual('G', Base64.charAt(6));
    try expectEqual('k', Base64.charAt(36));

    try expectEqualStrings("SGk=", try Base64.encode(a, "Hi"));
    try expectEqualStrings("MA==", try Base64.encode(a, "0"));

    try expectEqual(26, Base64.decodeChar('a'));
    try expectEqual(0, Base64.decodeChar('A'));
    try expectEqual(null, Base64.decodeChar('='));

    const string = "Hello world!!";
    try expectEqualStrings(
        string,
        try Base64.decode(a, try Base64.encode(a, string)),
    );
}
