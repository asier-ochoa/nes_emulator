const std = @import("std");
const Self = @This();

// Addresses 0000-1FFF
// Bitplane format:
// Each tile is "8x8" pixels encoded into 16 bytes.
// A single row in a tile is controlled by 1 byte in the first 8 bytes
// and 1 byte in the last 8 bytes. The first 8 bytes control
// the low bit of a pixel and the last 8 bytes control the
// high bit of a pixel. This effectively gives us 3 palette
// colors per pixel + transparency:
// ---LOW----                           ---HIGH---
// 0b00100001 |10|00|01|00|00|00|00|11| 0b10000001
pattern_tables: [2][0x1000]u8,
// Addresses 2000-2FFF
name_tables: [4][0x400]u8,

pub fn init() Self {
    return .{
        .pattern_tables = .{.{0} ** 0x1000} ** 2,
        .name_tables = .{.{0} ** 0x400} ** 4
    };
}

// Takes data for a single tile from the pattern table and decodes to 8x8 RGB array
// 2 bit number formed by pixel is used to index into palette (24 bit RGB)
pub fn decodePatternTile(tile: []const u8, palette: []const u32, decoded: []u32) void {
    if (tile.len < 16) @panic("Attempted to decode an invalid pattern table tile");
    if (palette.len < 4) @panic("Palette too short");
    if (decoded.len < 8 * 8) @panic("Output buffer too short");

    // Iterate first half and index into second half
    for (tile[0..8], 8..) |t, i| {
        for (0..8) |px| {
            const palette_idx_low = t >> @intCast(7 - px);
            const palette_idx_high = tile[i] >> @intCast(7 - px);
            const palette_idx = 0b0000_0001 & palette_idx_low | (0b0000_0010 & (palette_idx_high << 1));
            decoded[(i - 8) * 8 + px] = palette[palette_idx];
        }
    }
}

test "Pattern Tile decode" {
    const expected =
        \\0x000000FF 0xFF0000FF 0x000000FF 0x000000FF 0x000000FF 0x000000FF 0x000000FF 0x0000FFFF
        \\0xFF0000FF 0xFF0000FF 0x000000FF 0x000000FF 0x000000FF 0x000000FF 0x0000FFFF 0x000000FF
        \\0x000000FF 0xFF0000FF 0x000000FF 0x000000FF 0x000000FF 0x0000FFFF 0x000000FF 0x000000FF
        \\0x000000FF 0xFF0000FF 0x000000FF 0x000000FF 0x0000FFFF 0x000000FF 0x000000FF 0x000000FF
        \\0x000000FF 0x000000FF 0x000000FF 0x0000FFFF 0x000000FF 0x00FF00FF 0x00FF00FF 0x000000FF
        \\0x000000FF 0x000000FF 0x0000FFFF 0x000000FF 0x000000FF 0x000000FF 0x000000FF 0x00FF00FF
        \\0x000000FF 0x0000FFFF 0x000000FF 0x000000FF 0x000000FF 0x000000FF 0x00FF00FF 0x000000FF
        \\0x0000FFFF 0x000000FF 0x000000FF 0x000000FF 0x000000FF 0x00FF00FF 0x00FF00FF 0x00FF00FF
        \\
        ;

    const tile = .{
        // Bitplane 0
        0b01000001, //0b01000003
        0b11000010, //0b11000030
        0b01000100, //0b01000300
        0b01001000, //0b01003000
        0b00010000, //0b00030220
        0b00100000, //0b00300002
        0b01000000, //0b03000020
        0b10000000, //0b30000222
        // Bitplane 1,
        0b00000001,
        0b00000010,
        0b00000100,
        0b00001000,
        0b00010110,
        0b00100001,
        0b01000010,
        0b10000111
    };
    const palette = .{
        0x000000FF,
        0xFF0000FF,
        0x00FF00FF,
        0x0000FFFF,
    };
    var output: [8 * 8]u32 = .{0} ** (8 * 8);

    decodePatternTile(&tile, &palette, &output);

    // Format to string of hex and print
    var output_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer();
    // const writer = std.io.getStdErr().writer();
    for (output, 0..) |px, i| {
        try writer.print("0x{s}", .{
            std.fmt.bytesToHex(std.mem.asBytes(
                &std.mem.nativeTo(u32, px, .big)
            ), .upper)
        });
        if (@mod(i, 8) == 7) {
            try writer.print("\n", .{});
        } else {
            try writer.print(" ", .{});
        }
    }
    
    try std.testing.expectEqualStrings(expected, output_buffer.items);
}