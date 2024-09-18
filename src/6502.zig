const std = @import("std");
const util = @import("util.zig");

pub const logger = std.log.scoped(.CPU);

// General design:
// The central method to advance the CPU is the tick method.
// The tick method, depending on the state of the CPU should be able
// to correctly execute its step.
// Functions prefixed with "tick" are only to be called from the tick() method.
// Functions without tick prefixed are related to general cpu control, often used for interrupt triggering
pub fn CPU(Bus: type) type {
    return struct {
        const Self = @This();
        const instruction_cycle_reset = -1;

        // CPU programming registers
        a_register: u8 = 0,
        x_register: u8 = 0,
        y_register: u8 = 0,
        status_register: u8 = 0,

        // Internal physical state
        instruction_register: u8 = 0,
        stack_pointer: u8 = 0,
        program_counter: u16 = 0,

        // Internal logical state
        current_instruction_cycle: i32 = 0, // Starts at 0, starts at instruction fetch cycle
        is_reseting: bool = false, // Used to track when in reset procedure, needed to do things like skip 2 clock cycles on reset
        addressing_mode: AddressingMode = .None,
        data_latch: u16 = 0, // Represents the two internal data latches the 6502 uses to store half addresses when fetching instructions

        // Bus connection
        bus: *Bus,

        pub fn init(bus: *Bus) Self {
            return Self {
                .bus = bus
            };
        }

        pub fn tick(self: *Self) CPUError!void {
            if (self.is_reseting) {
                try resetTick(self);
            } else {
                switch (self.current_instruction_cycle) {
                    0 => self.fetchInstruction(),
                    else => try self.processInstruction()
                }
            }
            self.current_instruction_cycle += 1;
        }

        // Sets the state to have the tick function follow the reset steps
        // Since fetching the opcode is not needed, the cycle starts at 1.
        // When called from BRK instruction, the cycle will correspond
        pub fn reset(self: *Self) void {
            self.is_reseting = true;
            self.current_instruction_cycle = 1;
        }

        // TODO: Rewrite such that it is consistent with real 6502 behaviour, specifically the ricoh model
        fn resetTick(self: *Self) CPUError!void {
            switch (self.current_instruction_cycle) {
                // Common t1 through t4 operations for all interrupt routines
                1, 2, 3, 4 => {},
                // Fetch low order byte then high order byte from reset vector
                5 => self.program_counter = self.safeBusRead(reset_vector_low_order),
                6 => {
                    self.program_counter |= @as(u16, self.safeBusRead(reset_vector_low_order + 1)) << 8;
                    self.is_reseting = false;
                    self.current_instruction_cycle = 0;
                },
                else => return CPUError.IllegalClockState //TODO: log illegal clock cycles
            }
        }

        fn fetchInstruction(self: *Self) void {
            self.instruction_register = self.safeBusRead(self.program_counter);
            self.program_counter += 1;
        }

        // Master list of all instructions
        // Big switch case that uses the instruction + the current cycle to determine what to do.
        // ATTENTION: In order to reset the current instruction cycle, set it to
        fn processInstruction(self: *Self) CPUError!void {
            switch (self.current_instruction_cycle) {
                1 => {
                    switch (self.instruction_register) {
                        // Read low byte of address for execution on memory data
                        instr.LDAabs, instr.LDAzpg, instr.STAabs,
                        instr.LDXabs, instr.LDXzpg, instr.LDAabsX,
                        instr.LDAabsY, instr.LDAzpgX => {
                            self.data_latch = self.safeBusRead(self.program_counter);
                            self.program_counter += 1;
                        },
                        instr.LDAimm => {
                            self.loadRegister(.A, self.program_counter);
                            self.endInstruction();
                        },
                        else => return logIllegalInstruction(self.*) //TODO: log illegal instructions
                    }
                },
                2 => {
                    switch (self.instruction_register) {
                        // All instructions that need to read the high byte of the operand
                        instr.LDAabs, instr.STAabs, instr.LDXabs,
                        instr.LDAabsX, instr.LDAabsY => {
                            self.data_latch |= @as(u16, self.safeBusRead(self.program_counter)) << 8;
                            self.program_counter += 1;
                        },
                        instr.LDAzpg => {
                            self.loadRegister(.A, self.data_latch);
                            self.endInstruction();
                        },
                        instr.LDAzpgX => {},
                        instr.LDXzpg => {
                            self.loadRegister(.X, self.data_latch);
                            self.endInstruction();
                        },
                        else => return logIllegalInstruction(self.*)
                    }
                },
                3 => {
                    switch (self.instruction_register) {
                        instr.LDAabs => {
                            self.loadRegister(.A, self.data_latch);
                            self.endInstruction();
                        },
                        instr.LDXabs => {
                            self.loadRegister(.X, self.data_latch);
                            self.endInstruction();
                        },
                        instr.STAabs => {
                            self.safeBusWrite(self.data_latch, self.a_register);
                            self.endInstruction();
                        },
                        instr.LDAabsX => {
                            // Check if loading from another page
                            if ((self.data_latch & 0x00FF) + self.x_register > 0xFF) {
                                self.setFlag(.carry);
                            } else {
                                self.loadRegister(.A, self.data_latch +% self.x_register);
                                self.endInstruction();
                            }
                        },
                        instr.LDAabsY => {
                            // Check if loading from another page
                            if ((self.data_latch & 0x00FF) + self.y_register > 0xFF) {
                                self.setFlag(.carry);
                            } else {
                                self.loadRegister(.A, self.data_latch +% self.y_register);
                                self.endInstruction();
                            }
                        },
                        instr.LDAzpgX => {
                            self.loadRegister(.A, @as(u8, @intCast(self.data_latch)) +% self.x_register);
                            self.endInstruction();
                        },
                        else => return logIllegalInstruction(self.*)
                    }
                },
                4 => {
                    switch (self.instruction_register) {
                        instr.LDAabsX => {
                            self.loadRegister(.A, self.data_latch +% self.x_register);
                            self.endInstruction();
                        },
                        instr.LDAabsY => {
                            self.loadRegister(.A, self.data_latch +% self.y_register);
                            self.endInstruction();
                        },
                        else => return logIllegalInstruction(self.*)
                    }
                },
                else => {}
            }
        }

        pub inline fn isFlagSet(self: Self, flag: StatusFlag) bool {
            return self.status_register & @intFromEnum(flag) != 0;
        }

        pub inline fn setFlag(self: *Self, flag: StatusFlag) void {
            self.status_register |= @intFromEnum(flag);
        }

        pub inline fn clearFlag(self: *Self, flag: StatusFlag) void {
            self.status_register &= ~@intFromEnum(flag);
        }

        // Declares current cycle to be the end of the current instruction
        inline fn endInstruction(self: *Self) void {
            self.current_instruction_cycle = instruction_cycle_reset;
        }

        inline fn loadRegister(self: *Self, register: enum {A, X, Y}, from: u16) void {
            switch (register) {
                .A => {
                    self.a_register = self.safeBusRead(from);
                    if (self.a_register == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                    if (self.a_register & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                },
                .X => {
                    self.x_register = self.safeBusRead(from);
                    if (self.x_register == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                    if (self.x_register & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                },
                .Y => {
                    self.y_register = self.safeBusRead(from);
                    if (self.y_register == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                    if (self.y_register & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                }
            }
        }

        inline fn safeBusRead(self: Self, address: u16) u8 {
            return self.bus.cpuRead(address) catch blk: {
                logger.warn("Unmapped read from address 0x{X:0>4}, returning 0\n", .{address});
                break :blk 0;
            };
        }

        inline fn safeBusWrite(self: *Self, address: u16, data: u8) void {
            self.bus.cpuWrite(address, data) catch {
                logger.warn("Unmapped write to address 0x{X:0>4} with value 0x{X:0>2}\n", .{address, data});
            };
        }

        fn logIllegalInstruction(self: Self) CPUError!void {
            // Find opcode name to dissasemble
            const instr_name = switch (self.instruction_register) {
                inline 0...0xFF => |opcode| comptime blk: {
                    @setEvalBranchQuota(3000);
                    for (@typeInfo(instr).Struct.decls) |d| {
                        if (@field(instr, d.name) == opcode) break :blk d.name;
                    }
                    break :blk "<UNKNOWN>";
                }
            };
            logger.err(
                "Reached illegal instruction \"{s}\" on cycle T{}\nA = 0x{X:2>0}, X = 0x{X:2>0}, Y = 0x{X:2>0}, PC = 0x{X:4>0}, S = 0b{b:8>0}\n",
                .{instr_name, self.current_instruction_cycle, self.a_register, self.x_register, self.y_register, self.program_counter, self.status_register}
            );
            return error.IllegalInstruction;
        }
    };
}

pub const reset_vector_low_order: u16 = 0xfffc;

// Instruction pneumonics
pub const instr = struct {
    pub const LDAimm = 0xA9;
    pub const LDAzpg = 0xA5;
    pub const LDAzpgX = 0xB5;
    pub const LDAabs = 0xAD;
    pub const LDAabsX = 0xBD;
    pub const LDAabsY = 0xB9;
    pub const LDXabs = 0xAE;
    pub const LDXzpg = 0xA6;
    pub const STAabs = 0x8D;
};

pub const AddressingMode = enum {
    None, // Denotes no current addressing, reset after instruction ends
    Implied,
    Immediate,
    Absolute,
    ZeroPage,
    IndexedAbsoluteX,
    IndexedAbsoluteY,
    IndexedZeroPageX,
    IndexedZeroPageY,
    Indirect,
    PreIndexedIndirectZeroPageX,
    PostIndexedIndirectZeroPageY
};

pub const StatusFlag = enum(u8) {
    carry = 1,
    zero = 1 << 1,
    irq_disable = 1 << 2,
    decimal_mode = 1 << 3,
    brk_command = 1 << 4,
    overflow = 1 << 6,
    negative = 1 << 7
};

pub const CPUError = error {
    IllegalClockState, // When the cpu reaches a "current_instruction_cycle" that doesn't represent any possible state
    IllegalInstruction,
    NotImplemented
};

// TODO: add zero bit status register test
test "LDAabs" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        &([_]u8{instr.LDAabs, 0x00, 0x02} ++ [_]u8{0} ** 0x01fd ++ [_]u8{0xF4})
    );
    // Execute instruction
    for (0..4) |_| {
        try cpu.tick();
    }
    try std.testing.expectEqual(util.TestCPU {
        .a_register = 0xF4,
        .instruction_register = instr.LDAabs,
        .program_counter = 0x0003,
        .data_latch = 0x0200,
        .bus = &bus,
        .status_register = @intFromEnum(StatusFlag.negative)
    }, cpu);
}

test "STAabs" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        &[_]u8{instr.STAabs, 0x00, 0x02}
    );
    cpu.a_register = 0x64;
    // Execute instruction
    for (0..4) |_| {
        try cpu.tick();
    }
    try std.testing.expectEqual(0x64, bus.memory_map.@"0000-EFFF"[0x0200]);
}

// TODO: add zero bit status register test
test "LDAzpg" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        &([_]u8{instr.LDAzpg, 0xFE} ++ [_]u8{0} ** 0xFC ++ [_]u8{0xF4})
    );
    for (0..3) |_| {
        try cpu.tick();
    }
    try std.testing.expectEqual(util.TestCPU {
        .a_register = 0xF4,
        .instruction_register = instr.LDAzpg,
        .program_counter = 0x0002,
        .data_latch = 0x00fe,
        .bus = &bus,
        .status_register = @intFromEnum(StatusFlag.negative)
    }, cpu);
}

// TODO: add zero bit status register test
test "LDXabs" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        &([_]u8{instr.LDXabs, 0x00, 0x02} ++ [_]u8{0} ** 0x01fd ++ [_]u8{0xF4})
    );
    // Execute instruction
    for (0..4) |_| {
        try cpu.tick();
    }
    try std.testing.expectEqual(util.TestCPU {
        .x_register = 0xF4,
        .instruction_register = instr.LDXabs,
        .program_counter = 0x0003,
        .data_latch = cpu.data_latch,
        .bus = &bus,
        .status_register = @intFromEnum(StatusFlag.negative)
    }, cpu);
}

test "LDAimm" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        &[_]u8{instr.LDAimm, 0xD8}
    );
    for (0..2) |_| {
        try cpu.tick();
    }
    try std.testing.expectEqual(util.TestCPU {
        .a_register = 0xD8,
        .instruction_register = instr.LDAimm,
        .program_counter = 0x0001,
        .bus = &bus,
        .status_register = @intFromEnum(StatusFlag.negative)
    }, cpu);
}

test "LDAabsX" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        // LDA 0x0200, X
        // LDA 0x0201, X (Across pages)
        &[_]u8{instr.LDAabsX, 0x00, 0x02, instr.LDAabsX, 0x01, 0x02}
    );
    try bus.cpuWrite(0x0201, 0xF4);
    try bus.cpuWrite(0x0300, 0xF5);
    // Execute instruction
    cpu.x_register = 0x01;
    for (0..9) |i| {
        try cpu.tick();
        if (i == 3) {
            try std.testing.expectEqual(util.TestCPU {
                .a_register = 0xF4,
                .x_register = 0x01,
                .status_register = @intFromEnum(StatusFlag.negative),
                .program_counter = 0x0003,
                .data_latch = cpu.data_latch,
                .instruction_register = cpu.instruction_register,
                .bus = &bus
            }, cpu);
            cpu.x_register = 0xFF;
        }
    }
    try std.testing.expectEqual(util.TestCPU {
        .a_register = 0xF5,
        .x_register = 0xFF,
        .status_register = @intFromEnum(StatusFlag.negative) | @intFromEnum(StatusFlag.carry),
        .program_counter = 0x0006,
        .data_latch = cpu.data_latch,
        .instruction_register = cpu.instruction_register,
        .bus = &bus
    }, cpu);
}

test "LDAabsY" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        // LDA 0x0200, Y
        // LDA 0x0201, Y (Across pages)
        &[_]u8{instr.LDAabsY, 0x00, 0x02, instr.LDAabsY, 0x01, 0x02}
    );
    try bus.cpuWrite(0x0201, 0xF4);
    try bus.cpuWrite(0x0300, 0xF5);
    // Execute instruction
    cpu.y_register = 0x01;
    for (0..9) |i| {
        try cpu.tick();
        if (i == 3) {
            try std.testing.expectEqual(util.TestCPU {
                .a_register = 0xF4,
                .y_register = 0x01,
                .status_register = @intFromEnum(StatusFlag.negative),
                .program_counter = 0x0003,
                .data_latch = cpu.data_latch,
                .instruction_register = cpu.instruction_register,
                .bus = &bus
            }, cpu);
            cpu.y_register = 0xFF;
        }
    }
    try std.testing.expectEqual(util.TestCPU {
        .a_register = 0xF5,
        .y_register = 0xFF,
        .status_register = @intFromEnum(StatusFlag.negative) | @intFromEnum(StatusFlag.carry),
        .program_counter = 0x0006,
        .data_latch = cpu.data_latch,
        .instruction_register = cpu.instruction_register,
        .bus = &bus
    }, cpu);
}

test "Full Instruction Rom" {
    
}

// Writting tests is slowing me down too much :(