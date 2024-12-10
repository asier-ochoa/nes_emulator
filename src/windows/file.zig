const rl = @import("raylib");
const rg = @import("raygui");
const gui = @import("../gui.zig");
const nfd = @import("nfd");
const std = @import("std");
const util = @import("../util.zig");
const loader = @import("../rom_loader.zig");
const debugger = @import("./debugger.zig");

// Required for windowing
window_pos: rl.Vector2 = .{.x = 800, .y = 300},
window_active: bool = false,

status_text_buffer: [512]u8 = .{0} ** 512,

pub fn draw(self: *@This(), sys: *util.NesSystem, debug_state: *debugger) void {
    const anchor = self.window_pos;
    if (self.window_active) {
        if (rg.guiWindowBox(.{
            .x = anchor.x, .y = anchor.y,
            .width = gui.window_bounds.file.x, .height = gui.window_bounds.file.y
        }, "File") > 0) self.window_active = false;

        // File select button
        if (rg.guiButton(.{
            .x = anchor.x + 8, .y = anchor.y + 32,
            .width = 248, .height = 136,
        }, "") > 0) {
            @memset(&self.status_text_buffer, 0);
            const file_path = nfd.openFileDialog(null, null) catch blk: {
                std.mem.copyForwards(u8, &self.status_text_buffer, "File picker dialog error");
                break :blk null;
            };
            if (file_path) |f| {
                defer nfd.freePath(@ptrCast(f));
                std.debug.print("Attempting to open rom: {s}\n", .{f});
                open_rom_file(f, sys, &debug_state.dissasembly_regen) catch |e| {
                    switch (e) {
                        inline else => |err| std.mem.copyForwards(u8, &self.status_text_buffer, "Error: " ++ @errorName(err)),
                    }
                };
            }
        }

        // Help text
        _ = rg.guiLabel(.{
            .x = anchor.x + 72, .y = anchor.y + 72,
            .width = 136, .height = 24,
        }, "Drag and drop a rom");
        _ = rg.guiLabel(.{
            .x = anchor.x + 64, .y = anchor.y + 96,
            .width = 160, .height = 24,
        }, "Or click here to browse");

        // Rom loading status
        _ = rg.guiGroupBox(.{
            .x = anchor.x + 8, .y = anchor.y + 176,
            .width = 248, .height = 56,
        }, "Status");
        _ = rg.guiLabel(.{
            .x = anchor.x + 16, .y = anchor.y + 184,
            .width = 232, .height = 40,
        }, @ptrCast(&self.status_text_buffer));
    }
}

fn open_rom_file(path: []const u8, sys: *util.NesSystem, dissasembly_regen: *bool) (std.fs.File.OpenError || loader.INesError)!void {
    var file_buffer: [512_000]u8 = .{0} ** 512_000;
    const f = try std.fs.openFileAbsolute(path, .{});
    defer f.close();
    if ((f.metadata() catch unreachable).size() >= file_buffer.len) return loader.INesError.FileBufferOverflow;
    _ = f.readAll(&file_buffer) catch return loader.INesError.FileBufferOverflow;
    try loader.load_ines_into_bus(file_buffer[0..(f.metadata() catch unreachable).size()], sys);
    // reset system when loading rom
    // TODO: Also reset ppu
    sys.cpu = @TypeOf(sys.cpu).init(sys.bus);
    @memset(&sys.bus.memory_map.@"0000-07FF", 0);
    sys.cpu.reset_latch = true;
    dissasembly_regen.* = true;
}
