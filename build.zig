const std = @import("std");

pub fn build(b: *std.Build) void {
    // Main program
    const emulator_exe = b.addExecutable(.{
        .name = "nes_emulator",
        .root_source_file = b.path("src/main.zig"),
        .target = b.host
    });
    b.installArtifact(emulator_exe);

    // Declare raylib
    const raylib_dep = b.dependency("raylib", .{
        .target = b.host,
        .optimize = .ReleaseFast,
    });
    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // Declare dependency to raylib
    emulator_exe.linkLibrary(raylib_artifact);
    emulator_exe.root_module.addImport("raylib", raylib);
    emulator_exe.root_module.addImport("raygui", raygui);

    // Build script steps
    const run_artifact = b.addRunArtifact(emulator_exe);
    const run_step = b.step("run", "Run emulator");
    run_step.dependOn(&run_artifact.step);
}
