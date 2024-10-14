const rg = @import("raygui");
const rl = @import("raylib");
const std = @import("std");
const debug = @import("debugger.zig");

const input_buf_size = 128 + 1;

pub const GuiState = struct {
    cpu_status_cpu_running: bool = false,  // If the cpu is currently paused or not to allow for value editing
    cpu_status_window_active: bool = false,
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

    debugger_window_active: bool = false,
    debugger_dissasembly_scroll_offset: rl.Vector2 = .{.x = 0, .y = 0},
    debugger_dissasembly_bounds_offset: rl.Vector2 = .{.x = 0, .y = 0},
    debugger_dissasembly_scroll_view: rl.Rectangle = .{.x = 0, .y = 0, .width = 0, .height = 0},
};

const MenuBarItem = enum {
    none,
    file,
    debugger,
    cpu_state,
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
    }, if (state.debugger_window_active) "> DEBUGGER" else "DEBUGGER") > 0)
        state.debugger_window_active = !state.debugger_window_active;
    if (rg.guiButton(.{
        .x = 200, .y = 8,
        .width = 88, .height = 48
    }, if (state.cpu_status_window_active) "> CPU STATE" else "CPU STATE") > 0)
        state.cpu_status_window_active = !state.cpu_status_window_active;
    _ = rg.guiButton(.{
        .x = 296, .y = 8,
        .width = 88, .height = 48
    }, "MEMORY");
}

pub fn debugger(state: *GuiState, pos: rl.Vector2, logic_debugger: *debug.Debugger) void {
    const anchor = pos;
    if (state.debugger_window_active) {
        // TODO: verify cpu has debugger attached, if not, then attach

        // TODO: detatch debugger when closing window
        if (rg.guiWindowBox(.{
            .x = anchor.x, .y = anchor.y,
            .width = 320, .height = 312
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

        // Step forwar 1 cycle
        _ = rg.guiButton(.{
            .x = anchor.x + 8, .y = anchor.y + 104,
            .width = 72, .height = 24
        }, "STEP CYCLE");

        // TODO: Draw some colored text below to indicate the execution status

        // Dissasembly view
        _ = rg.guiScrollPanel(.{
            .x = anchor.x + 88, .y = anchor.y + 32,
            .width = 200 - state.debugger_dissasembly_bounds_offset.x,
            .height = 272 - state.debugger_dissasembly_bounds_offset.y
        }, null, .{
            .x = anchor.x + 88, .y = anchor.y + 32,
            .width = 200, .height = 272
        }, &state.debugger_dissasembly_scroll_offset, &state.debugger_dissasembly_scroll_view);
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
            .height = 128, .width = 376
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