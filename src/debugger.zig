// PLAN
// Debugger will hold a reference to a bus and a cpu
// It will tick the cpu and check against a list of breakpoints

// The dissasembly will be stored as a list of instructions in a different
// format.
// Opcodes in 6502.zig will contain data on the base pneumonic and addressing mode

const proc = @import("6502.zig");
const std = @import("std");
const builtin = @import("builtin");

const DissasemblyError = error {
    invalid_opcode
};

const DissassemblyOptionsTag = enum {
    current_instruction,
    single_instruction,
    slice,
    from_to
};

const DissassemblyOptions = union(DissassemblyOptionsTag) {
    current_instruction: struct {},
    single_instruction: struct {address: u16},
    slice: struct {memory: []const u8},
    from_to: struct {
        start: u16,
        end: u16
    }
};

pub fn dissasemble(cpu: anytype, comptime opt_kind: DissassemblyOptionsTag, opt: anytype) switch (opt_kind) {
    .current_instruction, .single_instruction => DissasemblyError!InstructionDissasembly,
    else => DissasemblyError![]InstructionDissasembly
} {
    const inner_opt = @unionInit(DissassemblyOptions, @tagName(opt_kind), opt);

    switch (inner_opt) {
        .current_instruction => {
            const pc = cpu.program_counter;
            const op_c = cpu.safeBusRead(pc);
            const meta = proc.instr.getMetadata(op_c) orelse return DissasemblyError.invalid_opcode;
            const dis: InstructionDissasembly = .{
                .pc = pc,
                .len = meta.len,
                .cycles = meta.cycles,
                .op_codes = [_]?u8{
                    op_c,
                    if (meta.len > 1) cpu.safeBusRead(pc +% 1) else null,
                    if (meta.len > 2) cpu.safeBusRead(pc +% 2) else null
                },
                .addressing = meta.addressing,
                .value_at_address = null
            };
            return dis;
        },
        else => unreachable
    }
}

const InstructionDissasembly = struct {
    pc: u16,
    len: u2,
    op_codes: [3]?u8,
    cycles: u3,
    addressing: proc.AddressingMode,
    value_at_address: ?u8,  // Holds value at address of operand

    // 6502 assembly format
    pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {

    }
};