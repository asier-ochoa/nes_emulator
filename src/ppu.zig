const std = @import("std");
const rl = @import("raylib");
const Self = @This();

// PPU registers
// These are memory mapped
// MAKE SURE THESE ARE ALWAYS AT THE TOP OF THE STRUCT!!
ppu_control: u8 = 0,  // At 0x2000, Write only
ppu_mask: u8 = 0,  // At 0x2001, Write only
ppu_status: u8 = 3,  // At 0x2002, Read only
oam_addr: u8 = 0,  // At 0x2003, Write only
oam_data: u8 = 0,  // At 0x2004, Read/Write
ppu_scroll: u8 = 0,  // At 0x2005, Write only, writing to this changes the W register to determine x or y
ppu_addr: u8 = 0,  // At 0x2006, Write only, writing changes the W register
ppu_data: u8 = 0,  // At 0x2007, Read/Write
oam_dma: u8 = 0,  // Wierd address

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

// Represents the final screen image
frame_buffer: [frame_buffer_height * frame_buffer_width]u32 = .{0} ** (frame_buffer_height * frame_buffer_width),
// Location of currently drawn pixel
cur_column: u16 = 0,
cur_scanline: u16 = 0,
pub const frame_buffer_width = 256;
pub const frame_buffer_height = 240;

pub fn init() Self {
    return .{
        .pattern_tables = .{.{0} ** 0x1000} ** 2,
        .name_tables = .{.{0} ** 0x400} ** 4
    };
}

// One clock cycle paints one pixel
pub fn tick(self: *Self) void {
    // Fill with noise, one pixel at a time
    self.frame_buffer[@as(usize, self.cur_scanline) * frame_buffer_width + @as(usize, self.cur_column)] = @as(u32, @intCast(rl.getRandomValue(0, 0xFFFFFF))) << 8 | 0x000000FF;
    // self.frame_buffer[@as(usize, self.cur_scanline) * frame_buffer_width + @as(usize, self.cur_column)] = 0x00FF00FF;

    // Advance currently drawn pixel
    self.cur_column += 1;
    if (self.cur_column >= frame_buffer_width) {
        self.cur_column = 0;
        self.cur_scanline += 1;
    }
    if (self.cur_scanline >= frame_buffer_height) {
        self.cur_scanline = 0;
    }
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

pub fn getFieldFromAddr(self: *Self, address: u16) ?*u8 {
    const address_from_base = address - 0x2000;
    if (address_from_base < 0) return null;
    // Iterate only through the ppu register fields
    inline for (@typeInfo(Self).Struct.fields[0..8], 0..) |f, i| {
        if (i == address_from_base) return &@field(self, f.name);
    }
    return null;
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