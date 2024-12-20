// PLAN
// Debugger will hold a reference to a bus and a cpu
// It will tick the cpu and check against a list of breakpoints

// The dissasembly will be stored as a list of instructions in a different
// format.
// Opcodes in 6502.zig will contain data on the base pneumonic and addressing mode

const proc = @import("6502.zig");
const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");
const bus = @import("bus.zig");

const MemoryBreakpoint = struct {
    address: u16,
    active: bool
};

pub const Debugger = struct {
    const Self = @This();
    const BreakpointList = std.AutoArrayHashMap(u16, MemoryBreakpoint);

    // Address as key
    read_breakpoints: BreakpointList,
    write_breakpoints: BreakpointList,
    pc_breakpoints: BreakpointList,

    // Sentinel to control if we have to pause, null means no breakpoint has been hit
    break_hit: ?MemoryBreakpoint = null,
    pause: bool = false,

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .read_breakpoints = BreakpointList.init(alloc),
            .write_breakpoints = BreakpointList.init(alloc),
            .pc_breakpoints = BreakpointList.init(alloc)
        };
    }

    pub fn attach(self: Self) void {
        _ = self;
    }

    pub fn detach(self: Self) void {
        _ = self;
    }

    // Called by CPU
    // Passing the CPU is needed to read directly from bus
    pub fn checkReadBreakpoints(self: *Self, address: u16, cpu: anytype) !u8 {
        // Check if this is a program counter read, REQUIRES THAT THE CPU ONLY INCREMENT PC AFTER READING
        const break_list = if (address == cpu.program_counter) self.pc_breakpoints else self.read_breakpoints;
        if (break_list.get(address)) |v| {
            if (v.active) self.break_hit = v;
        }
        return cpu.bus.cpuRead(address);
    }

    // Called by CPU
    // Passing the CPU is needed to read directly from bus
    pub fn checkWriteBreakpoints(self: *Self, address: u16, value: u8, cpu: anytype) !void {
        if (self.write_breakpoints.get(address)) |v| {
            if (v.active) self.break_hit = v;
        }
        return cpu.bus.cpuWrite(address, value);
    }
};

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

const OnInvalidOp = enum {
    // Exits dissasembly and returns as is
    abort,
    // Ignores and continues by filling the dissasembly with garbage
    ignore,
    // Exits with error
    fail
};

const DissassemblyOptions = union(DissassemblyOptionsTag) {
    current_instruction: struct {record_state: bool = true},
    single_instruction: struct {address: u16},
    slice: struct {memory: []const u8, on_fail: OnInvalidOp = .abort, alloc: std.mem.Allocator},
    from_to: struct {
        start: u16,
        end: u16,
        on_fail: OnInvalidOp = .abort,
        alloc: std.mem.Allocator
    }
};

// TODO: Find a mechanism such that bus reads dont trigger side effects (cpu.safeBusRead() triggers side effects)
// IDEA: Have a special "minimalDissasembly" type that only holds the length and cycles of an instruction, this is to
// help a future "stepping" function for the debugger. I could also implement stepping by checking for cpu.endInstruction()
pub fn dissasemble(cpu: anytype, comptime opt_kind: DissassemblyOptionsTag, opt: anytype) switch (opt_kind) {
    .current_instruction, .single_instruction => DissasemblyError!InstructionDissasembly,
    else => anyerror![]InstructionDissasembly
} {
    const inner_opt = @unionInit(DissassemblyOptions, @tagName(opt_kind), opt);

    // Used to denote currently pointed to memory
    var mem_idx: usize = switch (opt_kind) {
        .current_instruction, .single_instruction => 0,
        .from_to => inner_opt.from_to.start,
        .slice => 0,
    };

    var buf = std.ArrayListUnmanaged(InstructionDissasembly){};
    errdefer switch (inner_opt) {
        .from_to => |o| buf.deinit(o.alloc),
        .slice => |o| buf.deinit(o.alloc),
        else => {}
    };

    while (true) {
        const pc: u16 = switch (inner_opt) {
            .current_instruction => if (opt_kind == .current_instruction) cpu.program_counter else unreachable,
            .single_instruction => |o| o.address,
            .slice => @intCast(mem_idx & 0xFFFF),
            .from_to => @intCast(mem_idx & 0xFFFF)
        };
        const op_c = switch (inner_opt) {
            .current_instruction => if (opt_kind == .current_instruction) cpu.safeBusReadConst(pc) else unreachable,
            .single_instruction => |o| if (opt_kind == .single_instruction) cpu.safeBusReadConst(o.address) else unreachable,
            .slice => |o| o.memory[mem_idx],
            .from_to => if (opt_kind == .from_to) cpu.safeBusReadConst(@intCast(mem_idx & 0xFFFF)) else unreachable
        };
        mem_idx += 1;

        errdefer std.debug.print("Error: Invalid op: 0x{X:0>2}\n", .{op_c});
        const meta = switch (opt_kind) {
            .current_instruction, .single_instruction => proc.instr.getMetadata(op_c) orelse return DissasemblyError.invalid_opcode,
            inline .slice, .from_to => |k| switch (@field(inner_opt, @tagName(k)).on_fail) {
                .abort => proc.instr.getMetadata(op_c) orelse return buf.toOwnedSlice(opt.alloc),
                .fail => proc.instr.getMetadata(op_c) orelse return DissasemblyError.invalid_opcode,
                .ignore => proc.instr.getMetadata(op_c) orelse proc.instr.getInvalidMetadata(op_c),
            }
        };
        const operands = [_]?u8{
            op_c,
            if (meta.len > 1) blk: {
                defer mem_idx += 1;
                break :blk switch (inner_opt) {
                    .current_instruction => if (opt_kind == .current_instruction) cpu.safeBusReadConst(pc +% 1) else unreachable,
                    .single_instruction => |o| if (opt_kind == .single_instruction) cpu.safeBusReadConst(o.address +% 1) else unreachable,
                    .slice => |o| o.memory[mem_idx],
                    .from_to => if (opt_kind == .from_to) cpu.safeBusReadConst(@intCast(mem_idx & 0xFFFF)) else unreachable
                };
            } else null,
            if (meta.len > 2) blk: {
                defer mem_idx += 1;
                break :blk switch (inner_opt) {
                    .current_instruction => if (opt_kind == .current_instruction) cpu.safeBusReadConst(pc +% 2) else unreachable,
                    .single_instruction => |o| if (opt_kind == .single_instruction) cpu.safeBusReadConst(o.address +% 2) else unreachable,
                    .slice => |o| o.memory[mem_idx],
                    .from_to => if (opt_kind == .from_to) cpu.safeBusReadConst(@intCast(mem_idx & 0xFFFF)) else unreachable
                };
            } else null,
        };
        var dis: InstructionDissasembly = .{
            .pc = pc,
            .len = meta.len,
            .pneumonic = meta.pneumonic,
            .cycles = meta.cycles,
            .op_codes = operands,
            .addressing = meta.addressing,
            .value_at_address = if (opt_kind == .current_instruction and inner_opt == .current_instruction and inner_opt.current_instruction.record_state) switch (meta.addressing) {
                .Absolute => if (operands[0].? != proc.instr.JSRabs.op and operands[0].? != proc.instr.JMPabs.op)
                    cpu.safeBusReadConst(@as(u16, operands[2].?) << 8 | operands[1].?)
                    else null,
                .AbsoluteX => cpu.safeBusReadConst((@as(u16, operands[2].?) << 8 | operands[1].?) +% cpu.x_register),
                .AbsoluteY => cpu.safeBusReadConst((@as(u16, operands[2].?) << 8 | operands[1].?) +% cpu.y_register),
                .ZeroPage => cpu.safeBusReadConst(operands[1].?),
                .ZeroPageX => cpu.safeBusReadConst(operands[1].? +% cpu.x_register),
                .ZeroPageY => cpu.safeBusReadConst(operands[1].? +% cpu.y_register),
                .Indirect => blk: {
                    const vector_address = @as(u16, operands[2].?) << 8 | operands[1].?;
                    break :blk @as(u16, cpu.safeBusReadConst(
                        (vector_address & 0xFF00 | @as(u8, @intCast(vector_address & 0x00FF)) +% 1)
                    )) << 8 | cpu.safeBusReadConst(vector_address);
                },
                .Relative => if (operands[1].? >> 7 > 0) pc + meta.len -% (operands[1].? & 0x7F) else pc + meta.len +% (operands[1].? & 0x7F),
                else => null
            } else null
        };
        if (opt_kind == .current_instruction and inner_opt == .current_instruction and inner_opt.current_instruction.record_state) {
            if (inner_opt.current_instruction.record_state) {}
            switch (meta.addressing) {
                .AbsoluteX, .ZeroPageX, .IndirectX => dis.x_value = cpu.x_register,
                .AbsoluteY, .ZeroPageY, .IndirectY => dis.y_value = cpu.y_register,
                else => {}
            }
            switch (meta.addressing) {
                .IndirectX => {
                    const vector_address = operands[1].? +% cpu.x_register;
                    dis.vector = @as(u16, cpu.safeBusReadConst(vector_address +% 1)) << 8 | cpu.safeBusReadConst(vector_address);
                    dis.value_at_address = cpu.safeBusReadConst(dis.vector.?);
                },
                .IndirectY => {
                    dis.vector = @as(u16, cpu.safeBusReadConst(operands[1].? +% 1)) << 8 | cpu.safeBusReadConst(operands[1].?);
                    dis.value_at_address = cpu.safeBusReadConst(dis.vector.? +% cpu.y_register);
                },
                else => {}
            }
            return dis;
        }
        // Allocate memory for dissasembly
        switch (opt_kind) {
            .from_to, .slice => try buf.append(@field(opt, "alloc"), dis),
            else => {}
        }
        if (opt_kind == .slice and mem_idx >= inner_opt.slice.memory.len) {
            return try buf.toOwnedSlice(inner_opt.slice.alloc);
        }
        if (opt_kind == .from_to and mem_idx >= inner_opt.from_to.end) {
            return try buf.toOwnedSlice(inner_opt.from_to.alloc);
        }
    }
}

pub const InstructionDissasembly = struct {
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

const test_obj_code = [_]u8{0xAD, 0x16, 0x40, 0x20, 0x00, 0x43, 0xA0, 0x20, 0x91, 0x69, 0xAA, 0x1D, 0xA1, 0x1A};
const test_obj_code_malformed = [_]u8{0xAD, 0x16, 0x40, 0x20, 0x00, 0x43, 0xA0, 0x20, 0xFF, 0x69, 0xAA, 0x1D, 0xA1, 0x1A};
const test_formatted_dissasembly = \\LDA $4016
                                   \\JSR $4300
                                   \\LDY #$20
                                   \\STA ($69),Y
                                   \\TAX
                                   \\ORA $1AA1,X
                                   \\
                                   ;
const test_formatted_dissasembly_malformed = \\LDA $4016
                                   \\JSR $4300
                                   \\LDY #$20
                                   \\
                                   ;

test "Slice Dissasembly" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var buf = std.ArrayList(u8).init(alloc);
    const buf_writer = buf.writer();

    const dis = try dissasemble(.{}, .slice, .{.memory = &test_obj_code, .alloc = alloc});

    for (dis) |d| {
        try buf_writer.print("{any}\n", .{d});
    }

    try std.testing.expectEqualStrings(test_formatted_dissasembly, buf.items);

    // Testing with error
    buf.clearAndFree();
    const err_dis = try dissasemble(.{}, .slice, .{.memory = &test_obj_code_malformed, .alloc = alloc});

    for (err_dis) |d| {
        try buf_writer.print("{any}\n", .{d});
    }

    try std.testing.expectEqualStrings(test_formatted_dissasembly_malformed, buf.items);
}

test "FromTo Dissasemby" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var buf = std.ArrayList(u8).init(alloc);
    const buf_writer = buf.writer();

    var test_bus = bus.Bus(struct {
        @"0000-FFFF": [0xFFFF]u8
    }).init();
    std.mem.copyForwards(u8, test_bus.memory_map.@"0000-FFFF"[0x8000..], &test_obj_code);
    const test_cpu = proc.CPU(@TypeOf(test_bus)).init(&test_bus);

    const dis = try dissasemble(
        test_cpu,
        .from_to,
        .{.start = 0x8000, .end = 0x8000 + test_obj_code.len, .alloc = alloc}
    );

    for (dis) |d| {
        try buf_writer.print("{any}\n", .{d});
    }

    try std.testing.expectEqualStrings(test_formatted_dissasembly, buf.items);

    // Testing with error
    buf.clearAndFree();
    std.mem.copyForwards(u8, test_bus.memory_map.@"0000-FFFF"[0x8000..], &test_obj_code_malformed);
    const err_dis = try dissasemble(
        test_cpu,
        .from_to,
        .{.start = 0x8000, .end = 0x8000 + test_obj_code_malformed.len, .alloc = alloc}
    );

    for (err_dis) |d| {
        try buf_writer.print("{any}\n", .{d});
    }

    try std.testing.expectEqualStrings(test_formatted_dissasembly_malformed, buf.items);
}