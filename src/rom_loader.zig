const std = @import("std");
const util = @import("util.zig");

// Loads INES files into bus by copying according to mapper data.
pub fn load_ines_into_bus(data: []const u8, sys: *util.NesSystem) void {
    const header = data[0..16];
    const prg_size = @as(u32, header[4]) * 16384;
    const chr_size = @as(u32, header[5]) * 8192;
    _ = chr_size;
    const mapper = header[6] >> 4;
    _ = mapper;

    std.mem.copyForwards(u8, &sys.bus.memory_map.@"4020-FFFF".rom, data[16..16 + prg_size]);
}