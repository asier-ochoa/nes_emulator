const std = @import("std");
const CPU = @import("6502.zig");
const Bus = @import("bus.zig");
const util = @import("util.zig");

fn readTest(comptime address: u16, bus: anytype) !void {
    std.debug.print(
        "Reading from bus at " ++
        std.fmt.comptimePrint("0x{X:0>4}", .{address}) ++
        " returns: {d}\n", .{try bus.cpuRead(address)});
}

pub const std_options = std.Options {
    .log_level = .debug
};

pub fn main() !void {
    // Set up CPU
    const NesMemoryMap = struct {
        @"0000-AFFF": [0xb000]u8,
        @"B000-BFFE": struct {
            pub fn onRead(_: u16) u8 {
                return 20;
            }
            pub fn onWrite(address: u16, data: u8) void {
                std.debug.print("I have been called to write on address 0x{X:0<4} with value {}\n", .{address, data});
            }
        },
        @"FFFC-FFFF": [0x0004]u8,
    };
    var bus = Bus.Bus(NesMemoryMap).init();
    var cpu = CPU.CPU(@TypeOf(bus)).init(&bus);
    cpu.status_register = 0b00010011;

    std.debug.print("{b:0>8}\n", .{@intFromEnum(CPU.StatusFlag.zero)});
    std.debug.print("{b:0>8}\n", .{@intFromEnum(CPU.StatusFlag.brk_command)});
    std.debug.print("{b:0>8}\n", .{@intFromEnum(CPU.StatusFlag.carry)});
    if (cpu.isFlagSet(.carry)) {
        std.debug.print("Carry flag is set\n", .{});
    }
    if (cpu.isFlagSet(.brk_command)) {
        std.debug.print("Brk flag is set\n", .{});
    }
    if (cpu.isFlagSet(.zero)) {
        std.debug.print("Zero flag is set\n", .{});
    }
    
    // Testing bus writes
    std.debug.print("\n----Testing bus writes----\n", .{});
    try bus.cpuWrite(0x0000, 55);
    try bus.cpuWrite(0x0001, 40);
    try readTest(0x0000, bus);
    try readTest(0x0001, bus);

    try bus.cpuWrite(0xBFF0, 68);
    try readTest(0xBFF0, bus);

    // Testing cpu reset
    std.debug.print("\n----Testing cpu reset----\n", .{});
    try bus.cpuWrite(CPU.reset_vector_low_order, 0x4A);
    try bus.cpuWrite(CPU.reset_vector_low_order + 1, 0x68);
    cpu.reset();
    for (1..7) |i| {
        try cpu.tick();
        if (i == 5) std.debug.print("PC after reading low order reset vector: 0x{X:0>4}\n", .{cpu.program_counter});
    }
    std.debug.print("PC after reset: 0x{X:0>4}\n", .{cpu.program_counter});
}

test "Bus Array Write" {
    var bus = util.TestBus.init();
    try bus.cpuWrite(0x0000, 0x42);
    try bus.cpuWrite(0x0002, 0x61);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x42, 0, 0x61}, bus.memory_map.@"0000-EFFF"[0..3]);
}

test "Bus Array Write Unmapped Error" {
    var bus = util.TestBus.init();
    try std.testing.expectError(Bus.BusError.UnmappedWrite, bus.cpuWrite(0xf000, 0));
}

test "Bus Array Read" {
    var bus = util.TestBus.init();
    @memcpy(bus.memory_map.@"0000-EFFF"[0..3], &[_]u8{0x01, 0x20, 0});
    try std.testing.expectEqual(0x01, try bus.cpuRead(0x0000));
    try std.testing.expectEqual(0x20, try bus.cpuRead(0x0001));
    try std.testing.expectEqual(0, try bus.cpuRead(0x0003));
}

test "Bus Array Read Unmapped Error" {
    var bus = util.TestBus.init();
    try std.testing.expectError(Bus.BusError.UnmappedRead, bus.cpuRead(0xf000));
}

test "CPU LDAabs" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        &([_]u8{CPU.instr.LDAabs, 0x00, 0x02} ++ [_]u8{0} ** 0x01fd ++ [_]u8{0x64})
    );
    // Execute instruction
    for (0..4) |_| {
        try cpu.tick();
    }
    try std.testing.expectEqual(util.TestCPU {
        .a_register = 0x64,
        .instruction_register = CPU.instr.LDAabs,
        .program_counter = 0x0003,
        .data_latch = 0x0200,
        .bus = &bus
    }, cpu);
}

test "CPU STAabs" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        &[_]u8{CPU.instr.STAabs, 0x00, 0x02}
    );
    cpu.a_register = 0x64;
    // Execute instruction
    for (0..4) |_| {
        try cpu.tick();
    }
    try std.testing.expectEqual(0x64, bus.memory_map.@"0000-EFFF"[0x0200]);
}

test "CPU LDAzpg" {
    var bus: util.TestBus = undefined;
    var cpu: util.TestCPU = undefined;
    try util.initCPUForTest(&cpu, &bus,
        &([_]u8{CPU.instr.LDAzpg, 0xFE} ++ [_]u8{0} ** 0xFC ++ [_]u8{0x64})
    );
    for (0..3) |_| {
        try cpu.tick();
    }
    try std.testing.expectEqual(util.TestCPU {
        .a_register = 0x64,
        .instruction_register = CPU.instr.LDAzpg,
        .program_counter = 0x0002,
        .data_latch = 0x00fe,
        .bus = &bus
    }, cpu);
}