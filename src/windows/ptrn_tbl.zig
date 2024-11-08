const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const util = @import("../util.zig");

pub fn bounds(tag: enum {default, scaled, both, scaled_both}) rl.Vector2 {
    return ([_]rl.Vector2{
        .{.x = 320, .y = 272},
        .{.x = 320, .y = 408},
        .{.x = 320, .y = 272},
        .{.x = 568, .y = 408},
    })[@intFromEnum(tag)];
}

// Required for windowing
window_pos: rl.Vector2 = .{.x = 300, .y = 400},
window_active: bool = false,

// Framebuffer to draw pattern table in
// COLORS ARE STORED AS BIG ENDIAN, MUST BE GIVEN AS NATIVE
framebuffers: [2]rl.Image,
fb_textures: [2]rl.Texture,
draw_grid: bool = false,
two_scaling: bool = false,
active_table_display: i32 = 0,

pub fn init(alloc: std.mem.Allocator) !@This() {
    const fb: [2]rl.Image = .{
        .{
            .data = @ptrCast(try alloc.alloc(u32, 128 * 128)),
            .width = 128,
            .height = 128,
            .mipmaps = 1,
            .format = .pixelformat_uncompressed_r8g8b8a8,
        },
        .{
            .data = @ptrCast(try alloc.alloc(u32, 128 * 128)),
            .width = 128,
            .height = 128,
            .mipmaps = 1,
            .format = .pixelformat_uncompressed_r8g8b8a8,
        }
    };
    return .{
        .framebuffers = fb,
        .fb_textures = .{rl.loadTextureFromImage(fb[0]), rl.loadTextureFromImage(fb[1])},
    };
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    for (self.framebuffers, 0..) |_, i| {
        alloc.free(self.getRawFramebuffer(i));
        self.fb_textures[i].unload();
    }
}

// Modifies the bounds of the window
pub fn draw(self: *@This(), w_bounds: *rl.Vector2, sys: *const util.NesSystem) void {
    const anchor = self.window_pos;
    if (self.window_active) {
        // Define new window bounds and new anchor depending on how large
        // the framebuffer is. Determined by state.
        const new_anchor = blk: {
            // base scale with 1 table
            if (!self.two_scaling and self.active_table_display != 2) {
                w_bounds.* = bounds(.default);
                break :blk anchor.add(.{.x = 8, .y = 168});
            // base scale with 2 tables
            } else if (!self.two_scaling and self.active_table_display == 2) {
                w_bounds.* = bounds(.both);
                break :blk anchor.add(.{.x = 8, .y = 168});
            // 2x scale with 1 table
            } else if (self.two_scaling and self.active_table_display != 2){
                w_bounds.* = bounds(.scaled);
                break :blk anchor.add(.{.x = 8, .y = 304});
            // 2x scale with 2 tables
            } else {
                w_bounds.* = bounds(.scaled_both);
                break :blk anchor.add(.{.x = 8, .y = 304});
            }
        };

        // Declare window
        if (rg.guiWindowBox(.{
            .x = anchor.x, .y = anchor.y,
            .width = w_bounds.x, .height = w_bounds.y
        }, "PATTERN TABLE VIEWER") != 0) {
            self.window_active = !self.window_active;
        }

        // Panel around framebuffer
        const panel_size: f32 = if (!self.two_scaling) 136 else 136 * 2;
        _ = rg.guiPanel(.{
            .x = anchor.x + 8, .y = anchor.y + 32,
            .width = panel_size, .height = panel_size,
        }, null);
        // Conditionally draw panel for second table
        if (self.active_table_display == 2) {
            _ = rg.guiPanel(.{
                .x = anchor.x + 16 + panel_size, .y = anchor.y + 32,
                .width = panel_size, .height = panel_size,
            }, null);
        }

        // Grid checkbox
        _ = rg.guiCheckBox(.{
            .x = new_anchor.x, .y = new_anchor.y + 8,
            .width = 24, .height = 24
        }, "SHOW GRID", &self.draw_grid);

        // 2X scaling checkbox
        _ = rg.guiCheckBox(.{
            .x = new_anchor.x, .y = new_anchor.y + 40,
            .width = 24, .height = 24
        }, "2X SCALE", &self.two_scaling);

        // Choose which tbl to display
        _ = rg.guiToggleGroup(.{
            .x = new_anchor.x, .y = new_anchor.y + 72,
            .width = 88, .height = 24
        }, "TBL0;TBL1;BOTH", &self.active_table_display);

        update_framebuffer(self, sys);

        // Draw final framebuffer
        const fb_idx = if (self.active_table_display != 2) self.active_table_display else 0;
        rl.drawTexturePro(self.fb_textures[@intCast(fb_idx)], .{
            .x = 0, .y = 0,
            .width = 128, .height = 128,
        }, .{
            .x = 0, .y = 0,
            .width = panel_size - 8, .height = panel_size - 8,
        },.{.x = -(anchor.x + 12), .y = -(anchor.y + 36)}, 0, rl.Color.white);
        if (self.active_table_display == 2) {
            rl.drawTexturePro(self.fb_textures[1], .{
                .x = 0, .y = 0,
                .width = 128, .height = 128,
            }, .{
                .x = 0, .y = 0,
                .width = panel_size - 8, .height = panel_size - 8,
            },.{.x = -(anchor.x + 20 + panel_size), .y = -(anchor.y + 36)}, 0, rl.Color.white);
        }
    }
}

// - Draws pattern table into cpu framebuffer
// - Updates texture framebuffer
pub fn update_framebuffer(self: *@This(), sys: *const util.NesSystem) void {
    const tmp_color_palette = .{
        std.mem.nativeToBig(u32, 0x000000FF),
        std.mem.nativeToBig(u32, 0xFF0000FF),
        std.mem.nativeToBig(u32, 0x0000FFFF),
        std.mem.nativeToBig(u32, 0xFFFFFFFF),
    };

    // self.framebuffer.clearBackground(rl.Color.pink);
    for (&self.framebuffers, 0..) |*fb, idx| {
        const tbl: []const u8 = &sys.ppu.pattern_tables[idx];
        for (0..@divTrunc(tbl.len, 16)) |i| {
            // Draw to simple 1D buffer
            var decoded: [8 * 8]u32 = .{0} ** (8 * 8);
            @TypeOf(sys.ppu).decodePatternTile(tbl[i * 16..(i + 1) * 16], &tmp_color_palette, &decoded);
            fb.drawImage(.{
                .data = @ptrCast(&decoded),
                .format = .pixelformat_uncompressed_r8g8b8a8,
                .width = 8,
                .height = 8,
                .mipmaps = 1,
            }, .{.x = 0, .y = 0, .width = 8, .height = 8}, .{
                .x = @floatFromInt(@mod(i, 16) * 8),
                .y = @floatFromInt(@divTrunc(i, 16) * 8),
                .width = 8,
                .height = 8,
            }, rl.Color.white);
        }
    }

    for (self.fb_textures, 0..) |tex, i| {
        rl.updateTexture(tex, self.framebuffers[i].data);
    }
}

// Returns slice to raw image data in RGBA 32bit format
pub fn getRawFramebuffer(self: *@This(), idx: usize) []u32 {
    return @as([*]u32, @ptrCast(@alignCast(self.framebuffers[idx].data)))[0..@intCast(self.framebuffers[idx].width * self.framebuffers[idx].height)];
}