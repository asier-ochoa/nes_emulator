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
    const TestMemoryMap = struct {
        @"0000-AFFF": [0xb000]u8,
        @"B000-BFFE": struct {
            const Self = @This();
            pub fn onRead(_: *Self, _: u16, _: anytype) u8 {
                return 20;
            }
            pub fn onWrite(_: *Self, address: u16, data: u8, _: anytype) void {
                std.debug.print("I have been called to write on address 0x{X:0<4} with value {}\n", .{address, data});
            }
        },
        @"FFFC-FFFF": [0x0004]u8,
    };
    var bus = Bus.Bus(TestMemoryMap).init();
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
    try readTest(0x0000, &bus);
    try readTest(0x0001, &bus);

    try bus.cpuWrite(0xBFF0, 68);
    try readTest(0xBFF0, &bus);

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
