const rg = @import("raygui");
const rl = @import("raylib");
const std = @import("std");

pub const GuiState = struct {
    cpu_status_cpu_running: bool = true,  // If the cpu is currently paused or not to allow for value editing
    cpu_status_window_active: bool = true,
    cpu_status_a_register_text: [128]u8 = .{0} ** 128,
    cpu_status_a_register_text_edit: bool = false,
    cpu_status_x_register_text: [128]u8 = .{0} ** 128,
    cpu_status_x_register_text_edit: bool = false,
    cpu_status_y_register_text: [128]u8 = .{0} ** 128,
    cpu_status_y_register_text_edit: bool = false,
    cpu_status_pc_text: [128]u8 = .{0} ** 128,
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
    cpu_status_c_flag: bool = false
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
    _ = rg.guiButton(.{
        .x = 104, .y = 8,
        .width = 88, .height = 48
    }, "DEBUGGER");
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

pub fn cpuStatus(state: *GuiState, pos: rl.Vector2, CPU: type, cpu: *const CPU, cycle_count: u64, instr_count: u64) void {
    const anchor: rl.Vector2 = pos;
    if (state.cpu_status_window_active) {
        // Update gui state with cpu values
        _ = std.fmt.bufPrint(state.cpu_status_a_register_text[0..2], "{X:0>2}", .{cpu.a_register}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_x_register_text[0..2], "{X:0>2}", .{cpu.x_register}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_y_register_text[0..2], "{X:0>2}", .{cpu.y_register}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_pc_text[0..4], "{X:0>4}", .{cpu.program_counter}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_ir_text[0..2], "{X:0>2}", .{cpu.instruction_register}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_cc_text[0..1], "{}", .{cpu.current_instruction_cycle}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_cycles_text[0..20], "{}", .{cycle_count}) catch {};
        _ = std.fmt.bufPrint(state.cpu_status_instr_text[0..20], "{}", .{instr_count}) catch {};

        if (state.cpu_status_cpu_running) {
            state.cpu_status_n_flag = cpu.isFlagSet(.negative);
            state.cpu_status_v_flag = cpu.isFlagSet(.overflow);
            state.cpu_status_b_flag = cpu.isFlagSet(.brk_command);
            state.cpu_status_d_flag = cpu.isFlagSet(.decimal);
            state.cpu_status_i_flag = cpu.isFlagSet(.irq_disable);
            state.cpu_status_z_flag = cpu.isFlagSet(.zero);
            state.cpu_status_c_flag = cpu.isFlagSet(.carry);
        }

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