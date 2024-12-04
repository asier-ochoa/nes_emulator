const std = @import("std");
const rl = @import("raylib");
const Self = @This();
const builtin = @import("builtin");

// PPU registers
// These are memory mapped
// MAKE SURE THESE ARE ALWAYS AT THE TOP OF THE STRUCT!!
ppu_control: u8 = 0,  // At 0x2000, Write only
ppu_mask: u8 = 0,  // At 0x2001, Write only
ppu_status: u8 = 0,  // At 0x2002, Read only
oam_addr: u8 = 0,  // At 0x2003, Write only
oam_data: u8 = 0,  // At 0x2004, Read/Write
ppu_scroll: u8 = 0,  // At 0x2005, Write only, writing to this changes the W register to determine x or y
ppu_addr: u16 = 0,  // At 0x2006, Write only, writing changes the W register
ppu_data: u8 = 0,  // At 0x2007, Read/Write
oam_dma: u8 = 0,  // Wierd address

// Internal PPU state
// Indicates if low or high byte is being read
address_latch: u8 = 0,
ppu_data_buffer: u8 = 0,

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
// Addresses 3F00-3F1F,
palette_ram: [32]u8,

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
        .name_tables = .{.{0} ** 0x400} ** 4,
        .palette_ram = .{0} ** 32
    };
}

// One clock cycle paints one pixel
pub fn tick(self: *Self) void {
    // Fill with noise, one pixel at a time
    self.frame_buffer[@as(usize, self.cur_scanline) * frame_buffer_width + @as(usize, self.cur_column)] = @as(u32, @intCast(rl.getRandomValue(0, 0xFFFFFF))) << 8 | 0x000000FF;

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

const PpuControlRegisterFlags = enum(u8) {
    vblank_nmi = 1 << 7,
    ppu_master_slave = 1 << 6,
    sprite_size = 1 << 5,  // 0 is 8x8, 1 is 8x16
    background_ptrn_tbl_base = 1 << 4,
    sprite_ptrn_tbl_base = 1 << 3,
    vram_addr_increment = 1 << 2,  // 0 is increment 1, 1 is increment 32
    // 0 = 0x2000, 1 = 0x2400, 2 = 0x2800, 3 = 0x2C00
    base_name_tbl_h = 1 << 1,
    base_name_tbl_l = 1,
    pub inline fn get(self: @This()) u8 {
        return @intFromEnum(self);
    }
};

const PpuMaskRegisterFlags = enum(u8) {
    emphasis_b = 1 << 7,
    emphasis_g = 1 << 6,
    emphasis_r = 1 << 5,
    enable_sprites = 1 << 4,
    enable_background = 1 << 3,
    show_sprites_left = 1 << 2,
    show_background_left = 1 << 1,
    greyscale = 1,
    pub inline fn get(self: @This()) u8 {
        return @intFromEnum(self);
    }
};
pub const PPUMASK = PpuMaskRegisterFlags;

const PpuStatusRegisterFlags = enum(u8) {
    vblank = 1 << 7,
    sprite0 = 1 << 6,
    sprite_overflow = 1 << 5,
    pub inline fn get(self: @This()) u8 {
        return @intFromEnum(self);
    }
};
pub const PPUSTAT = PpuStatusRegisterFlags;

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
    var ret: ?*u8 = null;
    inline for (@typeInfo(Self).Struct.fields[0..8], 0..) |f, i| {
        if (i == address_from_base) {
            // PPU address retrieval logic
            // Right now im giving it data that has nothing to do with the address
            if (i == 6) {
                ret = &self.address_latch;
            } else {
                ret = &@field(self, f.name);
            }
        }
    }

    return ret;
}

// Address given in CPU space
pub fn ppu_write(self: *Self, data: u8, address: u16) void {
    switch (address - 0x2000) {
        // PPU Control
        0 => {
            self.ppu_control = data;
        },
        // PPU Mask
        1 => {
            self.ppu_mask = data;
        },
        2 => {},
        3 => {},
        4 => {},
        5 => {},
        // PPU Address
        6 => {
            if (self.address_latch == 0) {
                // Set high byte of address
                self.ppu_addr = self.ppu_addr & 0x00FF | (@as(u16, data) << 8);
                self.address_latch = 1;
            } else {
                // Set low byte of address
                self.ppu_addr = self.ppu_addr & 0xFF00 | data;
                self.address_latch = 0;
            }
        },
        // PPU Data
        7 => {
            self.ppu_data = data;
            self.memory_write(self.ppu_addr, self.ppu_data);
            // NES autoincrements the address
            self.ppu_addr +%= 1;
        },
        else => @panic("Unknown ppu write!"),
    }
}

// Address given in CPU space
pub fn ppu_read(self: *Self, address: u16, comptime debug_read: bool) u8 {
    var data = self.getFieldFromAddr(address).?.*;

    // Certain PPU reads change its state
    if (!debug_read) {
        switch (address - 0x2000) {
            // PPU Status
            2 => {
                // First 3 bits are filled with status register, rest is sourced from data register
                data = self.ppu_status & 0xE0 | self.ppu_data & 0x1F;
                // TODO: Remove this hack for always returning vblank = 1
                data |= PPUSTAT.vblank.get();

                // Reset data latch
                self.address_latch = 0;
                // Reset vblank flag
                self.ppu_status &= ~PPUSTAT.vblank.get();
            },
            // PPU Address
            6 => {},
            // PPU Data
            7 => {
                // There is a 1 cycle read delay from the ppu
                data = self.ppu_data_buffer;
                self.ppu_data_buffer = self.memory_read(self.ppu_addr);

                // Palette reads dont have a 1 cycle delay
                if (self.ppu_addr >= 0x3f00) data = self.ppu_data_buffer;

                // NES autoincrements the address
                self.ppu_addr +%= 1;
            },
            else => {@panic("Unknown field!");},
        }
    }
    return data;
}

fn memory_read(self: *Self, address: u16) u8 {
    // Top 2 bits are not used
    var addr = address & 0x3FFF;

    // Pattern memory
    if (addr <= 0x1FFF) {
        return self.pattern_tables[(addr & 0x1000) >> 12][addr & 0x0FFF];
    // Palette ram
    } else if (addr >= 0x3F00 and addr <= 0x3FFF) {
        // Only need 5 bits to access 32 long array
        addr &= 0x001F;
        // Mirror background color between sprite and background palettes
        if (addr == 0x0010) addr = 0x0000;
        if (addr == 0x0014) addr = 0x0004;
        if (addr == 0x0018) addr = 0x0008;
        if (addr == 0x001C) addr = 0x000C;
        return self.palette_ram[addr];
    }
    return 0;
}

fn memory_write(self: *Self, address: u16, data: u8) void {
    // Top 2 bits are not used
    var addr = address & 0x3FFF;

    // Pattern memory
    if (addr <= 0x1FFF) {
        self.pattern_tables[(addr & 0x1000) >> 12][addr & 0x0FFF] = data;
    // Palette ram
    } else if (addr >= 0x3F00 and addr <= 0x3FFF) {
        // Only need 5 bits to access 32 long array
        addr &= 0x001F;
        // Mirror background color between sprite and background palettes
        if (addr == 0x0010) addr = 0x0000;
        if (addr == 0x0014) addr = 0x0004;
        if (addr == 0x0018) addr = 0x0008;
        if (addr == 0x001C) addr = 0x000C;
        self.palette_ram[addr] = data;
    }
}

pub fn getNtscPaletteColor(index: u8) u32 {
    const pal_file = @embedFile("./resources/ntscpalette.pal");
    return switch (index) {
        inline 0...0x3F => |i| @as(u32, std.mem.readPackedInt(u24, pal_file[i * 3..i * 3 + 3], 0, builtin.cpu.arch.endian())) << 8 | 0xFF,
        inline else => @panic("NTSC palette index out of range!")
    };
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