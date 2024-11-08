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
    defer sys.deinit();
    sys.cpu.program_counter = 0xC000;
    sys.cpu.stack_pointer = 0xFD;

    // Initialize window
    rl.initWindow(1280, 720, "NES Emulator");
    defer rl.closeWindow();
    rl.setTargetFPS(rl.getMonitorRefreshRate(0));
    rg.guiLoadStyle("./dark.rgs");

    // Initialize GUI state
    var state = try gui.GuiState.init(alloc);
    defer state.deinit(alloc);

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

    while (!rl.windowShouldClose()) {
        // Update system state
        sys.running = state.cpu_status.cpu_running;

        // Run CPU
        sys.runAt(60);

        gui.windowDraggingLogic(&state);

        {  // Frame drawing scope
            rl.beginDrawing();
            defer rl.endDrawing();
            rl.clearBackground(rl.Color.dark_blue);

            {  // Ui Drawing scope
                gui.menuBar(&state);
                state.ptrn_tbl.draw(&gui.window_bounds.ptrn_tbl, &sys);
                state.debugger.draw(&state.cpu_status, &sys, alloc);
                state.cpu_status.draw(@TypeOf(sys.cpu), &sys.cpu, sys.cycles_executed, sys.instructions_executed);

                rl.drawFPS(0, 60);
            }
        }
    }
}
