// PLAN
// Debugger will hold a reference to a bus and a cpu
// It will tick the cpu and check against a list of breakpoints

// The dissasembly will be stored as a list of instructions in a different
// format.
// Opcodes in 6502.zig will contain data on the base pneumonic and addressing mode

const proc = @import("6502.zig");

pub fn dissasemble_from(bus: anytype, cpu: *const proc.CPU(@TypeOf(bus))) void {
    _ = cpu;
}

const InstructionDissasembly = struct {
    len: u2,
    op_codes: [3]?u8,
    cycles: u3,
    addressing: proc.AddressingMode,
    value_at_address: ?u8  // Holds value at address of operand
};