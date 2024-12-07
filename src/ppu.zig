const std = @import("std");
const rl = @import("raylib");
const Self = @This();
const builtin = @import("builtin");
const util = @import("util.zig");

// PPU registers
// These are memory mapped
// MAKE SURE THESE ARE ALWAYS AT THE TOP OF THE STRUCT!!
ppu_control: u8 = 0,  // At 0x2000, Write only
ppu_mask: u8 = 0,  // At 0x2001, Write only
ppu_status: u8 = 0,  // At 0x2002, Read only
oam_addr: u8 = 0,  // At 0x2003, Write only
oam_data: u8 = 0,  // At 0x2004, Read/Write
ppu_scroll: u16 = 0,  // At 0x2005, Write only, writing to this changes the W register to determine x or y
ppu_addr: Loopy = @enumFromInt(0),  // At 0x2006, Write only, writing changes the W register, ALSO KNOWN AS LOOPY VRAM ADDRESS
ppu_data: u8 = 0,  // At 0x2007, Read/Write
oam_dma: u8 = 0,  // Wierd address

// Internal PPU state
// Indicates if low or high byte is being read
address_latch: u8 = 0,
ppu_data_buffer: u8 = 0,
tram_addr: Loopy = @enumFromInt(0),  // Second loopy register
fine_x: u8 = 0,

// Nametable prefetching variables
next_ptrn_idx: u8 = 0,  // Indexes into pattern table
next_ptrn_attr: u8 = 0,
next_ptrn_lsb: u8 = 0,  // These 2 bitplanes are used to render 8 pixels at 2 bits per pixel
next_ptrn_msb: u8 = 0,

// Shift registers used in final drawing
shifter_ptrn_lsb: u16 = 0,
shifter_ptrn_msb: u16 = 0,
shifter_attr_lsb: u16 = 0,
shifter_attr_msb: u16 = 0,

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

nametable_mirroring: enum {h, v},

// Represents the final screen image
frame_buffer: [frame_buffer_height * frame_buffer_width]u32 = .{0} ** (frame_buffer_height * frame_buffer_width),
// Location of currently drawn pixel
cur_column: u16 = 0,
cur_scanline: i16 = 0,
pub const frame_buffer_width = 256;
pub const frame_buffer_height = 240;
pub const PPU_scanlines = 261;
pub const PPU_columns = 341;

pub fn init() Self {
    return .{
        .pattern_tables = .{.{0} ** 0x1000} ** 2,
        .name_tables = .{.{0} ** 0x400} ** 4,
        .palette_ram = .{0} ** 32,
        .nametable_mirroring = .h,
    };
}

// One clock cycle paints one pixel
pub fn tick(self: *Self, cpu: *util.NesCpu) void {

    // Reset vblanking state when at top left of screen
    if (self.cur_scanline == -1 and self.cur_column == 1) {
        // Set vblank to false
        self.ppu_status &= ~PPUSTAT.get(.vblank) ;
    }

    // Send NMI to cpu (Rendering done)
    if (self.cur_scanline == 241 and self.cur_column == 1) {
        // Set vblank to true
        self.ppu_status |= PPUSTAT.get(.vblank);
        if (self.ppu_control & PPUCTRL.get(.vblank_nmi) > 0) {
            cpu.nmi_latch = true;
        }
    }

    // Rendering logic
    if (self.cur_scanline >= -1 and self.cur_scanline < frame_buffer_height) {
        // Refer to frame timing diagram
        if (self.cur_column >= 2 and self.cur_column < 258 or self.cur_column >= 321 and self.cur_column < 338) {
            // Shift registers move every cycle
            self.updateShifters();
            switch (@mod(self.cur_column - 1, 8)) {
                // Extract the pattern id
                0 => {
                    self.loadShifter();
                    self.next_ptrn_idx = self.memory_read(0x2000 | (self.ppu_addr.get() & 0x0FFF));
                },
                // Extract the attributes
                2 => {
                    self.next_ptrn_attr = self.memory_read(0x23C0 | (self.ppu_addr.getVal(.nametable_select) << 10) | ((self.ppu_addr.getVal(.coarse_y_scroll) >> 2) << 3) | (self.ppu_addr.getVal(.coarse_x_scroll) >> 2));
                    if (self.ppu_addr.getVal(.coarse_y_scroll) & 0x02 != 0) self.next_ptrn_attr >>= 4;
                    if (self.ppu_addr.getVal(.coarse_x_scroll) & 0x02 != 0) self.next_ptrn_attr >>= 2;
                    self.next_ptrn_attr &= 0x03;
                },
                4 => {
                    self.next_ptrn_lsb = self.memory_read((@as(u16, self.ppu_control & PPUCTRL.background_ptrn_tbl_base.get()) << 8) + (@as(u16, self.next_ptrn_idx) << 4) + self.ppu_addr.getVal(.fine_y_scroll) + 0);
                },
                6 => {
                    self.next_ptrn_msb = self.memory_read((@as(u16, self.ppu_control & PPUCTRL.background_ptrn_tbl_base.get()) << 8) + (@as(u16, self.next_ptrn_idx) << 4) + self.ppu_addr.getVal(.fine_y_scroll) + 8);
                },
                7 => self.incrementRenderScrollX(),
                else => {},
            }

        }

        if (self.cur_column == 256) self.incrementRenderScrollY();

        if (self.cur_column == 257) {
            self.loadShifter();
            self.transferX();
        }

        if (self.cur_scanline == -1 and self.cur_column >= 280 and self.cur_column < 305) self.transferY();

        // Select pixel color to draw with if background drawing is enabled
        var pixel: u8 = 0;  // 2 bit color
        var palette: u8 = 0;  // 3 bit palette
        if (self.ppu_mask & PPUMASK.enable_background.get() != 0) {
            // Scroll the bit with fine_x
            const bit_mux: u16 = @as(u16, 0x8000) >> @intCast(self.fine_x);
            // Which bitplane is selected
            const bit_plane0 = @intFromBool((self.shifter_ptrn_lsb & bit_mux) > 0);
            const bit_plane1 = @intFromBool((self.shifter_ptrn_msb & bit_mux) > 0);
            pixel = @as(u8, bit_plane1) << 1 | bit_plane0;

            const palette0 = @intFromBool((self.shifter_attr_lsb & bit_mux) > 0);
            const palette1 = @intFromBool((self.shifter_attr_msb & bit_mux) > 0);
            palette = @as(u8, palette1) << 1 | palette0;
        }
        if (self.cur_scanline >= 0 and self.cur_column < frame_buffer_width) {
            const scanline: u16 = @intCast(self.cur_scanline);
            self.frame_buffer[scanline * frame_buffer_width + self.cur_column] = std.mem.nativeToLittle(
                u32,
                getNtscPaletteColor(self.memory_read(@as(u16, 0x3F00) + (palette << 2) + pixel)),
            );
        }
    }

    // Advance currently drawn pixel
    self.cur_column += 1;
    if (self.cur_column >= PPU_columns) {
        self.cur_column = 0;
        self.cur_scanline += 1;
    }
    if (self.cur_scanline >= PPU_scanlines) {
        self.cur_scanline = -1;
    }
}

// Increments coarse x of loopy register, taking into account nametable wrapping
fn incrementRenderScrollX(self: *Self) void {
    if (self.ppu_mask & (PPUMASK.enable_background.get() | PPUMASK.enable_sprites.get()) != 0) {
        if (self.ppu_addr.getVal(.coarse_x_scroll) == 31) {
            self.ppu_addr.setVal(.coarse_x_scroll, 0);
            // Flip nametable_x
            self.ppu_addr.set((~self.ppu_addr.get() & 0x0400) | (self.ppu_addr.get() & ~@as(u16, 0x0400)));
        } else {
            // Stay in current name table and increment scroll
            self.ppu_addr.setVal(.coarse_x_scroll, @intCast(self.ppu_addr.getVal(.coarse_x_scroll) + 1));
        }
    }
}

// Increments coarse y of loopy register, taking into account nametable wrapping. Moving "1 scanline" in memory
fn incrementRenderScrollY(self: *Self) void {
    if (self.ppu_mask & (PPUMASK.enable_background.get() | PPUMASK.enable_sprites.get()) != 0) {
        // Increment fine Y if we are still not at the end of pattern
        const coarse_y = self.ppu_addr.getVal(.coarse_y_scroll);
        const fine_y = self.ppu_addr.getVal(.fine_y_scroll);
        if (fine_y < 7) {
            self.ppu_addr.setVal(.fine_y_scroll, @intCast(fine_y + 1));
        } else {
            // Reset fine y
            self.ppu_addr.setVal(.fine_y_scroll, 0);
            if (coarse_y == 29) {
                self.ppu_addr.setVal(.coarse_y_scroll, 0);
                // Flip nametable_y
                self.ppu_addr.set((~self.ppu_addr.get() & 0x0800) | (self.ppu_addr.get() & ~@as(u16, 0x0800)));
            } else if (coarse_y == 31) {
                self.ppu_addr.setVal(.coarse_y_scroll, 0);
            } else {
                self.ppu_addr.setVal(.coarse_y_scroll, @intCast(coarse_y + 1));
            }
        }
    }
}

fn transferX(self: *Self) void {
    if (self.ppu_mask & (PPUMASK.enable_background.get() | PPUMASK.enable_sprites.get()) != 0) {
        // Transfer nametable X
        self.ppu_addr.set((self.tram_addr.get() & 0x0400) | (self.ppu_addr.get() & ~@as(u16, 0x0400)));
        self.ppu_addr.setVal(.coarse_x_scroll, @intCast(self.tram_addr.getVal(.coarse_x_scroll)));
    }
}

fn transferY(self: *Self) void {
    if (self.ppu_mask & (PPUMASK.enable_background.get() | PPUMASK.enable_sprites.get()) != 0) {
        // Transfer nametable Y
        self.ppu_addr.set((self.tram_addr.get() & 0x0800) | (self.ppu_addr.get() & ~@as(u16, 0x0800)));
        self.ppu_addr.setVal(.coarse_y_scroll, @intCast(self.tram_addr.getVal(.coarse_y_scroll)));
        self.ppu_addr.setVal(.fine_y_scroll, @intCast(self.tram_addr.getVal(.fine_y_scroll)));
    }
}

fn loadShifter(self: *Self) void {
    self.shifter_ptrn_lsb = (self.shifter_ptrn_lsb & 0xFF00) | self.next_ptrn_lsb;
    self.shifter_ptrn_msb = (self.shifter_ptrn_msb & 0xFF00) | self.next_ptrn_msb;
    self.shifter_attr_lsb = (self.shifter_attr_lsb & 0xFF00) | @as(u16, if (self.next_ptrn_attr & 0b01 != 0) 0xFF else 0);
    self.shifter_attr_msb = (self.shifter_attr_msb & 0xFF00) | @as(u16, if (self.next_ptrn_attr & 0b10 != 0) 0xFF else 0);
}

fn updateShifters(self: *Self) void {
    if (self.ppu_mask & PPUMASK.enable_background.get() != 0) {
        self.shifter_ptrn_lsb <<= 1;
        self.shifter_ptrn_msb <<= 1;
        self.shifter_attr_lsb <<= 1;
        self.shifter_attr_msb <<= 1;
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
pub const PPUCTRL = PpuControlRegisterFlags;

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

const PpuScrollRegisterFlags = enum(u16) {
    coarse_x = 0xFF00,
    coarse_y = 0x00FF,
    pub inline fn get(self: @This()) u16 {
        return @intFromEnum(self);
    }
};
pub const PPUSCROLL = PpuScrollRegisterFlags;

const PpuStatusRegisterFlags = enum(u8) {
    vblank = 1 << 7,
    sprite0 = 1 << 6,
    sprite_overflow = 1 << 5,
    pub inline fn get(self: @This()) u8 {
        return @intFromEnum(self);
    }
};
pub const PPUSTAT = PpuStatusRegisterFlags;

const Loopy = enum(u16) {
    coarse_x_scroll = 0x1F,
    coarse_y_scroll = 0x3E0,
    nametable_select = 0xC00,
    fine_y_scroll = 0x7000,
    _,
    pub fn getVal(self: *const @This(), val: @This()) u16 {
        const int_val = @intFromEnum(val);
        return switch (val) {
            .coarse_x_scroll => @intFromEnum(self.*) & int_val,
            .coarse_y_scroll => (@intFromEnum(self.*) & int_val) >> 5,
            .nametable_select => (@intFromEnum(self.*) & int_val) >> 10,
            .fine_y_scroll => (@intFromEnum(self.*) & int_val) >> 12,
            else => @intFromEnum(self.*),
        };
    }
    pub fn get(self: *const @This()) u16 {
        return @intFromEnum(self.*);
    }
    pub fn setVal(self: *@This(), comptime val: @This(), other: switch (val) {
        .coarse_x_scroll, .coarse_y_scroll => u5,
        .nametable_select => u2,
        .fine_y_scroll => u3,
        else => u16,
    }) void {
        const int_val = @intFromEnum(val);
        self.* = @enumFromInt(switch (val) {
            .coarse_x_scroll => (@intFromEnum(self.*) & ~int_val) | other,
            .coarse_y_scroll => (@intFromEnum(self.*) & ~int_val) | (@as(u16, other) << 5),
            .nametable_select => (@intFromEnum(self.*) & ~int_val) | (@as(u16, other) << 10),
            .fine_y_scroll => (@intFromEnum(self.*) & ~int_val) | (@as(u16, other) << 12),
            else => @intFromEnum(self.*),
        });
    }
    pub fn set(self: *@This(), other: u16) void {
        self.* = @enumFromInt(other);
    }
};

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
            if (i == 6 or i == 5) {
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
            // Set the loopy nametable select
            self.tram_addr.setVal(.nametable_select, @intCast(self.ppu_control & (PPUCTRL.base_name_tbl_h.get() | PPUCTRL.base_name_tbl_l.get())));
        },
        // PPU Mask
        1 => {
            self.ppu_mask = data;
        },
        2 => {},
        3 => {},
        4 => {},
        // Scroll register
        5 => {
            if (self.address_latch == 0) {
                self.fine_x = data & 0x07;
                self.tram_addr.setVal(.coarse_x_scroll, @intCast(data >> 3));
                self.address_latch = 1;
            } else {
                self.tram_addr.setVal(.fine_y_scroll, @intCast(data & 0x07));
                self.tram_addr.setVal(.coarse_y_scroll, @intCast(data >> 3));
                self.address_latch = 0;
            }
        },
        // PPU Address
        6 => {
            if (self.address_latch == 0) {
                // Set high byte of address
                self.tram_addr.set(self.tram_addr.get() & 0x00FF | (@as(u16, data) << 8));
                self.address_latch = 1;
            } else {
                // Set low byte of address
                self.tram_addr.set(self.tram_addr.get() & 0xFF00 | data);
                self.ppu_addr = self.tram_addr;
                self.address_latch = 0;
            }
        },
        // PPU Data
        7 => {
            self.ppu_data = data;
            self.memory_write(self.ppu_addr.get(), self.ppu_data);
            // NES autoincrements the address
            self.ppu_addr.set(self.ppu_addr.get() + @as(u16, if (self.ppu_control & PPUCTRL.get(.vram_addr_increment) == 0) 1 else 32));
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
                data = (self.ppu_status & 0xE0) | (self.ppu_data & 0x1F);

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
                self.ppu_data_buffer = self.memory_read(self.ppu_addr.get());

                // Palette reads dont have a 1 cycle delay
                if (self.ppu_addr.get() >= 0x3f00) data = self.ppu_data_buffer;

                // NES autoincrements the address
                self.ppu_addr.set(self.ppu_addr.get() + @as(u16, if (self.ppu_control & PPUCTRL.get(.vram_addr_increment) == 0) 1 else 32));
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
    // Nametable memory
    } else if (addr >= 0x2000 and addr <= 0x2FFF) {
        addr &= 0x0FFF;
        switch (self.nametable_mirroring) {
            .h => {
                if (addr >= 0x0000 and addr <= 0x03FF) return self.name_tables[0][addr & 0x03FF];
                if (addr >= 0x0400 and addr <= 0x07FF) return self.name_tables[0][addr & 0x03FF];
                if (addr >= 0x0800 and addr <= 0x0BFF) return self.name_tables[1][addr & 0x03FF];
                if (addr >= 0x0C00 and addr <= 0x0FFF) return self.name_tables[1][addr & 0x03FF];
            },
            .v => {
                if (addr >= 0x0000 and addr <= 0x03FF) return self.name_tables[0][addr & 0x03FF];
                if (addr >= 0x0400 and addr <= 0x07FF) return self.name_tables[1][addr & 0x03FF];
                if (addr >= 0x0800 and addr <= 0x0BFF) return self.name_tables[0][addr & 0x03FF];
                if (addr >= 0x0C00 and addr <= 0x0FFF) return self.name_tables[1][addr & 0x03FF];
            },
        }
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
    // Name table memory
    } else if (addr >= 0x2000 and addr <= 0x2FFF) {
        addr &= 0x0FFF;
        switch (self.nametable_mirroring) {
            .h => {
                if (addr >= 0x0000 and addr <= 0x03FF) self.name_tables[0][addr & 0x03FF] = data;
                if (addr >= 0x0400 and addr <= 0x07FF) self.name_tables[0][addr & 0x03FF] = data;
                if (addr >= 0x0800 and addr <= 0x0BFF) self.name_tables[1][addr & 0x03FF] = data;
                if (addr >= 0x0C00 and addr <= 0x0FFF) self.name_tables[1][addr & 0x03FF] = data;
            },
            .v => {
                if (addr >= 0x0000 and addr <= 0x03FF) self.name_tables[0][addr & 0x03FF] = data;
                if (addr >= 0x0400 and addr <= 0x07FF) self.name_tables[1][addr & 0x03FF] = data;
                if (addr >= 0x0800 and addr <= 0x0BFF) self.name_tables[0][addr & 0x03FF] = data;
                if (addr >= 0x0C00 and addr <= 0x0FFF) self.name_tables[1][addr & 0x03FF] = data;
            }
        }
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

test "Loopy enum set" {
    var l: Loopy = @enumFromInt(0);
    l.set(0x8000);
    l.setVal(.coarse_y_scroll, 3);
    try std.testing.expectEqual(3, l.getVal(.coarse_y_scroll));
    try std.testing.expectEqual(0x8060, l.get());

    l.set(0xFFF4);
    // Testing flipping 10th bit
    l.set((~l.get() & 0x0400) | (l.get() & ~@as(u16, 0x0400)));
    try std.testing.expectEqual(0xFBF4, l.get());
}