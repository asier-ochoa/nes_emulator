const std = @import("std");

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
                    else => self.processInstruction()
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
        fn processInstruction(self: *Self) void {
            switch (self.current_instruction_cycle) {
                1 => {
                    switch (self.instruction_register) {
                        // Read low byte of address for execution on memory data
                        instr.LDAabs, instr.LDAzpg, instr.STAabs, instr.LDXabs => {
                            self.data_latch = self.safeBusRead(self.program_counter);
                            self.program_counter += 1;
                        },
                        else => {} //TODO: log illegal instructions
                    }
                },
                2 => {
                    switch (self.instruction_register) {
                        instr.LDAabs, instr.STAabs, instr.LDXabs => {
                            self.data_latch |= @as(u16, self.safeBusRead(self.program_counter)) << 8;
                            self.program_counter += 1;
                        },
                        instr.LDAzpg => {
                            self.a_register = self.safeBusRead(self.data_latch);
                            if (self.a_register == 0) self.setFlag(.zero);
                            if (self.a_register & 0b10000000 != 0) self.setFlag(.negative);
                            self.current_instruction_cycle = instruction_cycle_reset;
                        },
                        else => {}
                    }
                },
                3 => {
                    switch (self.instruction_register) {
                        instr.LDAabs => {
                            self.a_register = self.safeBusRead(self.data_latch);
                            if (self.a_register == 0) self.setFlag(.zero);
                            if (self.a_register & 0b10000000 != 0) self.setFlag(.negative);
                            self.current_instruction_cycle = instruction_cycle_reset;
                        },
                        instr.LDXabs => {
                            self.x_register = self.safeBusRead(self.data_latch);
                            if (self.x_register == 0) self.setFlag(.zero);
                            if (self.x_register & 0b10000000 != 0) self.setFlag(.negative);
                            self.current_instruction_cycle = instruction_cycle_reset;
                        },
                        instr.STAabs => {
                            self.safeBusWrite(self.data_latch, self.a_register);
                            self.current_instruction_cycle = instruction_cycle_reset;
                        },
                        else => {}
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
    };
}

pub const reset_vector_low_order: u16 = 0xfffc;

// Instruction pneumonics
pub const instr = struct {
    pub const LDAabs = 0xAD;
    pub const LDAzpg = 0xA5;
    pub const LDXabs = 0xAE;
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
};