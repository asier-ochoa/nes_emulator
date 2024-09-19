const std = @import("std");
const Bus = @import("bus.zig");
const CPU = @import("6502.zig");

// Reset vector is placed at 0x0200 so as to be outside the zeropage and stack
pub const TestBus = Bus.Bus(struct {
    @"0000-EFFF": [0xf000]u8,
    // Gap to allow for error handling tests
    @"FFFC-FFFF": [0x0004]u8 = [_]u8{0x02, 0x00, 0, 0}
});

pub const NesBus = Bus.Bus(struct {
    @"0000-07FF": [0x0800]u8,  // Main RAM
    @"0800-1FFF": struct {  // Mirrors of main RAM
        const Self = @This();
        pub fn onRead(_: *Self, address: u16, mmap: anytype) u8 {
            return mmap.@"0000-07FF"[@mod(address, 0x0800)];
        }
        pub fn onWrite(_: *Self, address: u16, data: u8, mmap: anytype) void {
            mmap.@"0000-07FF"[@mod(address, 0x0800)] = data;
        }
    },
    @"2000-3FFF": struct {  // PPU registers (8 bytes) + mirrors TODO: implement
        const Self = @This();
        pub fn onRead(_: *Self, _: u16, _: anytype) u8 {
            return 0;
        }
        pub fn onWrite(_: *Self, _: u16, _: u8, _: anytype) void {}
    },
    @"4000-4017": struct {  // APU and I/O registers TODO: implement
        const Self = @This();
        pub fn onRead(_: *Self, _: u16, _: anytype) u8 {
            return 0;
        }
        pub fn onWrite(_: *Self, _: u16, _: u8, _: anytype) void {}
    },
    @"4018-401F": struct {  // Unused unless test
        const Self = @This();
        pub fn onRead(_: *Self, _: u16, _: anytype) u8 {
            return 0;
        }
        pub fn onWrite(_: *Self, _: u16, _: u8, _: anytype) void {}
    },
    @"4020-FFFF": struct {  // Unmapped, used for cartriges TODO: figure out how to design the mappers
        const Self = @This();
        rom: [0x4000]u8,
        pub fn onRead(self: *Self, address: u16, _: anytype) u8 {
            return if (address >= 0x8000) self.rom[@mod(address - 0x8000, 0x4000)] else 0;
        }
        pub fn onWrite(_: *Self, _: u16, _: u8, _: anytype) void {}
    }
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

test "NesBus Wrapping read" {
    var bus = NesBus.init();
    try bus.cpuWrite(0x0000, 0xF5);
    try std.testing.expectEqual(0xF5, try bus.cpuRead(0x0800));
    
    try bus.cpuWrite(0x0400 + 0x0800, 0xF4);
    try std.testing.expectEqual(0xF4, try bus.cpuRead(0x0400));
}