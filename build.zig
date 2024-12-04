const std = @import("std");

pub fn build(b: *std.Build) void {
    // Main program
    const emulator_exe = b.addExecutable(.{
        .name = "nes_emulator",
        .root_source_file = b.path("src/main.zig"),
        .target = b.host,
        .optimize = b.standardOptimizeOption(.{}),
    });
    const install_exe = b.addInstallArtifact(emulator_exe, .{
        .dest_dir = .{ .override = .{ .custom = "./" } }
    });
    b.getInstallStep().dependOn(&install_exe.step);

    // Gui style artifact
    const style_file = b.addInstallFile(b.path("src/resources/dark.rgs"), "./dark.rgs");
    emulator_exe.step.dependOn(&style_file.step);
    
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
    run_artifact.cwd = b.path("./zig-out/");
    run_artifact.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run emulator");
    run_step.dependOn(&run_artifact.step);
}
