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

    /// Returns the base64 encoded character for the given decimal `index` (`0`-`63`).
    fn charAt(index: u6) u8 {
        return table[index];
    }

    /// Returns the base64 decimal index for the given `char`, or `null` for `'='`.
    fn decodeChar(char: u8) ?u6 {
        return for (table, 0..) |c, i| {
            if (c == char) break @as(u6, @truncate(i));
        } else null;
    }

    /// Convert the given `string` to a base64 string.
    ///
    /// Returns the encoded string.
    pub fn encode(alloc: Allocator, string: []const u8) ![]const u8 {
        if (string.len == 0) return "";

        var out: ArrayList(u8) = .empty;
        var iter: WindowIterator(u8) = window(u8, string, 3, 3);

        while (iter.next()) |it| {
            var slice: [3]u8 = @splat(0);
            @memcpy(slice[0..it.len], it);

            const chunk: Base64Segment = .encodeChunk(&slice);

            switch (it.len) {
                3 => try out.appendSlice(alloc, &.{
                    Base64.charAt(chunk.@"0"),
                    Base64.charAt(chunk.@"1"),
                    Base64.charAt(chunk.@"2"),
                    Base64.charAt(chunk.@"3"),
                }),

                2 => try out.appendSlice(alloc, &.{
                    Base64.charAt(chunk.@"0"),
                    Base64.charAt(chunk.@"1"),
                    Base64.charAt(chunk.@"2"),
                    '=',
                }),
                1 => try out.appendSlice(alloc, &.{
                    Base64.charAt(chunk.@"0"),
                    Base64.charAt(chunk.@"1"),
                    '=',
                    '=',
                }),

                else => unreachable,
            }
        }

        return out.toOwnedSlice(alloc);
    }

    /// Decode the given base64 string.
    ///
    /// Returns the decoded string.
    pub fn decode(alloc: Allocator, string: []const u8) ![]const u8 {
        var out: ArrayList(u8) = .empty;
        var iter: WindowIterator(u8) = window(u8, string, 4, 4);

        while (iter.next()) |it| {
            var decoded_chars: [4]u6 = undefined;
            for (it, 0..) |char, i| decoded_chars[i] = decodeChar(char) orelse 0;

            const segment: u24 =
                @as(u24, decoded_chars[0]) << 18 |
                @as(u18, decoded_chars[1]) << 12 |
                @as(u12, decoded_chars[2]) << 6 |
                decoded_chars[3];

            const char_1: u8 = @truncate(segment >> 16);
            const char_2: u8 = @truncate(segment >> 8);
            const char_3: u8 = @truncate(segment);

            try out.append(alloc, char_1);
            if (char_2 > 0) try out.append(alloc, char_2);
            if (char_3 > 0) try out.append(alloc, char_3);
        }

        return out.toOwnedSlice(alloc);
    }

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
        try expectEqual(
            string,
            try Base64.decode(a, try Base64.encode(a, string)),
        );
    }
};

/// A segment of base64-encoded characters.
///
/// Represents 3 input characters (3 bytes, 24 bits) split into four 6-bit chunks,
/// each representing the index of a character on the base64 scale.
const Base64Segment = packed struct(u24) {
    @"3": u6,
    @"2": u6,
    @"1": u6,
    @"0": u6,

    /// Conver the given 24-bit input `segment` into a `Base64Segment`.
    pub fn encode(segment: u24) Base64Segment {
        return @bitCast(segment);
    }

    /// Convert the given chunk of char bytes into a `Base64Segment`.
    pub fn encodeChunk(in: *const [3]u8) Base64Segment {
        return .encode(@as(u24, in[0]) << 16 | @as(u16, in[1]) << 8 | in[2]);
    }

    /// Convert this `Base64Segment` into a 24-bit integer.
    pub fn decode(self: Base64Segment) u24 {
        return @bitCast(self);
    }

    /// Convert this `Base64Segment` into an array of character bytes.
    pub fn decodeChunk(self: Base64Segment) [3]u8 {
        const decoded: u24 = self.decode();
        return .{
            @truncate(decoded >> 16),
            @truncate(decoded >> 8),
            @truncate(decoded),
        };
    }

    test "segment" {
        const s = Base64Segment;

        try expectEqualDeep(
            s.encode(0xFF1122),
            s.encodeChunk(&.{ 0xFF, 0x11, 0x22 }),
        );

        try expectEqualDeep(
            s.encode(0xFF1122).decodeChunk(),
            [3]u8{ 0xFF, 0x11, 0x22 },
        );
    }
};

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();

    std.debug.print("{s}\n", .{try Base64.encode(a, "hello world!!")});
    std.debug.print("{s}\n", .{try Base64.decode(a, "aGVsbG8gd29ybGQhIQ==")});
}
