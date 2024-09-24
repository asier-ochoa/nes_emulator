const std = @import("std");
const CPU = @import("6502.zig");
const Bus = @import("bus.zig");
const util = @import("util.zig");
const rom_loader = @import("rom_loader.zig");

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
    const stdout = std.io.getStdIn().reader();
    var buf = [_]u8{0, 0};

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    var bus = util.NesBus.init();
    var cpu = CPU.CPU(@TypeOf(bus)).init(&bus);
    cpu.program_counter = 0xC000;
    cpu.stack_pointer = 0xFD;

    // Load ines rom
    const file = try std.fs.cwd().openFile("src/resources/nestest.nes", .{});
    defer file.close();
    const data = try alloc.alloc(u8, (try file.metadata()).size());
    defer alloc.free(data);

    _ = try file.readAll(data);

    rom_loader.load_ines_into_bus(data, &bus);

    var continous_run = false;

    // Get timestamp to compute speed of execution
    var cycles_executed: i64 = 0;
    var start_time: ?i64 = null;
    errdefer {
        bus.printPage(0x0000) catch unreachable;

        const end_time = std.time.microTimestamp();
        std.debug.print("{d} cycles executed at a speed of {d:.3} Mhz in {d} ms\n", .{
            cycles_executed,
            // f = 1 / (avg period := time (us) / cycles)
            1 / (@as(f64, @floatFromInt(end_time - start_time.?)) / @as(f64, @floatFromInt(cycles_executed))) ,
            @divFloor(end_time - start_time.?, 1000)
        });
    }

    std.debug.print("C{} - {any}\n", .{cycles_executed + 7, cpu});
    while (true) : (cycles_executed += 1) {
        try cpu.tick();

        // Continue ticking the cpu
        if (continous_run) {
            if (start_time == null) start_time = std.time.microTimestamp();
            if (cpu.current_instruction_cycle == 1) {
                std.debug.print("C{} - {any}\n", .{cycles_executed + 7, cpu});
            }
            continue;
        }

        _ = try stdout.read(&buf);
        switch (buf[0]) {
            'p' => try bus.printPage(cpu.program_counter),
            'r' => continous_run = true,
            '\n' => {},
            else => {},
        }
        std.debug.print("CPU State: {any}\n", .{cpu});
    }
}

fn oldMain() !void {
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

test "debug main" {
    try main();
}