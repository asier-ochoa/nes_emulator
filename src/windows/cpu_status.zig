const gui = @import("../gui.zig");
const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");

// Required for windowing
window_pos: rl.Vector2 = .{.x = 100, .y = 100},
window_active: bool = false,

cpu_running: bool = false,  // If the cpu is currently paused or not to allow for value editing
registers_update_flag: bool = true,  // Triggers an update of the register text values, starts true to populate on initial load
a_register_text: [gui.input_buf_size]u8 = .{0} ** gui.input_buf_size,
a_register_text_edit: bool = false,
x_register_text: [gui.input_buf_size]u8 = .{0} ** gui.input_buf_size,
x_register_text_edit: bool = false,
y_register_text: [gui.input_buf_size]u8 = .{0} ** gui.input_buf_size,
y_register_text_edit: bool = false,
pc_text: [gui.input_buf_size]u8 = .{0} ** gui.input_buf_size,
pc_text_edit: bool = false,
ir_text: [3]u8 = .{0} ** 3,
cc_text: [2]u8 = .{0} ** 2,
cycles_text: [21]u8 = .{0} ** 21,
instr_text: [21]u8 = .{0} ** 21,
n_flag: bool = false,
v_flag: bool = false,
one_flag: bool = false,
b_flag: bool = false,
d_flag: bool = false,
i_flag: bool = false,
z_flag: bool = false,
c_flag: bool = false,

// TODO: Implement the stack inspector
pub fn draw(self: *@This(), CPU: type, cpu: *const CPU, cycle_count: u64, instr_count: u64) void {
    const anchor: rl.Vector2 = self.window_pos;
    if (self.window_active) {
        // Update gui state with cpu values
        if (self.cpu_running or self.registers_update_flag) {
            defer self.registers_update_flag = false;
            @memset(&self.a_register_text, 0);
            @memset(&self.x_register_text, 0);
            @memset(&self.y_register_text, 0);
            @memset(&self.pc_text, 0);
            _ = std.fmt.bufPrint(self.a_register_text[0..2], "{X:0>2}", .{cpu.a_register}) catch {};
            _ = std.fmt.bufPrint(self.x_register_text[0..2], "{X:0>2}", .{cpu.x_register}) catch {};
            _ = std.fmt.bufPrint(self.y_register_text[0..2], "{X:0>2}", .{cpu.y_register}) catch {};
            _ = std.fmt.bufPrint(self.pc_text[0..4], "{X:0>4}", .{cpu.program_counter}) catch {};

            self.n_flag = cpu.isFlagSet(.negative);
            self.v_flag = cpu.isFlagSet(.overflow);
            self.b_flag = cpu.isFlagSet(.brk_command);
            self.d_flag = cpu.isFlagSet(.decimal);
            self.i_flag = cpu.isFlagSet(.irq_disable);
            self.z_flag = cpu.isFlagSet(.zero);
            self.c_flag = cpu.isFlagSet(.carry);
        }
        _ = std.fmt.bufPrint(self.ir_text[0..2], "{X:0>2}", .{cpu.instruction_register}) catch {};
        _ = std.fmt.bufPrint(self.cc_text[0..1], "{}", .{cpu.current_instruction_cycle}) catch {};
        _ = std.fmt.bufPrint(self.cycles_text[0..20], "{}", .{cycle_count}) catch {};
        _ = std.fmt.bufPrint(self.instr_text[0..20], "{}", .{instr_count}) catch {};

        // Main window
        if (rg.guiWindowBox(.{
            .x = anchor.x, .y = anchor.y,
            .height = gui.window_bounds.cpu_status.y, .width = gui.window_bounds.cpu_status.x
        }, "CPU Status") > 0) {
            self.registers_update_flag = true;
            self.window_active = false;
        }

        // A register
        if (gui.labeledInput(
            .{.x = anchor.x + 8, .y = anchor.y + 32},
            16, 32, "a:",
            @ptrCast(&self.a_register_text), self.a_register_text_edit
        )) self.a_register_text_edit = !self.a_register_text_edit;

        // X register
        if (gui.labeledInput(
            .{.x = anchor.x + 64, .y = anchor.y + 32},
            16, 32, "x:",
            @ptrCast(&self.x_register_text), self.x_register_text_edit
        )) self.x_register_text_edit = !self.x_register_text_edit;

        // Y register
        if (gui.labeledInput(
            .{.x = anchor.x + 120, .y = anchor.y + 32},
            16, 32,
            "y:", @ptrCast(&self.y_register_text), self.y_register_text_edit
        )) self.y_register_text_edit = !self.y_register_text_edit;

        // Program counter
        if (gui.labeledInput(
            .{.x = anchor.x + 176, .y = anchor.y + 32},
            24, 40,
            "pc:", @ptrCast(&self.pc_text), self.pc_text_edit
        )) self.pc_text_edit = !self.pc_text_edit;

        // Instruction register (Read only)
        gui.labeledStatus(
            .{.x = anchor.x + 248, .y = anchor.y + 32},
            24, 32,
            "ir:", @ptrCast(&self.ir_text)
        );

        // Current instruction cycle (Read only)
        gui.labeledStatus(
            .{.x = anchor.x + 312, .y = anchor.y + 32},
            24, 32,
            "cc:", @ptrCast(&self.cc_text)
        );

        // Executed cycles (Read only)
        gui.labeledStatus(
            .{.x = anchor.x + 8, .y = anchor.y + 64},
            56, 128,
            "cycles:", @ptrCast(&self.cycles_text)
        );

        // Executed instructions (Read only)
        gui.labeledStatus(
            .{.x = anchor.x + 8, .y = anchor.y + 96},
            56, 128,
            "instr:", @ptrCast(&self.instr_text)
        );

        self.statusFlags(.{.x = anchor.x + 200, .y = anchor.y + 64}, CPU, cpu);
    }
}

fn statusFlags(self: *@This(), pos: rl.Vector2, CPU: type, cpu: *const CPU) void {
    _ = cpu;
    const anchor: rl.Vector2 = pos;
    _ = rg.guiGroupBox(.{
        .x = anchor.x, .y = anchor.y,
        .width = 168, .height = 56
    }, "Status flags");
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 8, .y = anchor.y + 8,
        .width = 16, .height = 16
    }, "N", &self.n_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 40, .y = anchor.y + 8,
        .width = 16, .height = 16
    }, "V", &self.v_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 72, .y = anchor.y + 8,
        .width = 16, .height = 16
    }, "1", &self.one_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 104, .y = anchor.y + 8,
        .width = 16, .height = 16
    }, "B", &self.b_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 8, .y = anchor.y + 32,
        .width = 16, .height = 16
    }, "D", &self.d_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 40, .y = anchor.y + 32,
        .width = 16, .height = 16
    }, "I", &self.i_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 72, .y = anchor.y + 32,
        .width = 16, .height = 16
    }, "Z", &self.z_flag);
    _ = rg.guiCheckBox(.{
        .x = anchor.x + 104, .y = anchor.y + 32,
        .width = 16, .height = 16
    }, "C", &self.c_flag);
}