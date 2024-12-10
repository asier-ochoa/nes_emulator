const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const PPU = @import("../ppu.zig");
const gui = @import("../gui.zig");
const util = @import("../util.zig");

// Required for windowing
window_pos: rl.Vector2 = .{.x = 0, .y = 200},
window_active: bool = false,

framebuffer: rl.Image,
fb_texture: rl.Texture,

pub fn init(alloc: std.mem.Allocator) !@This() {
    const raw_pixel_data = try alloc.alloc(u32, PPU.frame_buffer_width * PPU.frame_buffer_height);
    // Fill with black
    @memset(raw_pixel_data, std.mem.bigToNative(u32, 0xFF0000FF));
    const framebuffer: rl.Image = .{
        .data = @ptrCast(raw_pixel_data),
        .format = .pixelformat_uncompressed_r8g8b8a8,
        .mipmaps = 1,
        .width = PPU.frame_buffer_width,
        .height = PPU.frame_buffer_height,
    };
    return .{
        .framebuffer = framebuffer,
        .fb_texture = rl.loadTextureFromImage(framebuffer),
    };
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.free(self.getRawFramebuffer());
    self.fb_texture.unload();
}

pub fn draw(self: *@This(), sys: *const util.NesSystem) void {
    const anchor = self.window_pos;
    // _ = sys;
    if (self.window_active) {
        updateCpuFramebuffer(&sys.ppu.frame_buffer, self.getRawFramebuffer());
        // Update gpu framebuffer
        rl.updateTexture(self.fb_texture, self.framebuffer.data);

        if (rg.guiWindowBox(.{
            .x = anchor.x, .y = anchor.y,
            .width = gui.window_bounds.game.x, .height = gui.window_bounds.game.y
        }, "Game") > 0) self.window_active = false;

        rl.drawTexture(self.fb_texture, @intFromFloat(anchor.x + 1), @intFromFloat(anchor.y + 24), rl.Color.white);
    }
}

pub fn updateCpuFramebuffer(src: []const u32, dest: []u32) void {
    for (src, 0..) |s, i| {
        dest[i] = std.mem.bigToNative(u32, s);
    }
}

pub fn getRawFramebuffer(self: *@This()) []u32 {
    return @as([*]u32, @ptrCast(@alignCast(self.framebuffer.data)))[0..@intCast(self.framebuffer.width * self.framebuffer.height)];
}