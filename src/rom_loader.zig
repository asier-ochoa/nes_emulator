const std = @import("std");
const util = @import("util.zig");

// Loads INES files into bus by copying according to mapper data.
pub fn load_ines_into_bus(data: []const u8, sys: *util.NesSystem) void {
    const header = data[0..16];
    const prg_size = @as(u32, header[4]) * 16384;
    const chr_size = @as(u32, header[5]) * 8192;
    const mapper = header[6] >> 4;

    std.debug.print(
        \\INES file stats:
        \\  - Mapper ID: {}
        \\  - PRG Banks: {} | Size: {} bytes
        \\  - CHR Banks: {} | Size: {} bytes | Starts at: 0x{X:0>4}
        \\  - Mirroring type: {c}
        \\
        , .{
            mapper,
            @divTrunc(prg_size, 16384),
            prg_size,
            @divTrunc(chr_size, 8192),
            chr_size,
            16 + prg_size + sys.ppu.pattern_tables[0].len,
            @as(u8 , if (header[6] & 1 != 0) 'v' else 'h'),
        },
    );

    // Copy prg to cpu rom address space
    std.mem.copyForwards(u8, &sys.bus.memory_map.@"4020-FFFF".rom, data[16..16 + prg_size]);
    // Copy same region twice if prg doesn't cover full 32 kb
    if (prg_size <= 16384) {
        std.mem.copyForwards(u8, sys.bus.memory_map.@"4020-FFFF".rom[prg_size..], data[16..16 + prg_size]);
    }

    // Copy chr to ppu mem
    std.mem.copyForwards(u8, &sys.ppu.pattern_tables[0], data[16 + prg_size..16 + prg_size + sys.ppu.pattern_tables[0].len]);
    std.mem.copyForwards(u8, &sys.ppu.pattern_tables[1], data[16 + prg_size + sys.ppu.pattern_tables[0].len..16 + prg_size + sys.ppu.pattern_tables[1].len * 2]);

    // Set mirroring type
    sys.ppu.nametable_mirroring = if (header[6] & 1 != 0) .v else .h;
}