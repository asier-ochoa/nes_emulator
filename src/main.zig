const std = @import("std");
const CPU = @import("6502.zig");
const Bus = @import("bus.zig");
const util = @import("util.zig");
const rom_loader = @import("rom_loader.zig");
const debug = @import("debugger.zig");
const rl = @import("raylib");

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
    rl.initWindow(800, 600, "NES Emulator");
    defer rl.closeWindow();

    rl.setTargetFPS(rl.getMonitorRefreshRate(0));

    while (!rl.windowShouldClose()) {
        {  // Frame drawing scope
            rl.clearBackground(rl.Color.dark_blue);
            rl.beginDrawing();
            rl.drawFPS(0, 0);
            defer rl.endDrawing();
        }
    }
}

pub fn oldMain() !void {
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
        bus.printPage(0x0) catch unreachable;

        const end_time = std.time.microTimestamp();
        std.debug.print("{d} cycles executed at a speed of {d:.3} Mhz in {d} ms\n", .{
            cycles_executed,
            // f = 1 / (avg period := time (us) / cycles)
            1 / (@as(f64, @floatFromInt(end_time - start_time.?)) / @as(f64, @floatFromInt(cycles_executed))) ,
            @divFloor(end_time - start_time.?, 1000)
        });
    }

    // ------ CPU execution ---------------
    cycles_executed += 8;
    {
        const dis = try debug.dissasemble(cpu, .current_instruction, .{.record_state = true});
        std.debug.print("{X:0>4}  ", .{dis.pc});
        for (dis.op_codes) |op| {
            if (op) |o| std.debug.print("{X:0>2} ", .{o}) else std.debug.print("   ", .{});
        }
        std.debug.print(" {any: <32}", .{dis});
        std.debug.print("{any} CYC:{}\n", .{cpu, cycles_executed});
    }
    while (true) : (cycles_executed += 1) {
        try cpu.tick();

        // Continue ticking the cpu
        if (continous_run) {
            if (start_time == null) start_time = std.time.microTimestamp();
            switch (cpu.current_instruction_cycle) {
                0 => {
                    const dis = try debug.dissasemble(cpu, .current_instruction, .{.record_state = true});
                    std.debug.print("{X:0>4}  ", .{dis.pc});
                    for (dis.op_codes) |op| {
                        if (op) |o| std.debug.print("{X:0>2} ", .{o}) else std.debug.print("   ", .{});
                    }
                    std.debug.print(" {any: <32}", .{dis});
                    std.debug.print("{any} CYC:{}\n", .{cpu, cycles_executed});
                },
                // 1 => {
                //     if (cpu.current_instruction_cycle == 1) {
                //         std.debug.print("C{} - {any}\n", .{cycles_executed + 7, cpu});
                //     }
                // },
                else => {}
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
        // std.debug.print("CPU State: {any}\n", .{cpu});
    }
}

test "debug main" {
    try main();
}