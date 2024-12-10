const std = @import("std");
const gui = @import("../gui.zig");
const rl = @import("raylib");
const rg = @import("raygui");
const debug = @import("../debugger.zig");
const util = @import("../util.zig");

// Required for windowing
window_pos: rl.Vector2 = .{.x = 300, .y = 400},
window_active: bool = false,

dissasembly: ?[]debug.InstructionDissasembly = null,  // Only null once at the start of the program
dissasembly_follow: bool = true,  // Controls if dissasembly scroll offset should change to have current instruction visible
dissasembly_regen: bool = false,  // Flag to signal that the debugger dissasembly must be regenerated (free and assign to new result)
dissasembly_address: u16 = 0,
dissasembly_address_text: [gui.input_buf_size]u8 = .{0} ** gui.input_buf_size,
dissasembly_address_text_edit: bool = false,
dissasembly_scroll_region_height: f32 = 0,
dissasembly_scroll_offset: rl.Vector2 = .{.x = 0, .y = 0},
dissasembly_scroll_view: rl.Rectangle = .{.x = 0, .y = 0, .width = 0, .height = 0},
dissasembly_text_buffer: std.ArrayList(u8),

pub fn init(alloc: std.mem.Allocator) @This() {
    return .{
        .dissasembly_text_buffer = std.ArrayList(u8).init(alloc)
    };
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    self.dissasembly_text_buffer.deinit();
    if (self.dissasembly) |p| {
        alloc.free(p);
    }
}

const dissasembly_line_height = 18;
pub fn draw(self: *@This(), cpu_status_state: *@import("cpu_status.zig"), system: *util.NesSystem, alloc: std.mem.Allocator) void {
    const anchor = self.window_pos;
    if (self.window_active) {
        // TODO: verify cpu has debugger attached, if not, then attach

        // TODO: detatch debugger when closing window
        if (rg.guiWindowBox(.{
            .x = anchor.x, .y = anchor.y,
            .width = gui.window_bounds.debugger.x, .height = gui.window_bounds.debugger.y
        }, "Debugger") > 0) self.window_active = false;

        // Resume code execution button
        if (rg.guiButton(.{
            .x = anchor.x + 8, .y = anchor.y + 32,
            .width = 32, .height = 32
        }, "#131#") > 0) {
            cpu_status_state.cpu_running = true;
        }

        // Pause code execution button
        if (rg.guiButton(.{
            .x = anchor.x + 48, .y = anchor.y + 32,
            .width = 32, .height = 32
        }, "#132#") > 0) {
            cpu_status_state.cpu_running = false;
        }

        // Step forward 1 instruction
        if (rg.guiButton(.{
            .x = anchor.x + 8, .y = anchor.y + 72,
            .width = 72, .height = 24
        }, "STEP INSTR") > 0) {
            cpu_status_state.registers_update_flag = true;
            system.running = true;
            system.tickInstruction() catch {
                cpu_status_state.cpu_running = false;
            };
            system.running = false;
            // Scroll to PC + 8 line offset
            if (self.dissasembly_follow) {
                if (getScrollToInstruction(self.dissasembly.?, system.last_instr_address)) |v| {
                    self.dissasembly_scroll_offset.y = @floatFromInt(v + dissasembly_line_height * 8);
                }
            }
        }

        // Step forward 1 cycle
        if (rg.guiButton(.{
            .x = anchor.x + 8, .y = anchor.y + 104,
            .width = 72, .height = 24
        }, "STEP CYCLE") > 0) {
            cpu_status_state.registers_update_flag = true;
            system.running = true;
            system.tick() catch {
                cpu_status_state.cpu_running = false;
            };
            system.running = false;
            // Scroll to PC + 8 line offset
            if (self.dissasembly_follow) {
                if (getScrollToInstruction(self.dissasembly.?, system.last_instr_address)) |v| {
                    self.dissasembly_scroll_offset.y = @floatFromInt(v + dissasembly_line_height * 8);
                }
            }
        }

        // Toggle follow current instruction
        if (rg.guiCheckBox(.{
            .x = anchor.x + 8, .y = anchor.y + 168,
            .width = 24, .height = 24
        }, "FOLLOW", &self.dissasembly_follow) != 0) {
            // Scroll to PC + 8 line offset
            if (self.dissasembly_follow) {
                if (getScrollToInstruction(self.dissasembly.?, system.last_instr_address)) |v| {
                    self.dissasembly_scroll_offset.y = @floatFromInt(v + dissasembly_line_height * 8);
                }
            }
        }

        // TODO: Draw some colored text below to indicate the execution status

        // Dissasembly start address
        if (rg.guiTextBox(.{
            .x = anchor.x + 8, .y = anchor.y + 440,
            .width = 72, .height = 24
        }, @ptrCast(&self.dissasembly_address_text), 128,self.dissasembly_address_text_edit) > 0) {
            self.dissasembly_address_text_edit = !self.dissasembly_address_text_edit;
            const text = &self.dissasembly_address_text;

            // Parse literal and set address
            if (std.fmt.parseInt(u16, text[0..4], 16)) |val| self.dissasembly_address = val else |_| {}
            @memset(text, 0);
            _ = std.fmt.bufPrint(text, "{X:0>4}", .{self.dissasembly_address}) catch unreachable;
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
            .width = 224, .height = self.dissasembly_scroll_region_height
        }, &self.dissasembly_scroll_offset, &self.dissasembly_scroll_view);
        {
            rl.beginScissorMode(
                @intFromFloat(self.dissasembly_scroll_view.x),
                @intFromFloat(self.dissasembly_scroll_view.y),
                @intFromFloat(self.dissasembly_scroll_view.width),
                @intFromFloat(self.dissasembly_scroll_view.height)
            );
            defer rl.endScissorMode();

            // Regenerate dissasembly
            if (self.dissasembly_regen) {
                defer self.dissasembly_regen = false;
                if (self.dissasembly) |d| alloc.free(d);

                // Read reset vector to signify where to start dissasembly
                const reset_vector: u16 = @as(u16, system.cpu.safeBusReadConst(0xFFFD)) << 8 | system.cpu.safeBusReadConst(0xFFFC);
                self.dissasembly = debug.dissasemble(system.cpu, .from_to, .{.start = reset_vector, .end = 0xFFFF, .alloc = alloc, .on_fail = .ignore}) catch unreachable;

                // Count pixels needed to show all lines + top and bottom margins
                self.dissasembly_scroll_region_height = @floatFromInt(dissasembly_line_height * self.dissasembly.?.len + 8 + 8);
            }

            // If cpu is running, scroll to follow current instruction + some padding
            if (cpu_status_state.cpu_running and self.dissasembly_follow) {
                // Linear search dissasembly to find offset
                // If instruction cant be found, dont change scroll
                self.dissasembly_scroll_offset.y = if (getScrollToInstruction(
                    self.dissasembly.?, system.last_instr_address
                )) |v| @floatFromInt(v + dissasembly_line_height * 8) else self.dissasembly_scroll_offset.y;
            }

            dissasemblyWindow(
                .{.x = anchor.x + 88, .y = anchor.y + 32},
                self.dissasembly_scroll_offset.y,
                self.dissasembly.?,
                system.last_instr_address
            );
        }
    }
}

// Address must be opcode aligned
fn getScrollToInstruction(dis: []const debug.InstructionDissasembly, instr_addr: u16) ?i32 {
    for (dis, 0..) |d, i| {
        if (d.pc == instr_addr) {
            return -dissasembly_line_height * @as(i32, @intCast(i));
        }
    }
    return null;
}

// address must be opcode aligned for correct instruction highlight!
fn dissasemblyWindow(pos: rl.Vector2, scroll: f32, dissasembly: []const debug.InstructionDissasembly, address: u16) void {
    const anchor = pos;
    var buf: [32]u8 = .{0} ** 32;

    // Line from which to start rendering, with 1 line of overdraw
    const start_dissasembly: usize = @divTrunc(@abs(@as(i64, @intFromFloat(scroll))), dissasembly_line_height) -| 1;
    const end_dissasembly: usize = if (start_dissasembly + 34 > dissasembly.len - 1) dissasembly.len - 1 else start_dissasembly + 34;

    var pc_line_drawn = false;
    for (dissasembly[start_dissasembly..end_dissasembly], start_dissasembly..) |d, i| {
        const y_pos = @as(f32, @floatFromInt(8 + i * dissasembly_line_height)) + scroll;
        var x_pos: f32 = 8;

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
        gui.drawText(anchor.add(.{.x = x_pos, .y = y_pos}), @ptrCast(&buf));
        x_pos += 32 + 10;

        for (d.op_codes) |op| {
            if (op) |o| {
                @memset(&buf, 0);
                _ = std.fmt.bufPrint(&buf, "{X:0>2}", .{o}) catch unreachable;
                gui.drawText(anchor.add(.{.x = x_pos, .y = y_pos}), @ptrCast(&buf));
            }
            x_pos += 16 + 5;
        }
        x_pos += 5;

        @memset(&buf, 0);
        _ = std.fmt.bufPrint(&buf, "{any}", .{d}) catch unreachable;
        gui.drawText(anchor.add(.{.x = x_pos, .y = y_pos}), @ptrCast(&buf));
    }
}