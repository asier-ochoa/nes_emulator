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
                    @setEvalBranchQuota(100000000);
                    for (@typeInfo(instr).Struct.decls) |d| {
                        if (@field(instr, d.name) == opcode) break :blk d.name;
                    }
                    break :blk "<UNKNOWN>";
                }
            };
            logger.err(
                "Reached illegal instruction \"{s}\" on cycle T{}\nA = 0x{X:2>0}, X = 0x{X:2>0}, Y = 0x{X:2>0}, PC = 0x{X:4>0}, SP = 0x{X:2>0}, IR = 0x{X:2>0}, S = 0b{b:8>0}\n",
                .{instr_name, self.current_instruction_cycle, self.a_register, self.x_register, self.y_register, self.program_counter, self.stack_pointer, self.instruction_register, self.status_register}
            );
            return error.IllegalInstruction;
        }
    };
}

pub const reset_vector_low_order: u16 = 0xfffc;

// Instruction pneumonics
pub const instr = struct {
    // Add memory to accumulator with carry
    pub const ADCimm = 0x69;
    pub const ADCzpg = 0x65;
    pub const ADCzpgX = 0x75;
    pub const ADCabs = 0x6D;
    pub const ADCabsX = 0x7D;
    pub const ADCabsY = 0x79;
    pub const ADCindX = 0x61;
    pub const ADCindY = 0x71;

    // AND memory with accumulator
    pub const ANDimm = 0x29;
    pub const ANDzpg = 0x25;
    pub const ANDzpgX = 0x35;
    pub const ANDabs = 0x2D;
    pub const ANDabsX = 0x3D;
    pub const ANDabsY = 0x39;
    pub const ANDindX = 0x21;
    pub const ANDindY = 0x31;

    // Shift left one bit
    pub const ASLacc = 0x0A;
    pub const ASLzpg = 0x06;
    pub const ASLzpgX = 0x16;
    pub const ASLabs = 0x0E;
    pub const ASLabsX = 0x1E;

    // Branch on carry clear
    pub const BCCrel = 0x90;

    // Branch on carry set
    pub const BCSrel = 0xB0;

    // Branch on result zero
    pub const BEQrel = 0xF0;

    // Test bits in memory with accumulator;
    pub const BITzpg = 0x24;
    pub const BITabs = 0x2C;

    // Branch on result minus
    pub const BMIrel = 0x30;

    // Branch on result not zero
    pub const BNErel = 0xD0;

    // Branch on result plus
    pub const BPLrel = 0x10;

    // Force break signal
    pub const BRK = 0x00;

    // Branch on overflow clear
    pub const BVCrel = 0x50;

    // Branch on overflow set
    pub const BVSrel = 0x70;

    // Clear carry flag
    pub const CLC = 0x18;

    // Clear decimal mode
    pub const CLD = 0xD8;

    // Clear interrupt disable bit
    pub const CLI = 0x58;

    // Clear overflow flag
    pub const CLV = 0xB8;

    // Compare memory with accumulator
    pub const CMPimm = 0xC9;
    pub const CMPzpg = 0xC5;
    pub const CMPzpgX = 0xD5;
    pub const CMPabs = 0xCD;
    pub const CMPabsX = 0xDD;
    pub const CMPabsY = 0xD9;
    pub const CMPindX = 0xC1;
    pub const CMPindY = 0xD1;

    // Compare memory and index X
    pub const CPXimm = 0xE0;
    pub const CPXzpg = 0xE4;
    pub const CPXabs = 0xEC;

    // Compare memory and index Y
    pub const CPYimm = 0xC0;
    pub const CPYzpg = 0xC4;
    pub const CPYabs = 0xCC;

    // Decrement memory by one
    pub const DECzpg = 0xC6;
    pub const DECzpgX = 0xD6;
    pub const DECabs = 0xCE;
    pub const DECabsX = 0xDE;

    // Decrement index X by one
    pub const DEX = 0xCA;

    // Decrement index Y by one;
    pub const DEY = 0x88;

    // ExclusiveOR memory with accumulator
    pub const EORimm = 0x49;
    pub const EORzpg = 0x45;
    pub const EORzpgX = 0x55;
    pub const EORabs = 0x4D;
    pub const EORabsX = 0x5D;
    pub const EORabsY = 0x59;
    pub const EORindX = 0x41;
    pub const EORindY = 0x51;

    // Increment memory by one;
    pub const INCzpg = 0xE6;
    pub const INCzpgX = 0xF6;
    pub const INCabs = 0xEE;
    pub const INCabsX = 0xFE;

    // Increment index X by one;
    pub const INX = 0xE8;

    // Increment index Y by one;
    pub const INY = 0xC8;

    // Jump to new location
    pub const JMPabs = 0x4C;
    pub const JMPind = 0x6C;

    // Jump to new location saving return address
    pub const JSRabs = 0x20;

    // Load accumulator with memory
    pub const LDAimm = 0xA9;
    pub const LDAzpg = 0xA5;
    pub const LDAzpgX = 0xB5;
    pub const LDAabs = 0xAD;
    pub const LDAabsX = 0xBD;
    pub const LDAabsY = 0xB9;
    pub const LDAindX = 0xA1;
    pub const LDAindY = 0xB1;

    // Load index X with memory
    pub const LDXimm = 0xA2;
    pub const LDXzpg = 0xA6;
    pub const LDXzpgY = 0xB6;
    pub const LDXabs = 0xAE;
    pub const LDXabsY = 0xBE;

    // Load index Y with memory
    pub const LDYimm = 0xA0;
    pub const LDYzpg = 0xA4;
    pub const LDYzpgX = 0xB4;
    pub const LDYabs = 0xAC;
    pub const LDYabsX = 0xBC;

    // Shift one bit right
    pub const LSRacc = 0x4A;
    pub const LSRzpg = 0x46;
    pub const LSRzpgX = 0x56;
    pub const LSRabs = 0x4E;
    pub const LSRabsX = 0x5E;

    // No operation
    pub const NOP = 0xEA;

    // OR memory with accumulator
    pub const ORAimm = 0x09;
    pub const ORAzpg = 0x05;
    pub const ORAzpgX = 0x15;
    pub const ORAabs = 0x0D;
    pub const ORAabsX = 0x1D;
    pub const ORAabsY = 0x19;
    pub const ORAindX = 0x01;
    pub const ORAindY = 0x11;

    // Push accumulator on stack
    pub const PHA = 0x48;

    // Push status on stack
    pub const PHP = 0x08;

    // Pull accumulator from stack
    pub const PLA = 0x68;

    // Pull status from stack
    pub const PLP = 0x28;

    // Rotate one bit left
    pub const ROLacc = 0x2A;
    pub const ROLzpg = 0x26;
    pub const ROLzpgX = 0x36;
    pub const ROLabs = 0x2E;
    pub const ROLabsX = 0x3E;

    // Rotate one bit right
    pub const RORacc = 0x6A;
    pub const RORzpg = 0x66;
    pub const RORzpgX = 0x76;
    pub const RORabs = 0x6E;
    pub const RORabsX = 0x7E;

    // Return from interrupt
    pub const RTI = 0x40;

    // Return from subroutine (from a JSR)
    pub const RTS = 0x60;

    // Subtract memory from accumulator with borrow
    pub const SBCimm = 0xE9;
    pub const SBCzpg = 0xE5;
    pub const SBCzpgX = 0xF5;
    pub const SBCabs = 0xED;
    pub const SBCabsX = 0xED;
    pub const SBCabsY = 0xF9;
    pub const SBCindX = 0xE1;
    pub const SBCindY = 0xF1;

    // Set carry flag
    pub const SEC = 0x38;

    // Set decimal flag
    pub const SED = 0xF8;

    // Set interrupt disable status
    pub const SEI = 0x78;

    // Store accumulator in memory
    pub const STAzpg = 0x85;
    pub const STAzpgX = 0x95;
    pub const STAabs = 0x8D;
    pub const STAabsX = 0x9D;
    pub const STAabsY = 0x99;
    pub const STAindX = 0x81;
    pub const STAindY = 0x81;

    // Store index X in memory
    pub const STXzpg = 0x86;
    pub const STXzpgY = 0x96;
    pub const STXabs = 0x8E;

    // Store index Y in memory
    pub const STYzpg = 0x84;
    pub const STYzpgX = 0x94;
    pub const STYabs = 0x8C;

    // Transfer accumulator to index X
    pub const TAX = 0xAA;

    // Transfer accumulator to index Y
    pub const TAY = 0xA8;

    // Transfer stack pointer to index X
    pub const TSX = 0xBA;

    // Transfer index X to accumulator
    pub const TXA = 0x8A;

    // Transfer index X to stack pointer
    pub const TXS = 0x9A;

    // Transfer index Y to accumulator
    pub const TYA = 0x98;
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

test "Full Instruction Rom" {
    
}
