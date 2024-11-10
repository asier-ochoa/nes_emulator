const std = @import("std");
const util = @import("util.zig");
const rom_loader = @import("rom_loader.zig");
const builtin = @import("builtin");
const debug = @import("debugger.zig");

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
        status_register: u8 = 0x24,

        // Internal physical state
        instruction_register: u8 = 0,
        stack_pointer: u8 = 0,
        program_counter: u16 = 0,

        // Internal logical state
        current_instruction_cycle: i32 = 0, // Starts at 0, starts at instruction fetch cycle
        data_latch: u16 = 0, // Represents the two internal data latches the 6502 uses to store half addresses when fetching instructions
        indirect_jump: u16 = 0, // USED ONLY FOR JMPind as a latch when fetching real address from base address

        // Bus connection
        bus: *Bus,

        // Debugger connection, required to redirect bus reads to the debugger's breakpoint checking functions
        debugger: ?*debug.Debugger = null,

        pub fn init(bus: *Bus) Self {
            return Self {
                .bus = bus
            };
        }

        pub fn tick(self: *Self) CPUError!void {
            switch (self.current_instruction_cycle) {
                0 => self.fetchInstruction(),
                else => try self.processInstruction()
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

        fn fetchInstruction(self: *Self) void {
            self.instruction_register = self.safeBusRead(self.program_counter);
            self.program_counter += 1;
        }

        // Master list of all instructions
        // Big switch case that uses the instruction + the current cycle to determine what to do.
        // ATTENTION: In order to reset the current instruction cycle, set it to instruction_cycle_reset
        // ATTENTION: All reads and writes must be done through the busRead and busWrite functions such that
        // memory map struct functions can execute their own side effects.
        // TODO: Split page boundary crossing reads accross 2 cycles in accordance to datasheet
        // TODO: REFACTOR THIS WHOLE THING WITH A FOCUS ON GROUPING BY HOWEVER THE DATASHEET GROUPS INSTRUCTIONS. AFTER THE VISUAL DEBUGGER IS DONE!!!!!
        fn processInstruction(self: *Self) CPUError!void {
            switch (self.current_instruction_cycle) {
                1 => {
                    switch (self.instruction_register) {
                        // Read low byte of address for execution on memory data
                        instr.LDAabs.op, instr.LDAzpg.op, instr.STAabs.op,
                        instr.LDXabs.op, instr.LDXzpg.op, instr.LDAabsX.op,
                        instr.LDAabsY.op, instr.LDAzpgX.op, instr.CMPzpg.op,
                        instr.STXzpg.op, instr.JSRabs.op, instr.BCSrel.op,
                        instr.BCCrel.op, instr.BEQrel.op, instr.BNErel.op,
                        instr.STAzpg.op, instr.BITzpg.op, instr.BVSrel.op,
                        instr.BVCrel.op, instr.BPLrel.op, instr.BMIrel.op,
                        instr.STYzpg.op, instr.STXabs.op, instr.ANDzpgX.op,
                        instr.LDAindX.op, instr.STAindX.op, instr.ORAindX.op,
                        instr.ANDindX.op, instr.EORindX.op, instr.ADCindX.op,
                        instr.CMPindX.op, instr.SBCindX.op, instr.LDYzpg.op,
                        instr.ORAzpg.op, instr.ANDzpg.op, instr.EORzpg.op,
                        instr.ADCzpg.op, instr.SBCzpg.op, instr.CPXzpg.op,
                        instr.CPYzpg.op, instr.LSRzpg.op, instr.ASLzpg.op,
                        instr.RORzpg.op, instr.ROLzpg.op, instr.INCzpg.op,
                        instr.DECzpg.op, instr.LDYabs.op, instr.STYabs.op,
                        instr.BITabs.op, instr.ORAabs.op, instr.ANDabs.op,
                        instr.EORabs.op, instr.ADCabs.op, instr.SBCabs.op,
                        instr.CMPabs.op, instr.CPXabs.op, instr.CPYabs.op,
                        instr.INCabs.op, instr.DECabs.op, instr.STAabsX.op,
                        instr.LDAindY.op, instr.STAindY.op, instr.ORAindY.op,
                        instr.ANDindY.op, instr.EORindY.op, instr.ADCindY.op,
                        instr.CMPindY.op, instr.SBCindY.op, instr.JMPind.op,
                        instr.LSRabs.op, instr.ASLabs.op, instr.RORabs.op,
                        instr.ROLabs.op, instr.JMPabs.op, instr.SBCzpgX.op,
                        instr.LDXabsY.op, instr.CMPabsY.op, instr.SBCabsY.op,
                        instr.ORAabsY.op, instr.ANDabsY.op, instr.EORabsY.op,
                        instr.ADCabsY.op, instr.STAabsY.op, instr.STAzpgX.op,
                        instr.LDYzpgX.op, instr.CMPzpgX.op, instr.ADCzpgX.op,
                        instr.ORAzpgX.op, instr.EORzpgX.op, instr.STYzpgX.op,
                        instr.LSRzpgX.op, instr.ASLzpgX.op, instr.RORzpgX.op,
                        instr.ROLzpgX.op, instr.INCzpgX.op, instr.DECzpgX.op,
                        instr.LDXzpgY.op, instr.STXzpgY.op, instr.LDYabsX.op,
                        instr.ORAabsX.op, instr.ANDabsX.op, instr.EORabsX.op,
                        instr.ADCabsX.op, instr.SBCabsX.op, instr.CMPabsX.op,
                        instr.ASLabsX.op, instr.RORabsX.op, instr.ROLabsX.op,
                        instr.LSRabsX.op, instr.INCabsX.op, instr.DECabsX.op => |instruction| {
                            self.data_latch = self.safeBusRead(self.program_counter);
                            self.program_counter += 1;

                            // End when branching instruction conditions are false
                            if (instruction == instr.BCSrel.op and !self.isFlagSet(.carry)) self.endInstruction();
                            if (instruction == instr.BCCrel.op and self.isFlagSet(.carry)) self.endInstruction();
                            if (instruction == instr.BEQrel.op and !self.isFlagSet(.zero)) self.endInstruction();
                            if (instruction == instr.BNErel.op and self.isFlagSet(.zero)) self.endInstruction();
                            if (instruction == instr.BVSrel.op and !self.isFlagSet(.overflow)) self.endInstruction();
                            if (instruction == instr.BVCrel.op and self.isFlagSet(.overflow)) self.endInstruction();
                            if (instruction == instr.BMIrel.op and !self.isFlagSet(.negative)) self.endInstruction();
                            if (instruction == instr.BPLrel.op and self.isFlagSet(.negative)) self.endInstruction();
                        },
                        instr.LDAimm.op, instr.LDXimm.op, instr.ANDimm.op,
                        instr.ORAimm.op, instr.EORimm.op, instr.ADCimm.op,
                        instr.LDYimm.op, instr.CPYimm.op, instr.CPXimm.op,
                        instr.SBCimm.op, instr.CMPimm.op => |instruction| {
                            switch (instruction) {
                                instr.LDXimm.op => self.loadRegister(.X, self.safeBusRead(self.program_counter)),
                                instr.LDAimm.op => self.loadRegister(.A, self.safeBusRead(self.program_counter)),
                                instr.LDYimm.op => self.loadRegister(.Y, self.safeBusRead(self.program_counter)),
                                instr.ANDimm.op => self.loadRegister(.A, self.a_register & self.safeBusRead(self.program_counter)),
                                instr.ORAimm.op => self.loadRegister(.A, self.a_register | self.safeBusRead(self.program_counter)),
                                instr.EORimm.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(self.program_counter)),
                                instr.ADCimm.op => self.addWithCarry(self.safeBusRead(self.program_counter)),
                                instr.SBCimm.op => self.addWithCarry(~self.safeBusRead(self.program_counter)),
                                instr.CPYimm.op => self.setCompareFlags(.Y, self.safeBusRead(self.program_counter)),
                                instr.CPXimm.op => self.setCompareFlags(.X, self.safeBusRead(self.program_counter)),
                                instr.CMPimm.op => self.setCompareFlags(.A, self.safeBusRead(self.program_counter)),
                                else => unreachable
                            }
                            self.program_counter += 1;
                            self.endInstruction();
                        },
                        instr.SEC.op, instr.SED.op => |instruction| {
                            self.setFlag(switch (instruction) {
                                instr.SED.op => .decimal,
                                instr.SEC.op => .carry,
                                else => unreachable
                            });
                            self.endInstruction();
                        },
                        instr.CLD.op, instr.CLC.op, instr.CLV.op,
                        instr.CLI.op => |instruction| {
                            self.clearFlag(switch (instruction) {
                                instr.CLD.op => .decimal,
                                instr.CLC.op => .carry,
                                instr.CLV.op => .overflow,
                                instr.CLI.op => .irq_disable,
                                else => unreachable
                            });
                            self.endInstruction();
                        },
                        instr.NOP.op => self.endInstruction(),
                        instr.RTS.op, instr.PHP.op, instr.PLA.op,
                        instr.PHA.op, instr.PLP.op, instr.RTI.op => {},
                        instr.INY.op, instr.INX.op, instr.DEY.op,
                        instr.DEX.op, instr.TAY.op, instr.TAX.op,
                        instr.TXA.op, instr.TYA.op, instr.TSX.op,
                        instr.TXS.op => |instruction| {
                            switch (instruction) {
                                instr.INY.op => self.loadRegister(.Y, self.y_register +% 1),
                                instr.INX.op => self.loadRegister(.X, self.x_register +% 1),
                                instr.DEY.op => self.loadRegister(.Y, self.y_register -% 1),
                                instr.DEX.op => self.loadRegister(.X, self.x_register -% 1),
                                instr.TAY.op => self.loadRegister(.Y, self.a_register),
                                instr.TAX.op => self.loadRegister(.X, self.a_register),
                                instr.TYA.op => self.loadRegister(.A, self.y_register),
                                instr.TXA.op => self.loadRegister(.A, self.x_register),
                                instr.TSX.op => self.loadRegister(.X, self.stack_pointer),
                                instr.TXS.op => self.stack_pointer = self.x_register,
                                else => unreachable
                            }
                            self.endInstruction();
                        },
                        instr.LSRacc.op, instr.RORacc.op => |instruction| {
                            const old_a = self.a_register;
                            self.loadRegister(.A, switch (instruction) {
                                instr.LSRacc.op => self.a_register >> 1,
                                instr.RORacc.op => (self.a_register >> 1) | (self.status_register << 7),
                                else => unreachable
                            });
                            if (old_a & 0b00000001 > 0) self.setFlag(.carry) else self.clearFlag(.carry);
                            self.endInstruction();
                        },
                        instr.ASLacc.op, instr.ROLacc.op => |instruction| {
                            const old_a = self.a_register;
                            self.loadRegister(.A, switch (instruction) {
                                instr.ASLacc.op => self.a_register << 1,
                                instr.ROLacc.op => (self.a_register << 1) | (self.status_register & 0b1),
                                else => unreachable
                            });
                            if (old_a & 0b10000000 > 0) self.setFlag(.carry) else self.clearFlag(.carry);
                            self.endInstruction();
                        },
                        instr.SEI.op => {
                            self.setFlag(.irq_disable);
                            self.endInstruction();
                        },
                        else => return logIllegalInstruction(self.*)
                    }
                },
                2 => {
                    switch (self.instruction_register) {
                        // All instructions that need to read the high byte of the operand
                        instr.LDAabs.op, instr.STAabs.op, instr.LDXabs.op,
                        instr.LDAabsX.op, instr.JMPind.op, instr.JMPabs.op,
                        instr.STXabs.op, instr.LDYabs.op, instr.STYabs.op,
                        instr.BITabs.op, instr.ORAabs.op, instr.ANDabs.op,
                        instr.EORabs.op, instr.ADCabs.op, instr.SBCabs.op,
                        instr.CMPabs.op, instr.CPXabs.op, instr.CPYabs.op,
                        instr.LSRabs.op, instr.ASLabs.op, instr.RORabs.op,
                        instr.ROLabs.op, instr.DECabs.op, instr.INCabs.op,
                        instr.LDAabsY.op, instr.LDXabsY.op, instr.CMPabsY.op,
                        instr.ORAabsY.op, instr.ANDabsY.op, instr.EORabsY.op,
                        instr.ADCabsY.op, instr.SBCabsY.op, instr.STAabsY.op,
                        instr.STAabsX.op, instr.LDYabsX.op, instr.ORAabsX.op,
                        instr.EORabsX.op, instr.ANDabsX.op, instr.ADCabsX.op,
                        instr.SBCabsX.op, instr.CMPabsX.op, instr.LSRabsX.op,
                        instr.ASLabsX.op, instr.RORabsX.op, instr.ROLabsX.op,
                        instr.INCabsX.op, instr.DECabsX.op => |instruction| {
                            self.data_latch |= @as(u16, self.safeBusRead(self.program_counter)) << 8;
                            self.program_counter = switch (instruction) {
                                instr.JMPabs.op => blk: {
                                    self.endInstruction();
                                    break :blk self.data_latch;
                                },
                                else => self.program_counter + 1
                            };
                        },
                        instr.LDAzpg.op, instr.LDYzpg.op, instr.LDXzpg.op,
                        instr.CMPzpg.op, instr.ORAzpg.op, instr.ANDzpg.op,
                        instr.EORzpg.op, instr.ADCzpg.op, instr.SBCzpg.op,
                        instr.CPXzpg.op, instr.CPYzpg.op => |instruction| {
                            switch (instruction) {
                                instr.LDAzpg.op => self.loadRegister(.A, self.safeBusRead(self.data_latch)),
                                instr.LDYzpg.op => self.loadRegister(.Y, self.safeBusRead(self.data_latch)),
                                instr.LDXzpg.op => self.loadRegister(.X, self.safeBusRead(self.data_latch)),
                                instr.CMPzpg.op => self.setCompareFlags(.A, self.safeBusRead(self.data_latch)),
                                instr.ORAzpg.op => self.loadRegister(.A, self.a_register | self.safeBusRead(self.data_latch)),
                                instr.ANDzpg.op => self.loadRegister(.A, self.a_register & self.safeBusRead(self.data_latch)),
                                instr.EORzpg.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(self.data_latch)),
                                instr.ADCzpg.op => self.addWithCarry(self.safeBusRead(self.data_latch)),
                                instr.SBCzpg.op => self.addWithCarry(~self.safeBusRead(self.data_latch)),
                                instr.CPXzpg.op => self.setCompareFlags(.X, self.safeBusRead(self.data_latch)),
                                instr.CPYzpg.op => self.setCompareFlags(.Y, self.safeBusRead(self.data_latch)),
                                else => unreachable
                            }
                            self.endInstruction();
                        },
                        // These last 5 cycles because of having to write back to the bus
                        instr.LSRzpg.op, instr.ASLzpg.op, instr.RORzpg.op,
                        instr.ROLzpg.op => |instruction| {
                            const value = self.safeBusRead(self.data_latch);
                            const shifted_value = switch (instruction) {
                                instr.LSRzpg.op => value >> 1,
                                instr.ASLzpg.op => value << 1,
                                instr.RORzpg.op => (value >> 1) | (self.status_register << 7),
                                instr.ROLzpg.op => (value << 1) | (self.status_register & 0b1),
                                else => unreachable
                            };
                            // Store result in high byte of data latch
                            self.data_latch |= @as(u16, shifted_value) << 8;
                            if (shifted_value == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                            if (shifted_value & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                            switch (instruction) {
                                instr.LSRzpg.op, instr.RORzpg.op => if (value & 0b00000001 != 0) self.setFlag(.carry) else self.clearFlag(.carry),
                                instr.ASLzpg.op, instr.ROLzpg.op => if (value & 0b10000000 != 0) self.setFlag(.carry) else self.clearFlag(.carry),
                                else => unreachable
                            }
                        },
                        instr.LDAzpgX.op, instr.SBCzpgX.op, instr.RTS.op,
                        instr.RTI.op, instr.ANDzpgX.op => {},
                        instr.STXzpg.op, instr.STAzpg.op, instr.STYzpg.op => |instruction| {
                            self.safeBusWrite(self.data_latch, switch (instruction) {
                                instr.STXzpg.op => self.x_register,
                                instr.STAzpg.op => self.a_register,
                                instr.STYzpg.op => self.y_register,
                                else => unreachable
                            });
                            self.endInstruction();
                        },
                        instr.BCSrel.op, instr.BCCrel.op, instr.BEQrel.op,
                        instr.BNErel.op, instr.BVSrel.op, instr.BVCrel.op,
                        instr.BPLrel.op, instr.BMIrel.op => {
                            if ((self.data_latch & 0x00FF) + (self.program_counter & 0x00FF) <= 0xFF) {
                                self.program_counter +%= self.data_latch;
                                self.endInstruction();
                            }
                        },
                        instr.BITzpg.op => {
                            self.bit(self.safeBusRead(self.data_latch));
                            self.endInstruction();
                        },
                        instr.PHP.op, instr.PHA.op => |instruction| {
                            self.safeBusWrite(0x0100 | @as(u16, self.stack_pointer), switch (instruction) {
                                instr.PHP.op => self.status_register | 0b00010000,  // bit 4 is reserved so it must be set
                                instr.PHA.op => self.a_register,
                                else => unreachable
                            });
                            self.stack_pointer -%= 1;
                            self.endInstruction();
                        },
                        instr.PLA.op, instr.PLP.op => {
                            self.stack_pointer +%= 1;
                        },
                        instr.LDAindY.op, instr.STAindY.op, instr.ORAindY.op,
                        instr.ANDindY.op, instr.EORindY.op, instr.ADCindY.op,
                        instr.CMPindY.op, instr.SBCindY.op => {
                            self.indirect_jump = self.safeBusRead(self.data_latch);
                        },
                        instr.JSRabs.op, instr.LDAindX.op, instr.STAindX.op,
                        instr.ORAindX.op, instr.ANDindX.op, instr.EORindX.op,
                        instr.ADCindX.op, instr.CMPindX.op, instr.SBCindX.op,
                        instr.INCzpg.op, instr.DECzpg.op, instr.LDYzpgX.op,
                        instr.STYzpgX.op, instr.ORAzpgX.op, instr.EORzpgX.op,
                        instr.ADCzpgX.op, instr.CMPzpgX.op, instr.STAzpgX.op,
                        instr.LSRzpgX.op, instr.ASLzpgX.op, instr.RORzpgX.op,
                        instr.ROLzpgX.op, instr.INCzpgX.op, instr.DECzpgX.op,
                        instr.LDXzpgY.op, instr.STXzpgY.op => {},
                        else => return logIllegalInstruction(self.*)
                    }
                },
                3 => {
                    switch (self.instruction_register) {
                        instr.LDAabs.op, instr.LDXabs.op, instr.LDYabs.op,
                        instr.ORAabs.op, instr.ANDabs.op, instr.EORabs.op,
                        instr.ADCabs.op, instr.SBCabs.op, instr.CMPabs.op,
                        instr.CPYabs.op, instr.CPXabs.op => |instruction| {
                            switch (instruction) {
                                instr.LDAabs.op => self.loadRegister(.A, self.safeBusRead(self.data_latch)),
                                instr.LDXabs.op => self.loadRegister(.X, self.safeBusRead(self.data_latch)),
                                instr.LDYabs.op => self.loadRegister(.Y, self.safeBusRead(self.data_latch)),
                                instr.ORAabs.op => self.loadRegister(.A, self.a_register | self.safeBusRead(self.data_latch)),
                                instr.ANDabs.op => self.loadRegister(.A, self.a_register & self.safeBusRead(self.data_latch)),
                                instr.EORabs.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(self.data_latch)),
                                instr.ADCabs.op => self.addWithCarry(self.safeBusRead(self.data_latch)),
                                instr.SBCabs.op => self.addWithCarry(~self.safeBusRead(self.data_latch)),
                                instr.CMPabs.op => self.setCompareFlags(.A, self.safeBusRead(self.data_latch)),
                                instr.CPYabs.op => self.setCompareFlags(.Y, self.safeBusRead(self.data_latch)),
                                instr.CPXabs.op => self.setCompareFlags(.X, self.safeBusRead(self.data_latch)),
                                else => unreachable,
                            }
                            self.endInstruction();
                        },
                        instr.STAabs.op, instr.STXabs.op, instr.STYabs.op => |instruction| {
                            self.safeBusWrite(self.data_latch, switch (instruction) {
                                instr.STAabs.op => self.a_register,
                                instr.STXabs.op => self.x_register,
                                instr.STYabs.op => self.y_register,
                                else => unreachable
                            });
                            self.endInstruction();
                        },
                        instr.LDAabsX.op, instr.LDYabsX.op, instr.ORAabsX.op,
                        instr.EORabsX.op, instr.ANDabsX.op, instr.ADCabsX.op,
                        instr.SBCabsX.op, instr.CMPabsX.op => |instruction| {
                            // Check if loading from another page
                            if ((self.data_latch & 0x00FF) + self.x_register > 0xFF) {} else {
                                const final_address = self.data_latch +% self.x_register;
                                switch (instruction) {
                                    instr.LDAabsX.op => self.loadRegister(.A, self.safeBusRead(final_address)),
                                    instr.LDYabsX.op => self.loadRegister(.Y, self.safeBusRead(final_address)),
                                    instr.ORAabsX.op => self.loadRegister(.A, self.a_register | self.safeBusRead(final_address)),
                                    instr.ANDabsX.op => self.loadRegister(.A, self.a_register & self.safeBusRead(final_address)),
                                    instr.EORabsX.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(final_address)),
                                    instr.ADCabsX.op => self.addWithCarry(self.safeBusRead(final_address)),
                                    instr.SBCabsX.op => self.addWithCarry(~self.safeBusRead(final_address)),
                                    instr.CMPabsX.op => self.setCompareFlags(.A, self.safeBusRead(final_address)),
                                    else => unreachable
                                }
                                self.endInstruction();
                            }
                        },
                        instr.LDAabsY.op, instr.LDXabsY.op, instr.CMPabsY.op,
                        instr.ORAabsY.op, instr.ANDabsY.op, instr.EORabsY.op,
                        instr.ADCabsY.op, instr.SBCabsY.op => |instruction| {
                            // Check if loading from another page
                            if ((self.data_latch & 0x00FF) + self.y_register > 0xFF) {} else {
                                const final_address = self.data_latch +% self.y_register;
                                switch (instruction) {
                                    instr.LDAabsY.op => self.loadRegister(.A, self.safeBusRead(final_address)),
                                    instr.LDXabsY.op => self.loadRegister(.X, self.safeBusRead(final_address)),
                                    instr.ORAabsY.op => self.loadRegister(.A, self.a_register | self.safeBusRead(final_address)),
                                    instr.ANDabsY.op => self.loadRegister(.A, self.a_register & self.safeBusRead(final_address)),
                                    instr.EORabsY.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(final_address)),
                                    instr.ADCabsY.op => self.addWithCarry(self.safeBusRead(final_address)),
                                    instr.SBCabsY.op => self.addWithCarry(~self.safeBusRead(final_address)),
                                    instr.CMPabsY.op => self.setCompareFlags(.A, self.safeBusRead(final_address)),
                                    else => unreachable,
                                }
                                self.endInstruction();
                            }
                        },
                        instr.BITabs.op => {
                            self.bit(self.safeBusRead(self.data_latch));
                            self.endInstruction();
                        },
                        instr.LDAzpgX.op, instr.LDYzpgX.op, instr.CMPzpgX.op,
                        instr.ORAzpgX.op, instr.ANDzpgX.op, instr.EORzpgX.op,
                        instr.ADCzpgX.op, instr.SBCzpgX.op, instr.STYzpgX.op,
                        instr.STAzpgX.op => |instruction| {
                            const final_address = @as(u8, @intCast(self.data_latch)) +% self.x_register;
                            switch (instruction) {
                                instr.LDAzpgX.op => self.loadRegister(.A, self.safeBusRead(final_address)),
                                instr.LDYzpgX.op => self.loadRegister(.Y, self.safeBusRead(final_address)),
                                instr.ANDzpgX.op => self.loadRegister(.A, self.a_register & self.safeBusRead(final_address)),
                                instr.ORAzpgX.op => self.loadRegister(.A, self.a_register | self.safeBusRead(final_address)),
                                instr.EORzpgX.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(final_address)),
                                instr.SBCzpgX.op => self.addWithCarry(~self.safeBusRead(final_address)),
                                instr.ADCzpgX.op => self.addWithCarry(self.safeBusRead(final_address)),
                                instr.STYzpgX.op => self.safeBusWrite(final_address, self.y_register),
                                instr.STAzpgX.op => self.safeBusWrite(final_address, self.a_register),
                                instr.CMPzpgX.op => self.setCompareFlags(.A, self.safeBusRead(final_address)),
                                else => unreachable
                            }
                            self.endInstruction();
                        },
                        instr.LDXzpgY.op, instr.STXzpgY.op => |instruction| {
                            const final_address = @as(u8, @intCast(self.data_latch)) +% self.y_register;
                            switch (instruction) {
                                instr.LDXzpgY.op => self.loadRegister(.X, self.safeBusRead(final_address)),
                                instr.STXzpgY.op => self.safeBusWrite(final_address, self.x_register),
                                else => unreachable,
                            }
                            self.endInstruction();
                        },
                        instr.RTS.op => {
                            self.stack_pointer +%= 1;
                            self.data_latch = self.safeBusRead(0x0100 | @as(u16, self.stack_pointer));
                        },
                        instr.RTI.op => {
                            self.stack_pointer +%= 1;
                            self.status_register ^= (self.safeBusRead(0x0100 | @as(u16, self.stack_pointer)) ^ self.status_register) & 0b11001111;
                        },
                        instr.JSRabs.op => {
                            self.safeBusWrite(0x0100 | @as(u16, self.stack_pointer), @as(u8, @intCast(self.program_counter >> 8)));
                            self.stack_pointer -%= 1;
                        },
                        instr.BCSrel.op, instr.BCCrel.op, instr.BEQrel.op,
                        instr.BNErel.op, instr.BVSrel.op, instr.BVCrel.op,
                        instr.BPLrel.op, instr.BMIrel.op => {
                            self.program_counter +%= self.data_latch;
                            self.endInstruction();
                        },
                        instr.PLA.op  => {
                            self.loadRegister(.A, self.safeBusRead(0x0100 | @as(u16, self.stack_pointer)));
                            self.endInstruction();
                        },
                        instr.PLP.op => {
                            self.status_register ^= (self.safeBusRead(0x0100 | @as(u16, self.stack_pointer)) ^ self.status_register) & 0b11001111;
                            self.endInstruction();
                        },
                        instr.LDAindX.op, instr.STAindX.op, instr.ORAindX.op,
                        instr.ANDindX.op, instr.EORindX.op, instr.ADCindX.op,
                        instr.CMPindX.op, instr.SBCindX.op => {
                            // Push base address into high byte of data latch
                            self.data_latch <<= 8;
                            // Fetch low byte of address only within the zeropage
                            self.data_latch |= self.safeBusRead(@as(u8, @intCast(self.data_latch >> 8)) +% self.x_register);
                        },
                        instr.LDAindY.op, instr.STAindY.op, instr.ORAindY.op,
                        instr.ANDindY.op, instr.EORindY.op, instr.ADCindY.op,
                        instr.CMPindY.op, instr.SBCindY.op => {
                            self.indirect_jump |= @as(u16, self.safeBusRead(@as(u8, @intCast(self.data_latch)) +% 1)) << 8;
                        },
                        instr.JMPind.op => {
                            // Fetch low byte of real address
                            self.indirect_jump = self.safeBusRead(self.data_latch);
                        },
                        instr.LSRzpgX.op, instr.ASLzpgX.op, instr.RORzpgX.op,
                        instr.ROLzpgX.op => |instruction| {
                            const value = self.safeBusRead(@as(u8, @intCast(self.data_latch)) +% self.x_register);
                            const shifted_value = switch (instruction) {
                                instr.LSRzpgX.op => value >> 1,
                                instr.ASLzpgX.op => value << 1,
                                instr.RORzpgX.op => (value >> 1) | (self.status_register << 7),
                                instr.ROLzpgX.op => (value << 1) | (self.status_register & 0b1),
                                else => unreachable
                            };
                            // Store result in high byte of data latch
                            self.data_latch |= @as(u16, shifted_value) << 8;
                            if (shifted_value == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                            if (shifted_value & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                            switch (instruction) {
                                instr.LSRzpgX.op, instr.RORzpgX.op => if (value & 0b00000001 != 0) self.setFlag(.carry) else self.clearFlag(.carry),
                                instr.ASLzpgX.op, instr.ROLzpgX.op => if (value & 0b10000000 != 0) self.setFlag(.carry) else self.clearFlag(.carry),
                                else => unreachable
                            }
                        },
                        instr.LSRzpg.op, instr.RORzpg.op, instr.ASLzpg.op,
                        instr.ROLzpg.op, instr.DECzpg.op, instr.INCzpg.op,
                        instr.LSRabs.op, instr.ASLabs.op, instr.RORabs.op,
                        instr.ROLabs.op, instr.INCabs.op, instr.DECabs.op,
                        instr.STAabsY.op, instr.STAabsX.op, instr.DECzpgX.op,
                        instr.INCzpgX.op, instr.LSRabsX.op, instr.ASLabsX.op,
                        instr.RORabsX.op, instr.ROLabsX.op, instr.DECabsX.op,
                        instr.INCabsX.op => {},
                        else => return logIllegalInstruction(self.*)
                    }
                },
                4 => {
                    switch (self.instruction_register) {
                        instr.LDAabsX.op, instr.LDYabsX.op, instr.ORAabsX.op,
                        instr.EORabsX.op, instr.ANDabsX.op, instr.ADCabsX.op,
                        instr.SBCabsX.op, instr.CMPabsX.op => |instruction| {
                            const final_address = self.data_latch +% self.x_register;
                            switch (instruction) {
                                instr.LDAabsX.op => self.loadRegister(.A, self.safeBusRead(final_address)),
                                instr.LDYabsX.op => self.loadRegister(.Y, self.safeBusRead(final_address)),
                                instr.ORAabsX.op => self.loadRegister(.A, self.a_register | self.safeBusRead(final_address)),
                                instr.ANDabsX.op => self.loadRegister(.A, self.a_register & self.safeBusRead(final_address)),
                                instr.EORabsX.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(final_address)),
                                instr.ADCabsX.op => self.addWithCarry(self.safeBusRead(final_address)),
                                instr.SBCabsX.op => self.addWithCarry(~self.safeBusRead(final_address)),
                                instr.CMPabsX.op => self.setCompareFlags(.A, self.safeBusRead(final_address)),
                                else => unreachable
                            }
                            self.endInstruction();
                        },
                        instr.LDAabsY.op, instr.LDXabsY.op, instr.CMPabsY.op,
                        instr.ORAabsY.op, instr.ANDabsY.op, instr.EORabsY.op,
                        instr.ADCabsY.op, instr.SBCabsY.op => |instruction| {
                            const final_address = self.data_latch +% self.y_register;
                            switch (instruction) {
                                instr.LDAabsY.op => self.loadRegister(.A, self.safeBusRead(final_address)),
                                instr.LDXabsY.op => self.loadRegister(.X, self.safeBusRead(final_address)),
                                instr.ORAabsY.op => self.loadRegister(.A, self.a_register | self.safeBusRead(final_address)),
                                instr.ANDabsY.op => self.loadRegister(.A, self.a_register & self.safeBusRead(final_address)),
                                instr.EORabsY.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(final_address)),
                                instr.ADCabsY.op => self.addWithCarry(self.safeBusRead(final_address)),
                                instr.SBCabsY.op => self.addWithCarry(~self.safeBusRead(final_address)),
                                instr.CMPabsY.op => self.setCompareFlags(.A, self.safeBusRead(final_address)),
                                else => unreachable,
                            }
                            self.endInstruction();
                        },
                        instr.RTS.op => {
                            self.stack_pointer +%= 1;
                            self.data_latch |= @as(u16, self.safeBusRead(0x0100 | @as(u16, self.stack_pointer))) << 8;
                        },
                        instr.RTI.op => {
                            self.stack_pointer +%= 1;
                            self.data_latch = self.safeBusRead(0x0100 | @as(u16, self.stack_pointer));
                        },
                        instr.JSRabs.op => {
                            self.safeBusWrite(0x0100 | @as(u16, self.stack_pointer), @intCast(0x00FF & (self.program_counter)));
                            self.stack_pointer -%= 1;
                        },
                        instr.LDAindX.op, instr.STAindX.op, instr.ORAindX.op,
                        instr.ANDindX.op, instr.EORindX.op, instr.ADCindX.op,
                        instr.CMPindX.op, instr.SBCindX.op => {
                            // High byte of data latch is the base address. Then clear high byte
                            const base_high = @as(u8, @intCast(self.data_latch >> 8)) +% self.x_register +% 1;
                            // High byte is replaced by address of final data
                            self.data_latch &= 0x00FF;
                            self.data_latch |= @as(u16, self.safeBusRead(base_high)) << 8;
                        },
                        instr.STAabsX.op, instr.STAabsY.op => |instruction| {
                            self.safeBusWrite(self.data_latch +% switch (instruction) {
                                instr.STAabsX.op => self.x_register,
                                instr.STAabsY.op => self.y_register,
                                else => unreachable
                            }, self.a_register);
                            self.endInstruction();
                        },
                        instr.LDAindY.op, instr.ORAindY.op,
                        instr.ANDindY.op, instr.EORindY.op, instr.ADCindY.op,
                        instr.CMPindY.op, instr.SBCindY.op  => |instruction| {
                            // Skip a cycle if data is in different page than the jump + Y
                            if ((self.indirect_jump & 0x00FF) + self.y_register > 0xFF) {} else {
                                const final_jump = self.indirect_jump +% self.y_register;
                                switch (instruction) {
                                    instr.LDAindY.op => self.loadRegister(.A, self.safeBusRead(final_jump)),
                                    instr.ORAindY.op => self.loadRegister(.A, self.a_register | self.safeBusRead(final_jump)),
                                    instr.ANDindY.op => self.loadRegister(.A, self.a_register & self.safeBusRead(final_jump)),
                                    instr.EORindY.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(final_jump)),
                                    instr.ADCindY.op => self.addWithCarry(self.safeBusRead(final_jump)),
                                    instr.SBCindY.op => self.addWithCarry(~self.safeBusRead(final_jump)),
                                    instr.CMPindY.op => self.setCompareFlags(.A, self.safeBusRead(final_jump)),
                                    else => unreachable
                                }
                                self.endInstruction();
                            }
                        },
                        instr.JMPind.op => {
                            // Low order byte of address pointed to by instruction must wrap arounf the PAGE
                            // Thats why i'm casting to u8 before wrapping addition.
                            // PAY CLOSER ATTENTION TO DATASHEET PLEASE!!!
                            self.indirect_jump |= @as(u16, self.safeBusRead(
                                self.data_latch & 0xFF00 | (@as(u8, @intCast(self.data_latch & 0x00FF)) +% 1)
                            )) << 8;
                            self.program_counter = self.indirect_jump;
                            self.endInstruction();
                        },
                        instr.LSRzpg.op, instr.RORzpg.op, instr.ASLzpg.op,
                        instr.ROLzpg.op => {
                            self.safeBusWrite(self.data_latch & 0xFF, @intCast(self.data_latch >> 8));
                            self.endInstruction();
                        },
                        instr.INCzpg.op => {
                            self.incrementAt(self.data_latch, false);
                            self.endInstruction();
                        },
                        instr.DECzpg.op => {
                            self.incrementAt(self.data_latch, true);
                            self.endInstruction();
                        },
                        instr.LSRabs.op, instr.ASLabs.op, instr.RORabs.op,
                        instr.ROLabs.op => |instruction| {
                            const value = self.safeBusRead(self.data_latch);
                            const shifted_value = switch (instruction) {
                                instr.LSRabs.op => value >> 1,
                                instr.ASLabs.op => value << 1,
                                instr.RORabs.op => (value >> 1) | (self.status_register << 7),
                                instr.ROLabs.op => (value << 1) | (self.status_register & 0b1),
                                else => unreachable
                            };
                            // Store result in indirect_jump (terrible for readability LMAO)
                            self.indirect_jump = shifted_value;
                            if (shifted_value == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                            if (shifted_value & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                            switch (instruction) {
                                instr.LSRabs.op, instr.RORabs.op => if (value & 0b00000001 != 0) self.setFlag(.carry) else self.clearFlag(.carry),
                                instr.ASLabs.op, instr.ROLabs.op => if (value & 0b10000000 != 0) self.setFlag(.carry) else self.clearFlag(.carry),
                                else => unreachable
                            }
                        },
                        instr.INCabs.op, instr.DECabs.op, instr.STAindY.op,
                        instr.LSRzpgX.op, instr.ASLzpgX.op, instr.RORzpgX.op,
                        instr.ROLzpgX.op, instr.DECzpgX.op, instr.INCzpgX.op,
                        instr.LSRabsX.op, instr.ASLabsX.op, instr.RORabsX.op,
                        instr.ROLabsX.op, instr.INCabsX.op, instr.DECabsX.op => {},
                        else => return logIllegalInstruction(self.*)
                    }
                },
                5 => {
                    switch (self.instruction_register) {
                        instr.RTS.op => {
                            self.program_counter = self.data_latch +% 1;
                            self.endInstruction();
                        },
                        instr.RTI.op => {
                            self.stack_pointer +%= 1;
                            self.data_latch |= @as(u16, self.safeBusRead(0x0100 | @as(u16, self.stack_pointer))) << 8;
                            self.program_counter = self.data_latch;
                            self.endInstruction();
                        },
                        instr.JSRabs.op => {
                            self.data_latch |= @as(u16, self.safeBusRead(self.program_counter)) << 8;
                            self.program_counter = self.data_latch;
                            self.endInstruction();
                        },
                        instr.LDAindX.op, instr.ORAindX.op, instr.ANDindX.op,
                        instr.EORindX.op, instr.ADCindX.op, instr.CMPindX.op,
                        instr.SBCindX.op => |instruction| {
                            switch (instruction) {
                                instr.LDAindX.op => self.loadRegister(.A, self.safeBusRead(self.data_latch)),
                                instr.ORAindX.op => self.loadRegister(.A, self.a_register | self.safeBusRead(self.data_latch)),
                                instr.ANDindX.op => self.loadRegister(.A, self.a_register & self.safeBusRead(self.data_latch)),
                                instr.EORindX.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(self.data_latch)),
                                instr.ADCindX.op => self.addWithCarry(self.safeBusRead(self.data_latch)),
                                instr.SBCindX.op => self.addWithCarry(~self.safeBusRead(self.data_latch)),
                                instr.CMPindX.op => self.setCompareFlags(.A, self.safeBusRead(self.data_latch)),
                                else => unreachable
                            }
                            self.endInstruction();
                        },
                        instr.LDAindY.op, instr.ORAindY.op, instr.ANDindY.op,
                        instr.EORindY.op, instr.ADCindY.op, instr.CMPindY.op,
                        instr.SBCindY.op => |instruction| {
                            const final_jump = self.indirect_jump +% self.y_register;
                            switch (instruction) {
                                instr.LDAindY.op => self.loadRegister(.A, self.safeBusRead(final_jump)),
                                instr.ORAindY.op => self.loadRegister(.A, self.a_register | self.safeBusRead(final_jump)),
                                instr.ANDindY.op => self.loadRegister(.A, self.a_register & self.safeBusRead(final_jump)),
                                instr.EORindY.op => self.loadRegister(.A, self.a_register ^ self.safeBusRead(final_jump)),
                                instr.ADCindY.op => self.addWithCarry(self.safeBusRead(final_jump)),
                                instr.SBCindY.op => self.addWithCarry(~self.safeBusRead(final_jump)),
                                instr.CMPindY.op => self.setCompareFlags(.A, self.safeBusRead(final_jump)),
                                else => unreachable
                            }
                            self.endInstruction();
                        },
                        instr.STAindX.op => {
                            self.safeBusWrite(self.data_latch, self.a_register);
                            self.endInstruction();
                        },
                        instr.STAindY.op => {
                            self.safeBusWrite(self.indirect_jump, self.a_register);
                            self.endInstruction();
                        },
                        instr.LSRabs.op, instr.ASLabs.op, instr.RORabs.op,
                        instr.ROLabs.op => {
                            // Shifted value was stored internally in indirect_jump, address is in data_latch
                            self.safeBusWrite(self.data_latch, @intCast(self.indirect_jump));
                            self.endInstruction();
                        },
                        instr.LSRzpgX.op, instr.ASLzpgX.op, instr.RORzpgX.op,
                        instr.ROLzpgX.op => {
                            // Value is stored in high byte of data latch, address in low byte
                            self.safeBusWrite(@as(u8, @intCast(self.data_latch & 0x00FF)) +% self.x_register, @intCast(self.data_latch >> 8));
                            self.endInstruction();
                        },
                        // TODO: This is innacurate because it reads and writes in the same cycle
                        instr.INCabs.op, instr.DECabs.op, instr.DECzpgX.op,
                        instr.INCzpgX.op => |instruction| {
                            switch (instruction) {
                                instr.INCabs.op => self.incrementAt(self.data_latch, false),
                                instr.DECabs.op => self.incrementAt(self.data_latch, true),
                                instr.INCzpgX.op => self.incrementAt(@as(u8, @intCast(self.data_latch)) +% self.x_register, false),
                                instr.DECzpgX.op => self.incrementAt(@as(u8, @intCast(self.data_latch)) +% self.x_register, true),
                                else => unreachable
                            }
                            self.endInstruction();
                        },
                        instr.LSRabsX.op, instr.ASLabsX.op, instr.RORabsX.op,
                        instr.ROLabsX.op => |instruction| {
                            const value = self.safeBusRead(self.data_latch +% self.x_register);
                            const shifted_value = switch (instruction) {
                                instr.LSRabsX.op => value >> 1,
                                instr.ASLabsX.op => value << 1,
                                instr.RORabsX.op => (value >> 1) | (self.status_register << 7),
                                instr.ROLabsX.op => (value << 1) | (self.status_register & 0b1),
                                else => unreachable
                            };
                            // Store result in indirect_jump (terrible for readability LMAO)
                            self.indirect_jump = shifted_value;
                            if (shifted_value == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                            if (shifted_value & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                            switch (instruction) {
                                instr.LSRabsX.op, instr.RORabsX.op => if (value & 0b00000001 != 0) self.setFlag(.carry) else self.clearFlag(.carry),
                                instr.ASLabsX.op, instr.ROLabsX.op => if (value & 0b10000000 != 0) self.setFlag(.carry) else self.clearFlag(.carry),
                                else => unreachable
                            }
                        },
                        instr.DECabsX.op, instr.INCabsX.op => {},
                        else => return logIllegalInstruction(self.*)
                    }
                },
                6 => {
                    switch (self.instruction_register) {
                        instr.LSRabsX.op, instr.ASLabsX.op, instr.RORabsX.op,
                        instr.ROLabsX.op => {
                            // Shifted value was stored internally in indirect_jump, address is in data_latch
                            self.safeBusWrite(self.data_latch +% self.x_register, @intCast(self.indirect_jump));
                            self.endInstruction();
                        },
                        instr.DECabsX.op, instr.INCabsX.op => |instruction| {
                            self.incrementAt(self.data_latch +% self.x_register, instruction == instr.DECabsX.op);
                            self.endInstruction();
                        },
                        else => return logIllegalInstruction(self.*)
                    }
                },
                else => return logIllegalInstruction(self.*)
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

        inline fn loadRegister(self: *Self, register: enum {A, X, Y}, with: u8) void {
            switch (register) {
                .A => {
                    self.a_register = with;
                    if (self.a_register == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                    if (self.a_register & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                },
                .X => {
                    self.x_register = with;
                    if (self.x_register == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                    if (self.x_register & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                },
                .Y => {
                    self.y_register = with;
                    if (self.y_register == 0) self.setFlag(.zero) else self.clearFlag(.zero);
                    if (self.y_register & 0b10000000 != 0) self.setFlag(.negative) else self.clearFlag(.negative);
                }
            }
        }

        fn bit(self: *Self, operand: u8) void {
            // x ^ y ^ x = y, transfer memory bits with mask
            self.status_register ^= (self.status_register ^ operand) & 0b11000000;
            if (self.a_register & operand == 0) self.setFlag(.zero) else self.clearFlag(.zero);
        }

        fn incrementAt(self: *Self, at: u16, dec: bool) void {
            const val = self.safeBusRead(at);
            if ((if (!dec) val +% 1 else val -% 1) & 0b10000000 > 0) self.setFlag(.negative) else self.clearFlag(.negative);
            if ((if (!dec) val +% 1 else val -% 1) == 0) self.setFlag(.zero) else self.clearFlag(.zero);
            self.safeBusWrite(at,  if (!dec) val +% 1 else val -% 1);
        }

        fn addWithCarry(self: *Self, value: u8) void {
            const carry = self.status_register & 0b1;
            const res = self.a_register +% value +% carry;

            // Check carry by looking at bit 8 in 16bit arithmetic
            if ((@as(u16, self.a_register) + value + carry) & 0x0100 > 0) self.setFlag(.carry) else self.clearFlag(.carry);

            // Check overflow flag, check difference in sign bit
            const value_sign_bit = value & 0b10000000;
            if (self.a_register & 0b10000000 == value_sign_bit and value_sign_bit != res & 0b10000000)
                self.setFlag(.overflow)
            else
                self.clearFlag(.overflow);

            self.loadRegister(.A, res);
        }

        fn setCompareFlags(self: *Self, register: enum {A, X, Y}, value: u8) void {
            const comp = switch (register) {
                .A => self.a_register,
                .X => self.x_register,
                .Y => self.y_register
            };
            if (comp -% value & 0b10000000 > 0) self.setFlag(.negative) else self.clearFlag(.negative);
            if (comp >= value) self.setFlag(.carry) else self.clearFlag(.carry);
            if (comp == value) self.setFlag(.zero) else self.clearFlag(.zero);
        }

        pub inline fn safeBusRead(self: Self, address: u16) u8 {
            // Call debugger breakpoint delegate instead
            if (self.debugger) |d| {
                return d.checkReadBreakpoints(address, self) catch blk: {
                    logger.warn("Unmapped read from address 0x{X:0>4}, returning 0\n", .{address});
                    break :blk 0;
                };
            }
            return self.bus.cpuRead(address) catch blk: {
                logger.warn("Unmapped read from address 0x{X:0>4}, returning 0\n", .{address});
                break :blk 0;
            };
        }

        // DO NOT USE FOR ANY EMULATION PURPOSES, AVOID SPAGHETTI!!!!
        pub inline fn safeBusReadConst(self: Self, address: u16) u8 {
            return self.bus.cpuReadConst(address) catch blk: {
                logger.warn("Unmapped read from address 0x{X:0>4}, returning 0\n", .{address});
                break :blk 0;
            };
        }

        inline fn safeBusWrite(self: *Self, address: u16, data: u8) void {
            // Call debugger breakpoint delegate instead
            if (self.debugger) |d| {
                d.checkWriteBreakpoints(address, data, self) catch {
                    logger.warn("Unmapped write to address 0x{X:0>4} with value 0x{X:0>2}\n", .{address, data});
                };
                return;
            }
            self.bus.cpuWrite(address, data) catch {
                logger.warn("Unmapped write to address 0x{X:0>4} with value 0x{X:0>2}\n", .{address, data});
            };
        }

        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print(
                "A:{X:0>2} X:{X:0>2} Y:{X:0>2} P:{X:0>2} SP:{X:0>2}",
                .{self.a_register, self.x_register, self.y_register, self.status_register, self.stack_pointer}
            );
        }

        fn logIllegalInstruction(self: Self) CPUError!void {
            // Find opcode name to dissasemble
            const instr_name = if (instr.getMetadata(self.instruction_register)) |m| m.pneumonic else "<UNKNOWN>";
            logger.err(
                "Reached illegal instruction \"{s}\"\n{any}\n",
                .{instr_name, self}
            );
            return error.IllegalInstruction;
        }
    };
}

pub const reset_vector_low_order: u16 = 0xfffc;

// Instruction pneumonics
pub const instr = struct {
    // Builds a jump table (at comptime) to get instruction metadata at runtime
    pub fn getMetadata(opcode: u8) ?*const Metadata {
        return switch (opcode) {
              inline 0...0xFF => |opc| comptime blk: {
                  @setEvalBranchQuota(100000);
                  for (@typeInfo(instr).Struct.decls) |d| {
                      const field = @field(instr, d.name);
                      if (@TypeOf(field) != Metadata) continue;
                      if (field.op == opc) break :blk &field;
                  }
                  break :blk null;
              }
        };
    }

    const Metadata = struct {
        pneumonic: []const u8,
        op: u8,
        addressing: AddressingMode,
        cycles: u3,
        len: u2,
        // page_branch: bool = false,  // Indicates 1 possible extra cycle on page crossing
        // ind_branch: bool = false,  // Indicates up to 2 possible extra cycles on different page branch
    };

    // Used for invalid op codes
    pub fn getInvalidMetadata(op: u8) *const Metadata {
        return switch (op) {
            inline else => |o| &.{
                .pneumonic = "???",
                .op = o,
                .addressing = .Unknown,
                .cycles = 0,
                .len = 1
            }
        };
    }

    // Add memory to accumulator with carry
    pub const ADCimm: Metadata = .{.pneumonic = "ADC", .op = 0x69, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const ADCzpg: Metadata = .{.pneumonic = "ADC", .op = 0x65, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const ADCzpgX: Metadata = .{.pneumonic = "ADC", .op = 0x75, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const ADCabs: Metadata = .{.pneumonic = "ADC", .op = 0x6D, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const ADCabsX: Metadata = .{.pneumonic = "ADC", .op = 0x7D, .addressing = .AbsoluteX, .cycles = 4, .len = 3};
    pub const ADCabsY: Metadata = .{.pneumonic = "ADC", .op = 0x79, .addressing = .AbsoluteY, .cycles = 4, .len = 3};
    pub const ADCindX: Metadata = .{.pneumonic = "ADC", .op = 0x61, .addressing = .IndirectX, .cycles = 6, .len = 2};
    pub const ADCindY: Metadata = .{.pneumonic = "ADC", .op = 0x71, .addressing = .IndirectY, .cycles = 5, .len = 2};

    // AND memory with accumulator
    pub const ANDimm: Metadata = .{.pneumonic = "AND", .op = 0x29, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const ANDzpg: Metadata = .{.pneumonic = "AND", .op = 0x25, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const ANDzpgX: Metadata = .{.pneumonic = "AND", .op = 0x35, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const ANDabs: Metadata = .{.pneumonic = "AND", .op = 0x2D, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const ANDabsX: Metadata = .{.pneumonic = "AND", .op = 0x3D, .addressing = .AbsoluteX, .cycles = 4, .len = 3};
    pub const ANDabsY: Metadata = .{.pneumonic = "AND", .op = 0x39, .addressing = .AbsoluteY, .cycles = 4, .len = 3};
    pub const ANDindX: Metadata = .{.pneumonic = "AND", .op = 0x21, .addressing = .IndirectX, .cycles = 6, .len = 2};
    pub const ANDindY: Metadata = .{.pneumonic = "AND", .op = 0x31, .addressing = .IndirectY, .cycles = 5, .len = 2};

    // Shift left one bit
    pub const ASLacc: Metadata = .{.pneumonic = "ASL", .op = 0x0A, .addressing = .Accumulator, .cycles = 2, .len = 1};
    pub const ASLzpg: Metadata = .{.pneumonic = "ASL", .op = 0x06, .addressing = .ZeroPage, .cycles = 5, .len = 2};
    pub const ASLzpgX: Metadata = .{.pneumonic = "ASL", .op = 0x16, .addressing = .ZeroPageX, .cycles = 6, .len = 2};
    pub const ASLabs: Metadata = .{.pneumonic = "ASL", .op = 0x0E, .addressing = .Absolute, .cycles = 6, .len = 3};
    pub const ASLabsX: Metadata = .{.pneumonic = "ASL", .op = 0x1E, .addressing = .AbsoluteX, .cycles = 7, .len = 3};

    // Branch on carry clear
    pub const BCCrel: Metadata = .{.pneumonic = "BCC", .op = 0x90, .addressing = .Relative, .cycles = 2, .len = 2};

    // Branch on carry set
    pub const BCSrel: Metadata = .{.pneumonic = "BCS", .op = 0xB0, .addressing = .Relative, .cycles = 2, .len = 2};

    // Branch on result zero
    pub const BEQrel: Metadata = .{.pneumonic = "BEQ", .op = 0xF0, .addressing = .Relative, .cycles = 2, .len = 2};

    // Test bits in memory with accumulator;
    pub const BITzpg: Metadata = .{.pneumonic = "BIT", .op = 0x24, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const BITabs: Metadata = .{.pneumonic = "BIT", .op = 0x2C, .addressing = .Absolute, .cycles = 4, .len = 3};

    // Branch on result minus
    pub const BMIrel: Metadata = .{.pneumonic = "BMI", .op = 0x30, .addressing = .Relative, .cycles = 2, .len = 2};

    // Branch on result not zero
    pub const BNErel: Metadata = .{.pneumonic = "BNE", .op = 0xD0, .addressing = .Relative, .cycles = 2, .len = 2};

    // Branch on result plus
    pub const BPLrel: Metadata = .{.pneumonic = "BPL", .op = 0x10, .addressing = .Relative, .cycles = 2, .len = 2};

    // Force break signal
    pub const BRK: Metadata = .{.pneumonic = "BRK", .op = 0x00, .addressing = .Implied, .cycles = 7, .len = 1};

    // Branch on overflow clear
    pub const BVCrel: Metadata = .{.pneumonic = "BVC", .op = 0x50, .addressing = .Relative, .cycles = 2, .len = 2};

    // Branch on overflow set
    pub const BVSrel: Metadata = .{.pneumonic = "BVS", .op = 0x70, .addressing = .Relative, .cycles = 2, .len = 2};

    // Clear carry flag
    pub const CLC: Metadata = .{.pneumonic = "CLC", .op = 0x18, .addressing = .Implied, .cycles = 2, .len = 1};

    // Clear decimal mode
    pub const CLD: Metadata = .{.pneumonic = "CLD", .op = 0xD8, .addressing = .Implied, .cycles = 2, .len = 1};

    // Clear interrupt disable bit
    pub const CLI: Metadata = .{.pneumonic = "CLI", .op = 0x58, .addressing = .Implied, .cycles = 2, .len = 1};

    // Clear overflow flag
    pub const CLV: Metadata = .{.pneumonic = "CLV", .op = 0xB8, .addressing = .Implied, .cycles = 2, .len = 1};

    // Compare memory with accumulator
    pub const CMPimm: Metadata = .{.pneumonic = "CMP", .op = 0xC9, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const CMPzpg: Metadata = .{.pneumonic = "CMP", .op = 0xC5, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const CMPzpgX: Metadata = .{.pneumonic = "CMP", .op = 0xD5, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const CMPabs: Metadata = .{.pneumonic = "CMP", .op = 0xCD, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const CMPabsX: Metadata = .{.pneumonic = "CMP", .op = 0xDD, .addressing = .AbsoluteX, .cycles = 4, .len = 3};
    pub const CMPabsY: Metadata = .{.pneumonic = "CMP", .op = 0xD9, .addressing = .AbsoluteY, .cycles = 4, .len = 3};
    pub const CMPindX: Metadata = .{.pneumonic = "CMP", .op = 0xC1, .addressing = .IndirectX, .cycles = 6, .len = 2};
    pub const CMPindY: Metadata = .{.pneumonic = "CMP", .op = 0xD1, .addressing = .IndirectY, .cycles = 5, .len = 2};

    // Compare memory and index X
    pub const CPXimm: Metadata = .{.pneumonic = "CPX", .op = 0xE0, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const CPXzpg: Metadata = .{.pneumonic = "CPX", .op = 0xE4, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const CPXabs: Metadata = .{.pneumonic = "CPX", .op = 0xEC, .addressing = .Absolute, .cycles = 4, .len = 3};

    // Compare memory and index Y
    pub const CPYimm: Metadata = .{.pneumonic = "CPY", .op = 0xC0, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const CPYzpg: Metadata = .{.pneumonic = "CPY", .op = 0xC4, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const CPYabs: Metadata = .{.pneumonic = "CPY", .op = 0xCC, .addressing = .Absolute, .cycles = 4, .len = 3};

    // Decrement memory by one
    pub const DECzpg: Metadata = .{.pneumonic = "DEC", .op = 0xC6, .addressing = .ZeroPage, .cycles = 5, .len = 2};
    pub const DECzpgX: Metadata = .{.pneumonic = "DEC", .op = 0xD6, .addressing = .ZeroPageX, .cycles = 6, .len = 2};
    pub const DECabs: Metadata = .{.pneumonic = "DEC", .op = 0xCE, .addressing = .Absolute, .cycles = 6, .len = 3};
    pub const DECabsX: Metadata = .{.pneumonic = "DEC", .op = 0xDE, .addressing = .AbsoluteX, .cycles = 7, .len = 3};

    // Decrement index X by one
    pub const DEX: Metadata = .{.pneumonic = "DEX", .op = 0xCA, .addressing = .Implied, .cycles = 2, .len = 1};

    // Decrement index Y by one;
    pub const DEY: Metadata = .{.pneumonic = "DEY", .op = 0x88, .addressing = .Implied, .cycles = 2, .len = 1};

    // ExclusiveOR memory with accumulator
    pub const EORimm: Metadata = .{.pneumonic = "EOR", .op = 0x49, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const EORzpg: Metadata = .{.pneumonic = "EOR", .op = 0x45, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const EORzpgX: Metadata = .{.pneumonic = "EOR", .op = 0x55, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const EORabs: Metadata = .{.pneumonic = "EOR", .op = 0x4D, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const EORabsX: Metadata = .{.pneumonic = "EOR", .op = 0x5D, .addressing = .AbsoluteX, .cycles = 4, .len = 3};
    pub const EORabsY: Metadata = .{.pneumonic = "EOR", .op = 0x59, .addressing = .AbsoluteY, .cycles = 4, .len = 3};
    pub const EORindX: Metadata = .{.pneumonic = "EOR", .op = 0x41, .addressing = .IndirectX, .cycles = 6, .len = 2};
    pub const EORindY: Metadata = .{.pneumonic = "EOR", .op = 0x51, .addressing = .IndirectY, .cycles = 5, .len = 2};

    // Increment memory by one;
    pub const INCzpg: Metadata = .{.pneumonic = "INC", .op = 0xE6, .addressing = .ZeroPage, .cycles = 5, .len = 2};
    pub const INCzpgX: Metadata = .{.pneumonic = "INC", .op = 0xF6, .addressing = .ZeroPageX, .cycles = 6, .len = 2};
    pub const INCabs: Metadata = .{.pneumonic = "INC", .op = 0xEE, .addressing = .Absolute, .cycles = 6, .len = 3};
    pub const INCabsX: Metadata = .{.pneumonic = "INC", .op = 0xFE, .addressing = .AbsoluteX, .cycles = 7, .len = 3};

    // Increment index X by one;
    pub const INX: Metadata = .{.pneumonic = "INX", .op = 0xE8, .addressing = .Implied, .cycles = 2, .len = 1};

    // Increment index Y by one;
    pub const INY: Metadata = .{.pneumonic = "INY", .op = 0xC8, .addressing = .Implied, .cycles = 2, .len = 1};

    // Jump to new location
    pub const JMPabs: Metadata = .{.pneumonic = "JMP", .op = 0x4C, .addressing = .Absolute, .cycles = 3, .len = 3};
    pub const JMPind: Metadata = .{.pneumonic = "JMP", .op = 0x6C, .addressing = .Indirect, .cycles = 5, .len = 3};

    // Jump to new location saving return address
    pub const JSRabs: Metadata = .{.pneumonic = "JSR", .op = 0x20, .addressing = .Absolute, .cycles = 6, .len = 3};

    // Load accumulator with memory
    pub const LDAimm: Metadata = .{.pneumonic = "LDA", .op = 0xA9, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const LDAzpg: Metadata = .{.pneumonic = "LDA", .op = 0xA5, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const LDAzpgX: Metadata = .{.pneumonic = "LDA", .op = 0xB5, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const LDAabs: Metadata = .{.pneumonic = "LDA", .op = 0xAD, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const LDAabsX: Metadata = .{.pneumonic = "LDA", .op = 0xBD, .addressing = .AbsoluteX, .cycles = 4, .len = 3};
    pub const LDAabsY: Metadata = .{.pneumonic = "LDA", .op = 0xB9, .addressing = .AbsoluteY, .cycles = 4, .len = 3};
    pub const LDAindX: Metadata = .{.pneumonic = "LDA", .op = 0xA1, .addressing = .IndirectX, .cycles = 6, .len = 2};
    pub const LDAindY: Metadata = .{.pneumonic = "LDA", .op = 0xB1, .addressing = .IndirectY, .cycles = 5, .len = 2};

    // Load index X with memory
    pub const LDXimm: Metadata = .{.pneumonic = "LDX", .op = 0xA2, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const LDXzpg: Metadata = .{.pneumonic = "LDX", .op = 0xA6, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const LDXzpgY: Metadata = .{.pneumonic = "LDX", .op = 0xB6, .addressing = .ZeroPageY, .cycles = 4, .len = 2};
    pub const LDXabs: Metadata = .{.pneumonic = "LDX", .op = 0xAE, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const LDXabsY: Metadata = .{.pneumonic = "LDX", .op = 0xBE, .addressing = .AbsoluteY, .cycles = 4, .len = 3};

    // Load index Y with memory
    pub const LDYimm: Metadata = .{.pneumonic = "LDY", .op = 0xA0, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const LDYzpg: Metadata = .{.pneumonic = "LDY", .op = 0xA4, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const LDYzpgX: Metadata = .{.pneumonic = "LDY", .op = 0xB4, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const LDYabs: Metadata = .{.pneumonic = "LDY", .op = 0xAC, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const LDYabsX: Metadata = .{.pneumonic = "LDY", .op = 0xBC, .addressing = .AbsoluteX, .cycles = 4, .len = 3};

    // Shift one bit right
    pub const LSRacc: Metadata = .{.pneumonic = "LSR", .op = 0x4A, .addressing = .Accumulator, .cycles = 2, .len = 1};
    pub const LSRzpg: Metadata = .{.pneumonic = "LSR", .op = 0x46, .addressing = .ZeroPage, .cycles = 5, .len = 2};
    pub const LSRzpgX: Metadata = .{.pneumonic = "LSR", .op = 0x56, .addressing = .ZeroPageX, .cycles = 6, .len = 2};
    pub const LSRabs: Metadata = .{.pneumonic = "LSR", .op = 0x4E, .addressing = .Absolute, .cycles = 6, .len = 3};
    pub const LSRabsX: Metadata = .{.pneumonic = "LSR", .op = 0x5E, .addressing = .AbsoluteX, .cycles = 7, .len = 3};

    // No operation
    // Adding illegal NOPs to pass tests
    pub const NOP: Metadata = .{.pneumonic = "NOP", .op = 0xEA, .addressing = .Implied, .cycles = 2, .len = 1};
    // pub const NOPimpl0: metadata = .{.pneumonic = "NOP", .op = 0x1A, .addressing = , .cycles = , .len = };
    // pub const NOPimpl1: metadata = .{.pneumonic = "NOP", .op = 0x3A, .addressing = , .cycles = , .len = };
    // pub const NOPimpl2: metadata = .{.pneumonic = "NOP", .op = 0x5A, .addressing = , .cycles = , .len = };
    // pub const NOPimpl3: metadata = .{.pneumonic = "NOP", .op = 0x7A, .addressing = , .cycles = , .len = };
    // pub const NOPimpl4: metadata = .{.pneumonic = "NOP", .op = 0xDA, .addressing = , .cycles = , .len = };
    // pub const NOPimpl5: metadata = .{.pneumonic = "NOP", .op = 0xFA, .addressing = , .cycles = , .len = };
    // pub const NOPimm0: metadata = .{.pneumonic = "NOP", .op = 0x80, .addressing = , .cycles = , .len = };
    // pub const NOPimm1: metadata = .{.pneumonic = "NOP", .op = 0x82, .addressing = , .cycles = , .len = };
    // pub const NOPimm2: metadata = .{.pneumonic = "NOP", .op = 0x89, .addressing = , .cycles = , .len = };
    // pub const NOPimm3: metadata = .{.pneumonic = "NOP", .op = 0xC2, .addressing = , .cycles = , .len = };
    // pub const NOPimm4: metadata = .{.pneumonic = "NOP", .op = 0xE2, .addressing = , .cycles = , .len = };
    // pub const NOPzpg0: metadata = .{.pneumonic = "NOP", .op = 0x04, .addressing = , .cycles = , .len = };
    // pub const NOPzpg1: metadata = .{.pneumonic = "NOP", .op = 0x44, .addressing = , .cycles = , .len = };
    // pub const NOPzpg2: metadata = .{.pneumonic = "NOP", .op = 0x64, .addressing = , .cycles = , .len = };
    // pub const NOPzpgX0: metadata = .{.pneumonic = "NOP", .op = 0x64, .addressing = , .cycles = , .len = };
    // pub const NOPzpgX1: metadata = .{.pneumonic = "NOP", .op = 0x64, .addressing = , .cycles = , .len = };
    // pub const NOPzpgX2: metadata = .{.pneumonic = "NOP", .op = 0x54, .addressing = , .cycles = , .len = };
    // pub const NOPzpgX3: metadata = .{.pneumonic = "NOP", .op = 0x74, .addressing = , .cycles = , .len = };
    // pub const NOPzpgX4: metadata = .{.pneumonic = "NOP", .op = 0xD4, .addressing = , .cycles = , .len = };
    // pub const NOPzpgX5: metadata = .{.pneumonic = "NOP", .op = 0xF4, .addressing = , .cycles = , .len = };
    // pub const NOPabs: metadata = .{.pneumonic = "NOP", .op = 0x0C, .addressing = , .cycles = , .len = };
    // pub const NOPabsX0: metadata = .{.pneumonic = "NOP", .op = 0x1C, .addressing = , .cycles = , .len = };
    // pub const NOPabsX1: metadata = .{.pneumonic = "NOP", .op = 0x3C, .addressing = , .cycles = , .len = };
    // pub const NOPabsX2: metadata = .{.pneumonic = "NOP", .op = 0x5C, .addressing = , .cycles = , .len = };
    // pub const NOPabsX3: metadata = .{.pneumonic = "NOP", .op = 0x7C, .addressing = , .cycles = , .len = };
    // pub const NOPabsX4: metadata = .{.pneumonic = "NOP", .op = 0xDC, .addressing = , .cycles = , .len = };
    // pub const NOPabsX5: metadata = .{.pneumonic = "NOP", .op = 0xFC, .addressing = , .cycles = , .len = };

    // OR memory with accumulator
    pub const ORAimm: Metadata = .{.pneumonic = "ORA", .op = 0x09, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const ORAzpg: Metadata = .{.pneumonic = "ORA", .op = 0x05, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const ORAzpgX: Metadata = .{.pneumonic = "ORA", .op = 0x15, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const ORAabs: Metadata = .{.pneumonic = "ORA", .op = 0x0D, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const ORAabsX: Metadata = .{.pneumonic = "ORA", .op = 0x1D, .addressing = .AbsoluteX, .cycles = 4, .len = 3};
    pub const ORAabsY: Metadata = .{.pneumonic = "ORA", .op = 0x19, .addressing = .AbsoluteY, .cycles = 4, .len = 3};
    pub const ORAindX: Metadata = .{.pneumonic = "ORA", .op = 0x01, .addressing = .IndirectX, .cycles = 6, .len = 2};
    pub const ORAindY: Metadata = .{.pneumonic = "ORA", .op = 0x11, .addressing = .IndirectY, .cycles = 5, .len = 2};

    // Push accumulator on stack
    pub const PHA: Metadata = .{.pneumonic = "PHA", .op = 0x48, .addressing = .Implied, .cycles = 3, .len = 1};

    // Push status on stack
    pub const PHP: Metadata = .{.pneumonic = "PHP", .op = 0x08, .addressing = .Implied, .cycles = 3, .len = 1};

    // Pull accumulator from stack
    pub const PLA: Metadata = .{.pneumonic = "PLA", .op = 0x68, .addressing = .Implied, .cycles = 4, .len = 1};

    // Pull status from stack
    pub const PLP: Metadata = .{.pneumonic = "PLP", .op = 0x28, .addressing = .Implied, .cycles = 4, .len = 1};

    // Rotate one bit left
    pub const ROLacc: Metadata = .{.pneumonic = "ROL", .op = 0x2A, .addressing = .Accumulator, .cycles = 2, .len = 1};
    pub const ROLzpg: Metadata = .{.pneumonic = "ROL", .op = 0x26, .addressing = .ZeroPage, .cycles = 5, .len = 2};
    pub const ROLzpgX: Metadata = .{.pneumonic = "ROL", .op = 0x36, .addressing = .ZeroPageX, .cycles = 6, .len = 2};
    pub const ROLabs: Metadata = .{.pneumonic = "ROL", .op = 0x2E, .addressing = .Absolute, .cycles = 6, .len = 3};
    pub const ROLabsX: Metadata = .{.pneumonic = "ROL", .op = 0x3E, .addressing = .AbsoluteX, .cycles = 7, .len = 3};

    // Rotate one bit right
    pub const RORacc: Metadata = .{.pneumonic = "ROR", .op = 0x6A, .addressing = .Accumulator, .cycles = 2, .len = 1};
    pub const RORzpg: Metadata = .{.pneumonic = "ROR", .op = 0x66, .addressing = .ZeroPage, .cycles = 5, .len = 2};
    pub const RORzpgX: Metadata = .{.pneumonic = "ROR", .op = 0x76, .addressing = .ZeroPageX, .cycles = 6, .len = 2};
    pub const RORabs: Metadata = .{.pneumonic = "ROR", .op = 0x6E, .addressing = .Absolute, .cycles = 6, .len = 3};
    pub const RORabsX: Metadata = .{.pneumonic = "ROR", .op = 0x7E, .addressing = .AbsoluteX, .cycles = 7, .len = 3};

    // Return from interrupt
    pub const RTI: Metadata = .{.pneumonic = "RTI", .op = 0x40, .addressing = .Implied, .cycles = 6, .len = 1};

    // Return from subroutine (from a JSR)
    pub const RTS: Metadata = .{.pneumonic = "RTS", .op = 0x60, .addressing = .Implied, .cycles = 6, .len = 1};

    // Subtract memory from accumulator with borrow
    pub const SBCimm: Metadata = .{.pneumonic = "SBC", .op = 0xE9, .addressing = .Immediate, .cycles = 2, .len = 2};
    pub const SBCzpg: Metadata = .{.pneumonic = "SBC", .op = 0xE5, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const SBCzpgX: Metadata = .{.pneumonic = "SBC", .op = 0xF5, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const SBCabs: Metadata = .{.pneumonic = "SBC", .op = 0xED, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const SBCabsX: Metadata = .{.pneumonic = "SBC", .op = 0xFD, .addressing = .AbsoluteX, .cycles = 4, .len = 3};
    pub const SBCabsY: Metadata = .{.pneumonic = "SBC", .op = 0xF9, .addressing = .AbsoluteY, .cycles = 4, .len = 3};
    pub const SBCindX: Metadata = .{.pneumonic = "SBC", .op = 0xE1, .addressing = .IndirectX, .cycles = 6, .len = 2};
    pub const SBCindY: Metadata = .{.pneumonic = "SBC", .op = 0xF1, .addressing = .IndirectY, .cycles = 5, .len = 2};

    // Set carry flag
    pub const SEC: Metadata = .{.pneumonic = "SEC", .op = 0x38, .addressing = .Implied, .cycles = 2, .len = 1};

    // Set decimal flag
    pub const SED: Metadata = .{.pneumonic = "SED", .op = 0xF8, .addressing = .Implied, .cycles = 2, .len = 1};

    // Set interrupt disable status
    pub const SEI: Metadata = .{.pneumonic = "SEI", .op = 0x78, .addressing = .Implied, .cycles = 2, .len = 1};

    // Store accumulator in memory
    pub const STAzpg: Metadata = .{.pneumonic = "STA", .op = 0x85, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const STAzpgX: Metadata = .{.pneumonic = "STA", .op = 0x95, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const STAabs: Metadata = .{.pneumonic = "STA", .op = 0x8D, .addressing = .Absolute, .cycles = 4, .len = 3};
    pub const STAabsX: Metadata = .{.pneumonic = "STA", .op = 0x9D, .addressing = .AbsoluteX, .cycles = 5, .len = 3};
    pub const STAabsY: Metadata = .{.pneumonic = "STA", .op = 0x99, .addressing = .AbsoluteY, .cycles = 5, .len = 3};
    pub const STAindX: Metadata = .{.pneumonic = "STA", .op = 0x81, .addressing = .IndirectX, .cycles = 6, .len = 2};
    pub const STAindY: Metadata = .{.pneumonic = "STA", .op = 0x91, .addressing = .IndirectY, .cycles = 6, .len = 2};

    // Store index X in memory
    pub const STXzpg: Metadata = .{.pneumonic = "STX", .op = 0x86, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const STXzpgY: Metadata = .{.pneumonic = "STX", .op = 0x96, .addressing = .ZeroPageY, .cycles = 4, .len = 2};
    pub const STXabs: Metadata = .{.pneumonic = "STX", .op = 0x8E, .addressing = .Absolute, .cycles = 4, .len = 3};

    // Store index Y in memory
    pub const STYzpg: Metadata = .{.pneumonic = "STY", .op = 0x84, .addressing = .ZeroPage, .cycles = 3, .len = 2};
    pub const STYzpgX: Metadata = .{.pneumonic = "STY", .op = 0x94, .addressing = .ZeroPageX, .cycles = 4, .len = 2};
    pub const STYabs: Metadata = .{.pneumonic = "STY", .op = 0x8C, .addressing = .Absolute, .cycles = 4, .len = 3};

    // Transfer accumulator to index X
    pub const TAX: Metadata = .{.pneumonic = "TAX", .op = 0xAA, .addressing = .Implied, .cycles = 2, .len = 1};

    // Transfer accumulator to index Y
    pub const TAY: Metadata = .{.pneumonic = "TAY", .op = 0xA8, .addressing = .Implied, .cycles = 2, .len = 1};

    // Transfer stack pointer to index X
    pub const TSX: Metadata = .{.pneumonic = "TSX", .op = 0xBA, .addressing = .Implied, .cycles = 2, .len = 1};

    // Transfer index X to accumulator
    pub const TXA: Metadata = .{.pneumonic = "TXA", .op = 0x8A, .addressing = .Implied, .cycles = 2, .len = 1};

    // Transfer index X to stack pointer
    pub const TXS: Metadata = .{.pneumonic = "TXS", .op = 0x9A, .addressing = .Implied, .cycles = 2, .len = 1};

    // Transfer index Y to accumulator
    pub const TYA: Metadata = .{.pneumonic = "TYA", .op = 0x98, .addressing = .Implied, .cycles = 2, .len = 1};
};

pub const StatusFlag = enum(u8) {
    carry = 1,
    zero = 1 << 1,
    irq_disable = 1 << 2,
    decimal = 1 << 3,
    brk_command = 1 << 4,
    overflow = 1 << 6,
    negative = 1 << 7
};

pub const CPUError = error {
    IllegalClockState, // When the cpu reaches a "current_instruction_cycle" that doesn't represent any possible state
    IllegalInstruction,
    NotImplemented
};

pub const AddressingMode = enum {
    Unknown,
    Accumulator,  // No addressing
    Implied,  // No addressing
    Relative,
    Immediate,
    Absolute,
    AbsoluteX,
    AbsoluteY,
    ZeroPage,
    ZeroPageX,
    ZeroPageY,
    Indirect,
    IndirectX,
    IndirectY
};

test "Full Instruction Rom (nestest.nes)" {
    const alloc = std.testing.allocator;

    // Load roms
    const nestest_rom = @embedFile("./resources/nestest.nes");
    const ref_log = @embedFile("./resources/nestest_log_reference.log");

    // Setup CPUs
    var sys = try util.NesSystem.init(alloc);
    defer sys.deinit();
    sys.cpu.program_counter = 0xC000;
    sys.cpu.stack_pointer = 0xFD;

    rom_loader.load_ines_into_bus(nestest_rom, &sys);

    // Setup writer for the execution log
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();
    const log_writer = buffer.writer();

    // Setup performance metrics
    var cycles_executed: usize = 8;
    const start_time = std.time.microTimestamp();
    defer {
        const end_time = std.time.microTimestamp();
        std.debug.print("{d} cycles executed at a speed of {d:.3} Mhz in {d} ms|", .{
            cycles_executed,
            1 / (@as(f64, @floatFromInt(end_time - start_time)) / @as(f64, @floatFromInt(cycles_executed))),
            @divTrunc(end_time - start_time, 1000)
        });
    }

    // TODO: Replace this terribleness with proper handling of BRK
    // Need to do this because the initial BRK is not implemented
    {
        const dis = try debug.dissasemble(sys.cpu, .current_instruction, .{.record_state = true});
        try log_writer.print("{X:0>4}  ", .{dis.pc});
        for (dis.op_codes) |op| {
            if (op) |o| try log_writer.print("{X:0>2} ", .{o}) else try log_writer.print("   ", .{});
        }
        try log_writer.print(" {any: <32}", .{dis});
        try log_writer.print("{any} CYC:{}\n", .{sys.cpu, 7});
    }
    while (true) : (cycles_executed += 1) {
        try sys.cpu.tick();

        if (sys.cpu.current_instruction_cycle == 0) {
            const dis = try debug.dissasemble(sys.cpu, .current_instruction, .{.record_state = true});
            try log_writer.print("{X:0>4}  ", .{dis.pc});
            for (dis.op_codes) |op| {
                if (op) |o| try log_writer.print("{X:0>2} ", .{o}) else try log_writer.print("   ", .{});
            }
            try log_writer.print(" {any: <32}", .{dis});
            try log_writer.print("{any} CYC:{}\n", .{sys.cpu, cycles_executed});
        }

        // End execution before illegal instructions start
        if (cycles_executed >= 14575) break;
    }

    // Uncomment next line to print output
    // std.debug.print("{s}", .{buffer.items});
    try std.testing.expectEqualStrings(ref_log, buffer.items);
}
