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

// Initializes a cpu and a bus with PC at 0 and first couple of addresses filled
pub fn initCPUForTest(cpu: *TestCPU, bus: *TestBus, memory: []const u8) TestError!void {
    cpu.* = TestCPU.init(bus);
    bus.* = TestBus.init();
    if (memory.len > 0) {
        if (memory.len > bus.memory_map.@"0000-EFFF".len) return TestError.ProvidedMemoryTooLarge
        else @memcpy(bus.memory_map.@"0000-EFFF"[0..memory.len], memory);
    }
}

pub fn emptyMem(comptime n: u32) [n]u8 {
    return [_]u8{0} ** n;
}

pub fn leftPadMem(comptime mem: anytype, comptime n: u32) [n]u8 {
    return mem ++ ([_]u8{0} ** (n - mem.len));
}

const TestError = error {
    ProvidedMemoryTooLarge
};