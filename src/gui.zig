const rg = @import("raygui");
const rl = @import("raylib");
const std = @import("std");
const debug = @import("debugger.zig");
const util = @import("util.zig");
const PPU = @import("ppu.zig");

pub const input_buf_size = 128 + 1;

// Width and height of windows
// Order of fields determines order of dragging collision check. MAKE SURE ITS IN SYNC WITH DRAWING CODE
pub const window_bounds = struct {
    pub const game: rl.Vector2 = .{.x = PPU.frame_buffer_width + 2, .y = PPU.frame_buffer_height + 24 + 1};
    pub const file: rl.Vector2 = .{.x = 264, .y = 240};
    pub const cpu_status: rl.Vector2 = .{.y = 176, .x = 376};
    pub const debugger: rl.Vector2 = .{.x = 320, .y = 504};
    pub var ptrn_tbl: rl.Vector2 = @import("windows/ptrn_tbl.zig").bounds(.default);
};

// TODO: Don't allow windows to be dragged off the edge
// For a window to be draggable, it must:
//   - Have decl in window_bounds that is a Vector2 that represents size of window and corresponds to a tag of same name in MenuBarItem
//   - Have a field of the same name in GuiState
//      - Field's type must have 2 fields:
//      - A "window_pos" struct of type rl.Vector2
//      - A "window_active" boolean
pub fn windowDraggingLogic(state: *GuiState) void {
    // Lock gui when pressing dragging chrod key
    if (rl.isKeyPressed(.key_left_control)) {
        rg.guiLock();
    }
    if (rl.isKeyReleased(.key_left_control)) {
        rg.guiUnlock();
    }
    // Check to start dragging
    if (rl.isKeyDown(.key_left_control) and rl.isMouseButtonPressed(.mouse_button_left)) {
        inline for (@typeInfo(window_bounds).Struct.decls) |w| {  // Check collision with each window
            const is_window_active = @field(state, w.name).window_active;
            const window_anchor = @field(state, w.name).window_pos;
            const window_size = @field(window_bounds, w.name);
            const window_bounds_inner: rl.Rectangle = .{
                .x = window_anchor.x, .y = window_anchor.y,
                .width = window_size.x, .height = window_size.y
            };
            if (is_window_active and rl.checkCollisionPointRec(rl.getMousePosition(), window_bounds_inner)) {
                state.currently_dragged_window = @field(MenuBarItem, w.name);
                state.currently_dragged_mouse_offset = rl.getMousePosition().subtract(window_anchor);
                break;
            }
        }
    }
    // Stop dragging
    if ((rl.isKeyReleased(.key_left_control) or rl.isMouseButtonReleased(.mouse_button_left)) and state.currently_dragged_window != null) {
        state.currently_dragged_window = null;
    }
    // Dragging movement
    if (state.currently_dragged_window) |w| {
        switch (w) {
            .none, .memory => {},
            inline else => |t| {
                const window_name = @tagName(t);
                const window_pos = &@field(state, window_name).window_pos;
                window_pos.* = rl.getMousePosition().subtract(state.currently_dragged_mouse_offset);
            }
        }
    }
}

pub const GuiState = struct {
    // If it's null no window is being dragged
    currently_dragged_window: ?MenuBarItem = null,
    currently_dragged_mouse_offset: rl.Vector2 = .{.x = 0, .y = 0},  // Offset from anchor point to window anchor
    
    file: @import("windows/file.zig") = .{},
    cpu_status: @import("windows/cpu_status.zig") = .{},
    debugger: @import("windows/debugger.zig"),
    ptrn_tbl: @import("windows/ptrn_tbl.zig"),
    game: @import("windows/game.zig"),

    pub fn init(alloc: std.mem.Allocator) !@This() {
        return .{
            .debugger = @import("windows/debugger.zig").init(alloc),
            .ptrn_tbl = try @import("windows/ptrn_tbl.zig").init(alloc),
            .game = try @import("windows/game.zig").init(alloc),
        };
    }

    // Attempts to clear all used heap from this allocator
    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.debugger.deinit(alloc);
        self.ptrn_tbl.deinit(alloc);
        self.game.deinit(alloc);
    }
};

pub const MenuBarItem = enum {
    none,
    file,
    game,
    debugger,
    cpu_status,
    ptrn_tbl,
    memory,
};

pub fn menuBar(state: *GuiState) void {
    _ = rg.guiDummyRec(.{
        .x = 0, .y = 0,
        .width = @floatFromInt(rl.getRenderWidth()),
        .height = 64
    }, "");
    if (rg.guiButton(.{
        .x = 8, .y = 8,
        .width = 88, .height = 48
    }, if (state.file.window_active) "> FILE" else "FILE") > 0) {
        state.file.window_active = !state.file.window_active;
    }
    if (rg.guiButton(.{
        .x = 104, .y = 8,
        .width = 88, .height = 48
    }, if (state.game.window_active) "> GAME" else "GAME") > 0) {
        state.game.window_active = !state.game.window_active;
    }
    if (rg.guiButton(.{
        .x = 200, .y = 8,
        .width = 88, .height = 48
    }, if (state.debugger.window_active) "> DEBUGGER" else "DEBUGGER") > 0) {
        state.debugger.window_active = !state.debugger.window_active;
        state.debugger.dissasembly_regen = true;
    }
    if (rg.guiButton(.{
        .x = 296, .y = 8,
        .width = 88, .height = 48
    }, if (state.cpu_status.window_active) "> CPU STATUS" else "CPU STATUS") > 0) {
        state.cpu_status.window_active = !state.cpu_status.window_active;
        state.cpu_status.registers_update_flag = true;
    }
    if (rg.guiButton(.{
        .x = 392, .y = 8,
        .width = 88, .height = 48
    }, if (state.ptrn_tbl.window_active) "> PTRN TBL" else "PTRN TBL") > 0) {
        state.ptrn_tbl.window_active = !state.ptrn_tbl.window_active;
    }
    _ = rg.guiButton(.{
        .x = 488, .y = 8,
        .width = 88, .height = 48
    }, "MEMORY");
}

// Returns if the input box was clicked
pub fn labeledInput(
    pos: rl.Vector2,
    label_width: i32,
    input_width: i32,
    label: []const u8,
    text: [*:0]u8,
    can_edit: bool
) bool {
    _ = rg.guiLabel(.{
        .x = pos.x, .y = pos.y,
        .width = @floatFromInt(label_width), .height = 24
    }, @ptrCast(label));
    return rg.guiTextBox(.{
        .x = pos.x + @as(f32, @floatFromInt(label_width)), .y = pos.y,
        .width = @floatFromInt(input_width), .height = 24
    }, text, 128, can_edit) > 0;
}

pub fn labeledStatus(
    pos: rl.Vector2,
    label_width: i32,
    status_width: i32,
    label: []const u8,
    status: []const u8
) void {
    _ = rg.guiLabel(.{
        .x = pos.x, .y = pos.y,
        .width = @floatFromInt(label_width), .height = 24
    }, @ptrCast(label));
    _ = rg.guiStatusBar(.{
        .x = pos.x + @as(f32, @floatFromInt(label_width)), .y = pos.y,
        .width = @floatFromInt(status_width), .height = 24
    }, @ptrCast(status));
}

pub fn drawText(pos: rl.Vector2, text: [*:0]const u8) void {
    const color: u32 = @bitCast(rg.guiGetStyle(.default, @intFromEnum(rg.GuiControlProperty.text_color_normal)));
    const font_size = rg.guiGetStyle(.default, @intFromEnum(rg.GuiDefaultProperty.text_size));
    const font_spacing = rg.guiGetStyle(.default, @intFromEnum(rg.GuiDefaultProperty.text_spacing));
    rl.drawTextEx(
        rg.guiGetFont(),
        text,
        pos, @floatFromInt(font_size),
        @floatFromInt(font_spacing), rl.getColor(color)
    );
}