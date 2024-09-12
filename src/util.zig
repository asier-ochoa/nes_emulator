const std = @import("std");
const Bus = @import("bus.zig");
const CPU = @import("6502.zig");

// Reset vector is placed at 0x0200 so as to be outside the zeropage and stack
pub const TestBus = Bus.Bus(struct {
    @"0000-EFFF": [0xf000]u8,
    // Gap to allow for error handling tests
    @"FFFC-FFFF": [0x0004]u8 = [_]u8{0x02, 0x00, 0, 0}
});

pub const TestCPU = CPU.CPU(TestBus);