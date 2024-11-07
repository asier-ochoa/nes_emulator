const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

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
framebuffer: rl.Image,
draw_grid: bool = false,
two_scaling: bool = false,
active_table_display: i32 = 0,

pub fn init(alloc: std.mem.Allocator) !@This() {
    const buffer = try alloc.alloc(u24, 128 * 128);
    return .{
        .framebuffer = .{
            .data = @ptrCast(buffer),
            .width = 128,
            .height = 128,
            .mipmaps = 1,
            .format = .pixelformat_uncompressed_r8g8b8,
        }
    };
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.free(self.getRawFramebuffer());
}

// Modifies the bounds of the window
pub fn draw(self: *@This(), w_bounds: *rl.Vector2) void {
    const anchor = self.window_pos;
    if (self.window_active) {
        // Define new window bounds and new anchor depending on how large
        // the framebuffer is. Determined by state.
        // TODO: CHANGE THESE VALUES
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
    }
}

// Returns slice to raw image data in RGB 24bit format
pub fn getRawFramebuffer(self: *@This()) []u24 {
    return @as([*]u24, @ptrCast(@alignCast(self.framebuffer.data)))[0..@intCast(self.framebuffer.width * self.framebuffer.height)];
}