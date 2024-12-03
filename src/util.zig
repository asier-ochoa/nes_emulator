const std = @import("std");
const Bus = @import("bus.zig");
const CPU = @import("6502.zig");
const debug = @import("debugger.zig");
const rl = @import("raylib");
const PPU = @import("ppu.zig");

pub const NesSystem = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    cpu: CPU.CPU(NesBus),
    bus: *NesBus,  // Have to do this because of circular dependencies and such
    ppu: PPU,
    debugger: debug.Debugger,

    cycles_executed: usize = 0,
    instructions_executed: usize = 0,
    last_instr_address: u16 = 0,

    running: bool = false,  // Determines if cpu should run

    pub fn init(alloc: std.mem.Allocator) !Self {
        const heap_bus = try alloc.create(NesBus);
        var ret: Self = .{
            .alloc = alloc,
            .cpu = CPU.CPU(@TypeOf(heap_bus.*)).init(heap_bus),
            .ppu = PPU.init(),
            .bus = heap_bus,
            .debugger = debug.Debugger.init(alloc)
        };

        ret.bus.memory_map.@"2000-3FFF".ppu = &ret.ppu;
        // Set ram to 0
        @memset(&ret.bus.memory_map.@"0000-07FF", 0);
        return ret;
    }

    pub fn deinit(self: Self) void {
        self.alloc.destroy(self.bus);
    }

    // Executes system cycles for a certain amount of millisenconds since frame start
    // All time values must be given in millis
    pub fn runFullSpeedFor(self: *Self, start_time: i64, time: i64) void {
        const end_time = start_time + time;
        while (std.time.milliTimestamp() < end_time) {
            self.tick();
        }
    }

    // Executes system cycles at a certain frequency in hz
    // Minimum tick rate will always be tied to framerate
    pub fn runAt(self: *Self, freq: i64) void {
        const fps = rl.getFPS();
        if (fps > 0) {
            var cycles_per_frame = @divTrunc(freq, rl.getFPS());
            cycles_per_frame += if (cycles_per_frame == 0) 1 else 0;
            for (0..@intCast(cycles_per_frame)) |_| {
                self.tick();
            }
        }
    }

    // Ticks a single clock cycle
    // PPU is base clock
    // CPU is every 3 ticks
    pub fn tick(self: *Self) void {
        if (self.running) {
            self.ppu.tick();
            if (@mod(self.cycles_executed, 3) == 0) {
                self.cpu.tick() catch {
                    std.debug.print("Last Instruction was at address {X:0<4}\n", .{self.last_instr_address});
                    @panic("Reached illegal instruction");
                };
            }
            self.cycles_executed += 1;
            // Count instruction when on fetch cycle
            if (self.cpu.current_instruction_cycle == 0) {
                self.instructions_executed += 1;
                self.last_instr_address = self.cpu.program_counter;
            }
        }
    }

    pub fn tickInstruction() void {

    }
};

// Reset vector is placed at 0x0200 so as to be outside the zeropage and stack
pub const TestBus = Bus.Bus(struct {
    @"0000-EFFF": [0xf000]u8,
    // Gap to allow for error handling tests
    @"FFFC-FFFF": [0x0004]u8 = .{0x02, 0x00, 0, 0}
});

pub const NesBus = Bus.Bus(struct {
    @"0000-07FF": [0x0800]u8,  // Main RAM
    @"0800-1FFF": struct {  // Mirrors of main RAM
        const Self = @This();
        pub fn onRead(_: *Self, address: u16, mmap: anytype) u8 {
            return mmap.@"0000-07FF"[@mod(address, 0x0800)];
        }
        pub fn onReadConst(_: Self, address: u16, mmap: anytype) u8 {
            return mmap.@"0000-07FF"[@mod(address, 0x0800)];
        }
        pub fn onWrite(_: *Self, address: u16, data: u8, mmap: anytype) void {
            mmap.@"0000-07FF"[@mod(address, 0x0800)] = data;
        }
    },
    @"2000-3FFF": struct {  // PPU registers (8 bytes) + mirrors
        ppu: *PPU = undefined,
        const Self = @This();
        pub fn onRead(self: *Self, address: u16, _: anytype) u8 {
            const inner_address = @mod(address, 8) + 0x2000;
            return self.ppu.getFieldFromAddr(inner_address).?.*;
        }
        pub fn onReadConst(self: Self, address: u16, _: anytype) u8 {
            const inner_address = @mod(address, 8) + 0x2000;
            return self.ppu.getFieldFromAddr(inner_address).?.*;
        }
        pub fn onWrite(self: *Self, address: u16, value: u8, _: anytype) void {
            const inner_address = @mod(address, 8) + 0x2000;
            self.ppu.getFieldFromAddr(inner_address).?.* = value;
        }
    },
    @"4000-4017": struct {  // APU and I/O registers TODO: implement
        const Self = @This();
        pub fn onRead(_: *Self, _: u16, _: anytype) u8 {
            return 0;
        }
        pub fn onReadConst(_: Self, _: u16, _: anytype) u8 {
            return 0;
        }
        pub fn onWrite(_: *Self, _: u16, _: u8, _: anytype) void {}
    },
    @"4018-401F": struct {  // Unused unless test
        const Self = @This();
        pub fn onRead(_: *Self, _: u16, _: anytype) u8 {
            return 0;
        }
        pub fn onReadConst(_: Self, _: u16, _: anytype) u8 {
            return 0;
        }
        pub fn onWrite(_: *Self, _: u16, _: u8, _: anytype) void {}
    },
    @"4020-FFFF": struct {  // Unmapped, used for cartriges TODO: figure out how to design the mappers
        const Self = @This();
        rom: [0x8000]u8,
        pub fn onRead(self: *Self, address: u16, _: anytype) u8 {
            return if (address >= 0x8000) self.rom[address - 0x8000] else 0;
        }
        pub fn onReadConst(self: Self, address: u16, _: anytype) u8 {
            return if (address >= 0x8000) self.rom[address - 0x8000] else 0;
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

test "NesSystem Sanity check" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();
    var sys = try NesSystem.init(alloc);
    sys.bus.memory_map.@"0000-07FF"[0] = 0x20;
    try std.testing.expectEqual(0x20, sys.cpu.safeBusRead(0x0000));
}