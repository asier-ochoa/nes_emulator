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
    // Dissasembles instruction at PC.
    // Records partial CPU state, allowing the dissasembly to contain
    // values at addresses
    current_instruction,
    // Dissassembles single instruction.
    single_instruction,
    // Dissasembles an arbitrary slice.
    // CPU is not required. Requires memory allocator.
    slice,
    // Dissasembles range of memory in CPU.
    // Requires memory allocator.
    from_to
};

const DissassemblyOptions = union(DissassemblyOptionsTag) {
    current_instruction: struct {record_state: bool = true},
    single_instruction: struct {address: u16},
    slice: struct {memory: []const u8, alloc: *std.mem.Allocator},
    from_to: struct {
        start: u16,
        end: u16,
        alloc: *std.mem.Allocator
    }
};

// TODO: Find a mechanism such that bus reads dont trigger side effects (cpu.safeBusRead() triggers side effects)
// IDEA: Have a special "minimalDissasembly" type that only holds the length and cycles of an instruction, this is to
// help a future "stepping" function for the debugger. I could also implement stepping by checking for cpu.endInstruction()
pub fn dissasemble(cpu: anytype, comptime opt_kind: DissassemblyOptionsTag, opt: anytype) switch (opt_kind) {
    .current_instruction, .single_instruction => DissasemblyError!InstructionDissasembly,
    else => DissasemblyError![]InstructionDissasembly
} {
    const inner_opt = @unionInit(DissassemblyOptions, @tagName(opt_kind), opt);

    switch (inner_opt) {
        .current_instruction, .single_instruction => {
            const pc = if (inner_opt == .current_instruction) cpu.program_counter else opt.address;
            const op_c = cpu.safeBusRead(pc);

            const meta = proc.instr.getMetadata(op_c) orelse return DissasemblyError.invalid_opcode;
            const operands = [_]?u8{
                op_c,
                if (meta.len > 1) cpu.safeBusRead(pc +% 1) else null,
                if (meta.len > 2) cpu.safeBusRead(pc +% 2) else null
            };
            var dis: InstructionDissasembly = .{
                .pc = pc,
                .len = meta.len,
                .pneumonic = meta.pneumonic,
                .cycles = meta.cycles,
                .op_codes = operands,
                .addressing = meta.addressing,
                .value_at_address = if (inner_opt == .current_instruction and inner_opt.current_instruction.record_state) switch (meta.addressing) {
                    .Absolute => if (operands[0].? != proc.instr.JSRabs.op and operands[0].? != proc.instr.JMPabs.op)
                        cpu.safeBusRead(@as(u16, operands[2].?) << 8 | operands[1].?)
                        else null
                    ,
                    .AbsoluteX => cpu.safeBusRead((@as(u16, operands[2].?) << 8 | operands[1].?) +% cpu.x_register),
                    .AbsoluteY => cpu.safeBusRead((@as(u16, operands[2].?) << 8 | operands[1].?) +% cpu.y_register),
                    .ZeroPage => cpu.safeBusRead(operands[1].?),
                    .ZeroPageX => cpu.safeBusRead(operands[1].? +% cpu.x_register),
                    .ZeroPageY => cpu.safeBusRead(operands[1].? +% cpu.y_register),
                    // Unfinished TODO: Store the vector in addition to the final address
                    .Indirect => blk: {
                        const vector_address = @as(u16, operands[2].?) << 8 | operands[1].?;
                        break :blk (@as(u16, cpu.safeBusRead(vector_address +% 1)) << 8) | cpu.safeBusRead(vector_address);
                    },
                    .Relative => if (operands[1].? >> 7 > 0) pc + meta.len -% (operands[1].? & 0x7F) else pc + meta.len +% (operands[1].? & 0x7F),
                    else => null
                } else null
            };
            if (inner_opt == .current_instruction and inner_opt.current_instruction.record_state) {
                switch (meta.addressing) {
                    .AbsoluteX, .ZeroPageX, .IndirectX => dis.x_value = cpu.x_register,
                    .AbsoluteY, .ZeroPageY, .IndirectY => dis.y_value = cpu.y_register,
                    else => {}
                }
                switch (meta.addressing) {
                    .IndirectX => {
                        const vector_address = operands[1].? +% cpu.x_register;
                        dis.vector = @as(u16, cpu.safeBusRead(vector_address +% 1)) << 8 | cpu.safeBusRead(vector_address);
                        dis.value_at_address = cpu.safeBusRead(dis.vector.?);
                    },
                    .IndirectY => {
                        dis.vector = @as(u16, cpu.safeBusRead(operands[1].? +% 1)) << 8 | cpu.safeBusRead(operands[1].?);
                        dis.value_at_address = cpu.safeBusRead(dis.vector.?) +% cpu.y_register;
                    },
                    else => {}
                }
            }
            return dis;
        },
        else => unreachable
    }
}

const InstructionDissasembly = struct {
    pc: u16,
    len: u2,
    pneumonic: []const u8,
    op_codes: [3]?u8,
    cycles: u3,
    addressing: proc.AddressingMode,
    // Holds value at address of operand, being present depends on addressing mode and
    // which option is used to generate dissasembly
    value_at_address: ?u16,
    x_value: ?u8 = null,  // Recorded only for x indexed addressing modes
    y_value: ?u8 = null,  // Recorded only for y indexed addressing modes
    vector: ?u16 = null,  // Recorded only indirect addressing modes

    // 6502 assembly format
    // Formatted in HHLL
    // Everything is in HEX
    // Relative jumps are translated to absolute if value_at_address is present
    pub fn format(self: @This(), comptime _: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        // Buffer to allow for counting bytes
        var buf = [_]u8{0} ** 32;
        var count: usize = 0;

        // Write pneumonic. |LDA|
        count += try writer.write(self.pneumonic);

        // Write addressing mode symbol |LDA $|
        switch (self.addressing) {
            .Accumulator => count += try writer.write(" A"),
            .Absolute, .AbsoluteX, .AbsoluteY,
            .ZeroPage, .ZeroPageX, .ZeroPageY,
            .Relative => count += try writer.write(" $"),
            .Immediate => count += try writer.write(" #$"),
            .Indirect, .IndirectX, .IndirectY => count += try writer.write(" ($"),
            else => {}
        }

        // Write operand |LDA ($12AE| in Big endian
        switch (self.addressing) {
            .Absolute, .AbsoluteX, .AbsoluteY,
            .Indirect => count += try writer.write(try std.fmt.bufPrint(&buf, "{X:0>4}", .{(@as(u16, self.op_codes[2].?) << 8) | self.op_codes[1].?})),
            .Immediate, .IndirectX, .IndirectY,
            .ZeroPage, .ZeroPageX,
            .ZeroPageY => count += try writer.write(try std.fmt.bufPrint(&buf, "{X:0>2}", .{self.op_codes[1].?})),
            .Relative => if (self.value_at_address) |v| {
                count += try writer.write(try std.fmt.bufPrint(&buf, "{X:0>4}", .{v}));
            } else {count += try writer.write(try std.fmt.bufPrint(&buf, "{X:0>2}", .{self.op_codes[1].?}));},
            else => {}
        }

        // Write terminator |LDA $12AE,X|
        count += try writer.write(switch (self.addressing) {
            .AbsoluteX => ",X",
            .AbsoluteY => ",Y",
            .Indirect => ")",
            .IndirectX => ",X)",
            .IndirectY => "),Y",
            .ZeroPageX => ",X",
            .ZeroPageY => ",Y",
            else => ""
        });

        // Write value at address |LDA $12AE,X @ 12BD = 68| if the data is present
        if (self.value_at_address) |v| {
            switch (self.addressing) {
                .Absolute, .ZeroPage => count += try writer.write(try std.fmt.bufPrint(&buf, " = {X:0>2}", .{v})),
                .AbsoluteX => count += try writer.write(try std.fmt.bufPrint(&buf, " @ {X:0>4} = {X:0>2}", .{(@as(u16, self.op_codes[2].?) << 8 | self.op_codes[1].?) +% self.x_value.?, v})),
                .AbsoluteY => count += try writer.write(try std.fmt.bufPrint(&buf, " @ {X:0>4} = {X:0>2}", .{(@as(u16, self.op_codes[2].?) << 8 | self.op_codes[1].?) +% self.y_value.?, v})),
                .ZeroPageX => count += try writer.write(try std.fmt.bufPrint(&buf, " @ {X:0>2} = {X:0>2}", .{self.op_codes[1].? +% self.x_value.?, v})),
                .ZeroPageY => count += try writer.write(try std.fmt.bufPrint(&buf, " @ {X:0>2} = {X:0>2}", .{self.op_codes[1].? +% self.y_value.?, v})),
                .Indirect => count += try writer.write(try std.fmt.bufPrint(&buf, " = {X:0>4}", .{v})),
                .IndirectX => count += try writer.write(try std.fmt.bufPrint(&buf, " @ {X:0>2} = {X:0>4} = {X:0>2}", .{self.x_value.? +% self.op_codes[1].?, self.vector.?, v})),
                .IndirectY => count += try writer.write(try std.fmt.bufPrint(&buf, " = {X:0>4} @ {X:0>4} = {X:0>2}", .{self.vector.?, self.vector.? +% self.y_value.?, v})),
                else => {}
            }
        }

        if (opt.width) |w| {
            var unicode_buf = [_]u8{0} ** 7;
            const unicode_len = try std.unicode.utf8Encode(opt.fill, &unicode_buf);
            try writer.writeBytesNTimes(unicode_buf[0..unicode_len], w - count);
        }
    }
};