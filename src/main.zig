const std = @import("std");
const CPU = @import("6502.zig");
const Bus = @import("bus.zig");
const util = @import("util.zig");
const rom_loader = @import("rom_loader.zig");
const debug = @import("debugger.zig");
const rl = @import("raylib");
const rg = @import("raygui");
const gui = @import("gui.zig");

pub const std_options = std.Options {
    .log_level = .debug
};

pub fn main() !void {
    // Initialize application allocator
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Initialize emulation system
    var sys = try util.NesSystem.init(alloc);
    sys.bus.memory_map.@"2000-3FFF".ppu = &sys.ppu;
    defer sys.deinit();

    // Initialize window
    rl.initWindow(1280, 720, "NES Emulator");
    defer rl.closeWindow();
    rl.setTargetFPS(rl.getMonitorRefreshRate(0));
    rg.guiLoadStyle("./dark.rgs");

    // Initialize GUI state
    var state = try gui.GuiState.init(alloc);
    defer state.deinit(alloc);

    // Variables used for performance counters
    var last_cycle_count: u64 = 0;
    var last_cpu_cycle_count: u64 = 0;

    // Initialize debugger but don't attach
    // var debugger = debug.Debugger.init(alloc);

    // TODO: Replace with proper rom loading method controlled by gui
    // Load nestest
    const file = try std.fs.cwd().openFile("./../src/resources/nestest.nes", .{});
    defer file.close();
    const file_data = try alloc.alloc(u8, (try file.metadata()).size());
    defer _ = alloc.free(file_data);
    _ = try file.readAll(file_data);
    rom_loader.load_ines_into_bus(file_data, &sys);

    var text_buffer: [256]u8 = .{0} ** 256;
    while (!rl.windowShouldClose()) {
        // Update system state
        sys.running = state.cpu_status.cpu_running;

        // Run CPU
        sys.runAt(1_789_773 * 3);
        // sys.runFullSpeedFor(std.time.milliTimestamp(), @intFromFloat(rl.getFrameTime() * 0.96 * 1000));
        // sys.runAt(4000);

        // Compute emulator frequency
        const freq = (sys.cycles_executed - last_cycle_count) * @as(u32, @intCast(rl.getFPS()));
        const cpu_freq = (sys.cpu_cycles_executed - last_cpu_cycle_count) * @as(u32, @intCast(rl.getFPS()));

        gui.windowDraggingLogic(&state);

        {  // Frame drawing scope
            rl.beginDrawing();
            defer rl.endDrawing();
            rl.clearBackground(rl.Color.dark_blue);

            // Draw perf counters
            @memset(&text_buffer, 0);
            rl.drawText(@ptrCast(try std.fmt.bufPrint(&text_buffer, "System: {} hz", .{freq})), 0, 65, 20, rl.Color.black);
            @memset(&text_buffer, 0);
            rl.drawText(@ptrCast(try std.fmt.bufPrint(&text_buffer, "CPU: {} hz", .{cpu_freq})), 0, 85, 20, rl.Color.black);
            {  // Ui Drawing scope
                gui.menuBar(&state);
                state.ptrn_tbl.draw(&gui.window_bounds.ptrn_tbl, &sys);
                state.debugger.draw(&state.cpu_status, &sys, alloc);
                state.cpu_status.draw(&sys, sys.cpu_cycles_executed, sys.instructions_executed);
                state.game.draw(&sys);
            }
        }

        last_cycle_count = sys.cycles_executed;
        last_cpu_cycle_count = sys.cpu_cycles_executed;
    }
}
