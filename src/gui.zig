const rg = @import("raygui");
const rl = @import("raylib");
const std = @import("std");
const debug = @import("debugger.zig");

const input_buf_size = 128 + 1;

// Width and height of windows
// Order of fields determines order of dragging collision check. MAKE SURE ITS IN SYNC WITH DRAWING CODE
pub const window_bounds = struct {
    pub const cpu_status: rl.Vector2 = .{.y = 128, .x = 376};
    pub const debugger: rl.Vector2 = .{.x = 320, .y = 504};
};

// TODO: Don't allow windows to be dragged off the edge
// For a window to be draggable, it must:
//   - Have decl in window_bounds that is a Vector2 that represents size of window and corresponds to a tag of same name in MenuBarItem
//   - Have a _window_pos struct that is Vector2 in GuiState
//   - Have a _window_active boolean in GuiState
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
            const is_window_active = @field(state, w.name ++ "_window_active");
            const window_anchor = @field(state, w.name ++ "_window_pos");
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
            .none, .file, .memory => {},
            inline else => |t| {
                const window_name = @tagName(t);
                const window_pos = &@field(state, window_name ++ "_window_pos");
                window_pos.* = rl.getMousePosition().subtract(state.currently_dragged_mouse_offset);
            }
        }
    }
}

pub const GuiState = struct {
    // If it's null no window is being dragged
    currently_dragged_window: ?MenuBarItem = null,
    currently_dragged_mouse_offset: rl.Vector2 = .{.x = 0, .y = 0},  // Offset from anchor point to window anchor

    cpu_status_window_pos: rl.Vector2 = .{.x = 100, .y = 100},
    cpu_status_window_active: bool = false,
    cpu_status_cpu_running: bool = false,  // If the cpu is currently paused or not to allow for value editing
    cpu_status_a_register_text: [input_buf_size]u8 = .{0} ** input_buf_size,
    cpu_status_a_register_text_edit: bool = false,
    cpu_status_x_register_text: [input_buf_size]u8 = .{0} ** input_buf_size,
    cpu_status_x_register_text_edit: bool = false,
    cpu_status_y_register_text: [input_buf_size]u8 = .{0} ** input_buf_size,
    cpu_status_y_register_text_edit: bool = false,
    cpu_status_pc_text: [input_buf_size]u8 = .{0} ** input_buf_size,
    cpu_status_pc_text_edit: bool = false,
    cpu_status_ir_text: [3]u8 = .{0} ** 3,
    cpu_status_cc_text: [2]u8 = .{0} ** 2,
    cpu_status_cycles_text: [21]u8 = .{0} ** 21,
    cpu_status_instr_text: [21]u8 = .{0} ** 21,
    cpu_status_n_flag: bool = false,
    cpu_status_v_flag: bool = false,
    cpu_status_one_flag: bool = false,
    cpu_status_b_flag: bool = false,
    cpu_status_d_flag: bool = false,
    cpu_status_i_flag: bool = false,
    cpu_status_z_flag: bool = false,
    cpu_status_c_flag: bool = false,

    debugger_window_pos: rl.Vector2 = .{.x = 300, .y = 400},
    debugger_window_active: bool = false,
    debugger_dissasembly: ?[]debug.InstructionDissasembly = null,  // Only null once at the start of the program
    debugger_dissasembly_regen: bool = false,  // Flag to signal that the debugger dissasembly must be regenerated (free and assign to new result)
    debugger_dissasembly_address: u16 = 0,
    debugger_dissasembly_address_text: [input_buf_size]u8 = .{0} ** input_buf_size,
    debugger_dissasembly_address_text_edit: bool = false,
    debugger_dissasembly_scroll_region_height: f32 = 0,
    debugger_dissasembly_scroll_offset: rl.Vector2 = .{.x = 0, .y = 0},
    debugger_dissasembly_scroll_view: rl.Rectangle = .{.x = 0, .y = 0, .width = 0, .height = 0},
    debugger_dissasembly_text_buffer: std.ArrayList(u8)
};

pub const MenuBarItem = enum {
    none,
    file,
    debugger,
    cpu_status,
    memory
};

pub fn menuBar(state: *GuiState) void {
    _ = rg.guiDummyRec(.{
        .x = 0, .y = 0,
        .width = @floatFromInt(rl.getRenderWidth()),
        .height = 64
    }, "");
    _ = rg.guiButton(.{
        .x = 8, .y = 8,
        .width = 88, .height = 48
    }, "FILE");
    if (rg.guiButton(.{
        .x = 104, .y = 8,
        .width = 88, .height = 48
    }, if (state.debugger_window_active) "> DEBUGGER" else "DEBUGGER") > 0) {
        state.debugger_window_active = !state.debugger_window_active;
        state.debugger_dissasembly_regen = true;
    }
    if (rg.guiButton(.{
        .x = 200, .y = 8,
        .width = 88, .height = 48
    }, if (state.cpu_status_window_active) "> CPU STATUS" else "CPU STATUS") > 0)
        state.cpu_status_window_active = !state.cpu_status_window_active;
    _ = rg.guiButton(.{
        .x = 296, .y = 8,
        .width = 88, .height = 48
    }, "MEMORY");
}

const dissasembly_line_height = 18;
pub fn debugger(state: *GuiState, pos: rl.Vector2, logic_debugger: *debug.Debugger, cpu: anytype, cycles: *usize, alloc: std.mem.Allocator) void {
    const anchor = pos;
    if (state.debugger_window_active) {
        // TODO: verify cpu has debugger attached, if not, then attach

        // TODO: detatch debugger when closing window
        if (rg.guiWindowBox(.{
            .x = anchor.x, .y = anchor.y,
            .width = window_bounds.debugger.x, .height = window_bounds.debugger.y
        }, "Debugger") > 0) state.debugger_window_active = false;

        // Resume code execution button
        if (rg.guiButton(.{
            .x = anchor.x + 8, .y = anchor.y + 32,
            .width = 32, .height = 32
        }, "#131#") > 0) {
            logic_debugger.pause = false;
            state.cpu_status_cpu_running = true;
        }

        // Pause code execution button
        if (rg.guiButton(.{
            .x = anchor.x + 48, .y = anchor.y + 32,
            .width = 32, .height = 32
        }, "#132#") > 0) {
            logic_debugger.pause = true;
            state.cpu_status_cpu_running = false;
        }

        // Step forward 1 instruction
        _ = rg.guiButton(.{
            .x = anchor.x + 8, .y = anchor.y + 72,
            .width = 72, .height = 24
        }, "STEP INSTR");

        // TODO: Replace with call to proper system ticker function
        // Step forward 1 cycle
        if (rg.guiButton(.{
            .x = anchor.x + 8, .y = anchor.y + 104,
            .width = 72, .height = 24
        }, "STEP CYCLE") > 0) {
            if (cpu.tick()) |_| {
                cycles.* += 1;
            } else |_| {}
        }

        // TODO: Draw some colored text below to indicate the execution status

        // Dissasembly start address
        if (rg.guiTextBox(.{
            .x = anchor.x + 8, .y = anchor.y + 440,
            .width = 72, .height = 24
        }, @ptrCast(&state.debugger_dissasembly_address_text), 128,state.debugger_dissasembly_address_text_edit) > 0) {
            state.debugger_dissasembly_address_text_edit = !state.debugger_dissasembly_address_text_edit;
            const text = &state.debugger_dissasembly_address_text;

            // Parse literal and set address
            if (std.fmt.parseInt(u16, text[0..4], 16)) |val| state.debugger_dissasembly_address = val else |_| {}
            @memset(text, 0);
            _ = std.fmt.bufPrint(text, "{X:0>4}", .{state.debugger_dissasembly_address}) catch unreachable;
        }

        // Dissasembly button
        _ = rg.guiButton(.{
            .x = anchor.x + 8, .y = anchor.y + 472,
            .width = 72, .height = 24
        }, "GOTO");

        // Dissasembly view
        _ = rg.guiScrollPanel(.{
            .x = anchor.x + 88, .y = anchor.y + 32,
            .width = 224,
            .height = 464
        }, null, .{
            .x = anchor.x + 88, .y = anchor.y + 32,
            .width = 224, .height = state.debugger_dissasembly_scroll_region_height
        }, &state.debugger_dissasembly_scroll_offset, &state.debugger_dissasembly_scroll_view);
        {
            rl.beginScissorMode(
                @intFromFloat(state.debugger_dissasembly_scroll_view.x),
                @intFromFloat(state.debugger_dissasembly_scroll_view.y),
                @intFromFloat(state.debugger_dissasembly_scroll_view.width),
                @intFromFloat(state.debugger_dissasembly_scroll_view.height)
            );
            defer rl.endScissorMode();

            // Regenerate dissasembly
            if (state.debugger_dissasembly_regen) {
                state.debugger_dissasembly_regen = false;
                if (state.debugger_dissasembly) |d| alloc.free(d);

                // Read reset vector to signify where to start dissasembly
                const reset_vector: u16 = @as(u16, cpu.safeBusReadConst(0xFFFD)) << 8 | cpu.safeBusReadConst(0xFFFC);
                state.debugger_dissasembly = debug.dissasemble(cpu, .from_to, .{.start = reset_vector, .end = reset_vector + 0x0FFF, .alloc = alloc, .on_fail = .ignore}) catch unreachable;

                // Count pixels needed to show all lines + top and bottom margins
                state.debugger_dissasembly_scroll_region_height = @floatFromInt(dissasembly_line_height * state.debugger_dissasembly.?.len + 8 + 8);
            }

            dissasemblyWindow(
                .{.x = anchor.x + 88, .y = anchor.y + 32},
                state.debugger_dissasembly_scroll_offset.y,
                state.debugger_dissasembly.?,
                cpu.program_counter
            );
        }
    }
}

fn dissasemblyWindow(pos: rl.Vector2, scroll: f32, dissasembly: []const debug.InstructionDissasembly, address: u16) void {
    const anchor = pos;
    var buf: [32]u8 = .{0} ** 32;

    // Line from which to start rendering, with 1 line of overdraw
    const start_dissasembly: usize = @divFloor(@abs(@as(i64, @intFromFloat(scroll))), dissasembly_line_height) -| 1;
    const end_dissasembly: usize = if (start_dissasembly + 34 > dissasembly.len - 1) dissasembly.len - 1 else start_dissasembly + 34;

    var pc_line_drawn = false;
    for (dissasembly[start_dissasembly..end_dissasembly], start_dissasembly..) |d, i| {
        const y_pos = @as(f32, @floatFromInt(8 + i * dissasembly_line_height)) + scroll;
        var x_pos: f32 = 8;

        // TODO: Do this check with op code alligned address
        // Draw colored box to indicate current op_code address
        if (d.pc >= address and d.pc < address + d.len and !pc_line_drawn) {
            pc_line_drawn = true;
            rl.drawRectangle(
                @intFromFloat(anchor.x),@intFromFloat(anchor.y + y_pos),
                700, dissasembly_line_height,
                rl.Color.blue
            );
        }

        @memset(&buf, 0);
        _ = std.fmt.bufPrint(&buf, "{X:0>4}", .{d.pc}) catch unreachable;
        drawText(anchor.add(.{.x = x_pos, .y = y_pos}), @ptrCast(&buf));
        x_pos += 32 + 10;

        for (d.op_codes) |op| {
            if (op) |o| {
                @memset(&buf, 0);
                _ = std.fmt.bufPrint(&buf, "{X:0>2}", .{o}) catch unreachable;
                drawText(anchor.add(.{.x = x_pos, .y = y_pos}), @ptrCast(&buf));
            }
            x_pos += 16 + 5;
        }
        x_pos += 5;

        @memset(&buf, 0);
        _ = std.fmt.bufPrint(&buf, "{any}", .{d}) catch unreachable;
        drawText(anchor.add(.{.x = x_pos, .y = y_pos}), @ptrCast(&buf));
    }
}

// Returns if the input box was clicked
fn labeledInput(
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

fn labeledStatus(
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

fn statusFlags(state: *GuiState, pos: rl.Vector2, CPU: type, cpu: *const CPU) void {
    _ = cpu;
    const anchor: rl.Vector2 = pos;
    _ = rg.guiGroupBox(.{
        .x = anchor.x, .y = anchor.y,
        .width = 168, .height = 56
    }, "Status flags");
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 8, .y = anchor.y + 8,
        .width = 16, .height = 16
    }, "N", &state.cpu_status_n_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 40, .y = anchor.y + 8,
        .width = 16, .height = 16
    }, "V", &state.cpu_status_v_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 72, .y = anchor.y + 8,
        .width = 16, .height = 16
    }, "1", &state.cpu_status_one_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 104, .y = anchor.y + 8,
        .width = 16, .height = 16
    }, "B", &state.cpu_status_b_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 8, .y = anchor.y + 32,
        .width = 16, .height = 16
    }, "D", &state.cpu_status_d_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 40, .y = anchor.y + 32,
        .width = 16, .height = 16
    }, "I", &state.cpu_status_i_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 72, .y = anchor.y + 32,
        .width = 16, .height = 16
    }, "Z", &state.cpu_status_z_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 104, .y = anchor.y + 32,
        .width = 16, .height = 16
    }, "C", &state.cpu_status_c_flag);
}

// TODO: Implement the stack inspector
pub fn cpuStatus(state: *GuiState, pos: rl.Vector2, CPU: type, cpu: *const CPU, cycle_count: u64, instr_count: u64) void {
    const anchor: rl.Vector2 = pos;
    if (state.cpu_status_window_active) {
        // Update gui state with cpu values
        if (state.cpu_status_cpu_running) {
            _ = std.fmt.bufPrint(state.cpu_status_a_register_text[0..2], "{X:0>2}", .{cpu.a_register}) catch {};
            _ = std.fmt.bufPrint(state.cpu_status_x_register_text[0..2], "{X:0>2}", .{cpu.x_register}) catch {};
            _ = std.fmt.bufPrint(state.cpu_status_y_register_text[0..2], "{X:0>2}", .{cpu.y_register}) catch {};
            _ = std.fmt.bufPrint(state.cpu_status_pc_text[0..4], "{X:0>4}", .{cpu.program_counter}) catch {};

            state.cpu_status_n_flag = cpu.isFlagSet(.negative);
            state.cpu_status_v_flag = cpu.isFlagSet(.overflow);
            state.cpu_status_b_flag = cpu.isFlagSet(.brk_command);
            state.cpu_status_d_flag = cpu.isFlagSet(.decimal);
            state.cpu_status_i_flag = cpu.isFlagSet(.irq_disable);
            state.cpu_status_z_flag = cpu.isFlagSet(.zero);
            state.cpu_status_c_flag = cpu.isFlagSet(.carry);
        }
        _ = std.fmt.bufPrint(state.cpu_status_ir_text[0..2], "{X:0>2}", .{cpu.instruction_register}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_cc_text[0..1], "{}", .{cpu.current_instruction_cycle}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_cycles_text[0..20], "{}", .{cycle_count}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_instr_text[0..20], "{}", .{instr_count}) catch {};

        // Main window
        if (rg.guiWindowBox(.{
            .x = anchor.x, .y = anchor.y,
            .height = window_bounds.cpu_status.y, .width = window_bounds.cpu_status.x
        }, "CPU Status") > 0) state.cpu_status_window_active = false;

        // A register
        if (labeledInput(
            .{.x = anchor.x + 8, .y = anchor.y + 32},
            16, 32, "a:",
            @ptrCast(&state.cpu_status_a_register_text), state.cpu_status_a_register_text_edit
        )) state.cpu_status_a_register_text_edit = !state.cpu_status_a_register_text_edit;

        // X register
        if (labeledInput(
            .{.x = anchor.x + 64, .y = anchor.y + 32},
            16, 32, "x:",
            @ptrCast(&state.cpu_status_x_register_text), state.cpu_status_x_register_text_edit
        )) state.cpu_status_x_register_text_edit = !state.cpu_status_x_register_text_edit;

        // Y register
        if (labeledInput(
            .{.x = anchor.x + 120, .y = anchor.y + 32},
            16, 32,
            "y:", @ptrCast(&state.cpu_status_y_register_text), state.cpu_status_y_register_text_edit
        )) state.cpu_status_y_register_text_edit = !state.cpu_status_y_register_text_edit;

        // Program counter
        if (labeledInput(
            .{.x = anchor.x + 176, .y = anchor.y + 32},
            24, 40,
            "pc:", @ptrCast(&state.cpu_status_pc_text), state.cpu_status_pc_text_edit
        )) state.cpu_status_pc_text_edit = !state.cpu_status_pc_text_edit;

        // Instruction register (Read only)
        labeledStatus(
            .{.x = anchor.x + 248, .y = anchor.y + 32},
            24, 32,
            "ir:", @ptrCast(&state.cpu_status_ir_text)
        );

        // Current instruction cycle (Read only)
        labeledStatus(
            .{.x = anchor.x + 312, .y = anchor.y + 32},
            24, 32,
            "cc:", @ptrCast(&state.cpu_status_cc_text)
        );

        // Executed cycles (Read only)
        labeledStatus(
            .{.x = anchor.x + 8, .y = anchor.y + 64},
            56, 128,
            "cycles:", @ptrCast(&state.cpu_status_cycles_text)
        );

        // Executed instructions (Read only)
        labeledStatus(
            .{.x = anchor.x + 8, .y = anchor.y + 96},
            56, 128,
            "instr:", @ptrCast(&state.cpu_status_instr_text)
        );

        statusFlags(state, .{.x = anchor.x + 200, .y = anchor.y + 64}, CPU, cpu);
    }
}

fn drawText(pos: rl.Vector2, text: [*:0]const u8) void {
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