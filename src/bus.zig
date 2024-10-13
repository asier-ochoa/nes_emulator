const std = @import("std");
const util = @import("util.zig");

pub const logger = std.log.scoped(.Bus);

pub fn Bus(SuppliedMMap: type) type {
    return struct {
        const Self = @This();

        memory_map: MemoryMap,

        // Represents the entire address space of the CPU
        // Each member can be:
        // - A struct instance with a onRead, onWrite and onReadConst function
        //  - If the struct contains a "bus"
        // - A var array representing read and write memory
        // The name of the member must denote the address range in the following format:
        //    @"XXXX[Lower bound in hex uppercase]-XXXX[Upper bound in hex uppercase]"
        // TODO: Allow for struct instances to have init functions that initialize their internal state, if not present zero initialize
        pub const MemoryMap = CheckedMemoryMap(SuppliedMMap);

        pub fn init() Self {
            return std.mem.zeroes(Self);
        }

        pub fn cpuRead(self: *Self, address: u16) BusError!u8 {
            // Find appropriate field on memory map to call or read from
            inline for (@typeInfo(MemoryMap).Struct.fields) |field| {
                // Already checked format at compile time
                const bounds = comptime blk: {
                    break :blk extractBoundsFromMemoryRegionName(field.name) catch unreachable;
                };
                if (address >= bounds.lower and address <= bounds.upper) {
                    return switch (@typeInfo(field.type)) {
                        .Struct => @field(self.memory_map, field.name).onRead(address, &self.memory_map),
                        .Array => @field(self.memory_map, field.name)[address - bounds.lower],
                        else => unreachable
                    };
                }
            }
            logger.warn("Illegal read at 0x{X:0>4}\n", .{address});
            return BusError.UnmappedRead;
        }

        // Reads from bus but guarantees onRead methods won't have side effects
        pub fn cpuReadConst(self: Self, address: u16) BusError!u8 {
            inline for (@typeInfo(MemoryMap).Struct.fields) |field| {
                const bounds = comptime blk: {
                    break :blk extractBoundsFromMemoryRegionName(field.name) catch unreachable;
                };
                if (address >= bounds.lower and address <= bounds.upper) {
                    return switch (@typeInfo(field.type)) {
                        .Struct => @field(self.memory_map, field.name).onReadConst(address, @as(*const MemoryMap, &self.memory_map)),
                        .Array => @field(self.memory_map, field.name)[address - bounds.lower],
                        else => unreachable
                    };
                }
            }
            logger.warn("Illegal read at 0x{X:0>4}\n", .{address});
            return BusError.UnmappedRead;
        }

        pub fn cpuWrite(self: *Self, address: u16, data: u8) BusError!void {
            // Find appropriate field on memory map to call or write to
            inline for (@typeInfo(MemoryMap).Struct.fields) |field| {
                // Already checked format at compile time
                const bounds = comptime blk: {
                    break :blk extractBoundsFromMemoryRegionName(field.name) catch unreachable;
                };
                if (address >= bounds.lower and address <= bounds.upper) {
                    switch (@typeInfo(field.type)) {
                        .Struct => @field(self.memory_map, field.name).onWrite(address, data, &self.memory_map),
                        .Array => @field(self.memory_map, field.name)[address - bounds.lower] = data,
                        else => unreachable
                    }
                    return;
                }
            }
            logger.warn("Illegal write to 0x{X:0>4} with value 0x{X:0>2}\n", .{address, data});
            return BusError.UnmappedWrite;
        }

        // A memory map must:
        // - Not have any overlapping memory sections
        // - Field name must follow the given format
        // - Upper bound > lower bound
        // - Have all fields that are of struct type, have one "onRead", one "onWrite", and one "onReadConst" method
        //      - 1st argument must be a pointer to @This(), const for the const variant
        //      - 2nd argument must be a u16 address
        //      - last address must be anytype and holds a pointer to the mmap, const for the const variant
        //      - 3rd argument for onWrite must be a u8 data value to be written
        //      - return type for onRead must be a u8 data value to be read
        // - Arrays must represent their bound's size
        // - Array's child type must be u8
        fn CheckedMemoryMap(T: type) type {
            comptime {
                for (@typeInfo(T).Struct.fields) |field| {
                    // Check for correct number format XXXX-XXXX, hex and caps
                    if (!memoryRegionNameFormatCheck(field.name)) @compileError(
                        "Invalid field name \"" ++ field.name ++ "\", use format @\"XXXX-XXXX\" in uppercase hex"
                    );
                    // Check for region overlap
                    var payload_string: []const u8 = undefined;
                    if (!memoryRegionOverlapCheck(T, field.name, .{.err_payload = &payload_string})) @compileError(
                        "Invalid memory map layout: " ++ payload_string
                    );
                    // Check upper bound > lower bound
                    const bounds = extractBoundsFromMemoryRegionName(field.name) catch unreachable;
                    if (bounds.lower > bounds.upper) @compileError(
                        "Invalid memory map layout: Bounds \"" ++ field.name ++ "\"are inverted"
                    );
                    switch (@typeInfo(field.type)) {
                        // Check struct can respond to reads and writes
                        .Struct => if (!memoryRegionReadableAndWriteableCheck(field.type)) @compileError(
                            "Memory region \"" ++ field.name ++ "\" is missing an onWrite, onRead or onReadConst method" ++
                            " with the signatures \"fn (@This(), u16, u8, anytype) void\" and \"fn (@This(), u16, anytype) u8\""
                        ),
                        // Check array is properly sized
                        .Array => |mem_array| {
                            if (bounds.upper - bounds.lower + 1 != mem_array.len) @compileError(
                            "Memory region \"" ++ field.name ++ "\"'s size doesn't correspond to type's size, " ++
                                "correct size is " ++ std.fmt.comptimePrint("0x{X:0>4}", .{bounds.upper - bounds.lower + 1})
                            );
                            // Check child type is u8
                            if (mem_array.child != u8) @compileError(
                                "Memory region \"" ++ field.name ++ "\"'s array child type must be u8"
                            );
                        },
                        else => @compileError("Invalid type for memory region \"" ++ field.name ++ "\", must be a struct or array")
                    }
                }
                return T;
            }
        }

        fn memoryRegionNameFormatCheck(name: []const u8) bool {
            comptime {
                if (name.len != 9) return false;
                for (name, 0..) |c, i| {
                    if (i == 4) {
                        if (c != '-') return false;
                    } else {
                        switch (c) {
                            '0'...'9', 'A'...'F' => {continue;},
                            else => {return false;}
                        }
                    }
                }
                return true;
            }
        }

        // errorPayload can optionally have an err_payload field of type []const u8
        fn memoryRegionOverlapCheck(MMap: type, region_name: []const u8, errorPayload: ?struct {err_payload: *[] const u8}) bool {
            comptime {
                const checked_field_bounds = extractBoundsFromMemoryRegionName(region_name) catch unreachable;
                for (@typeInfo(MMap).Struct.fields) |field| {
                    // Skip if compairing same field
                    if (std.mem.eql(u8, region_name, field.name)) continue;
                    const bounds = extractBoundsFromMemoryRegionName(field.name) catch unreachable;
                    if (
                    (checked_field_bounds.lower <= bounds.upper and checked_field_bounds.lower >= bounds.lower) or
                        (checked_field_bounds.upper >= bounds.lower and checked_field_bounds.upper <= bounds.upper)
                    ) {
                        if (errorPayload) |*payload| {
                            payload.err_payload.* = std.fmt.comptimePrint(
                                "Collision between regions \"0x{X:0>4}-0x{X:0>4}\" and \"0x{X:0>4}-{X:0>4}\"",
                                .{checked_field_bounds.lower, checked_field_bounds.upper, bounds.lower, bounds.upper}
                            );
                        }
                        return false;
                    }
                }
            }
            return true;
        }

        fn memoryRegionReadableAndWriteableCheck(region_type: type) bool {
            if (!@hasDecl(region_type, "onRead") or !@hasDecl(region_type, "onWrite") or !@hasDecl(region_type, "onReadConst")) return false;
            return @TypeOf(@field(region_type, "onRead")) == fn (*region_type, u16, anytype) u8 and
            @TypeOf(@field(region_type, "onWrite")) == fn (*region_type, u16, u8, anytype) void and
            @TypeOf(@field(region_type, "onReadConst")) == fn (region_type, u16, anytype) u8;
        }

        const MemoryError = error {
            RegionNameFormatInvalid
        };

        const MemoryRegionBounds = struct {
            upper: u16,
            lower: u16,
        };

        inline fn extractBoundsFromMemoryRegionName(name: []const u8) MemoryError!MemoryRegionBounds {
            if (!memoryRegionNameFormatCheck(name)) return MemoryError.RegionNameFormatInvalid;
            return .{
                .lower = std.fmt.parseInt(u16, name[0..4], 16) catch unreachable,
                .upper = std.fmt.parseInt(u16, name[5..9], 16) catch unreachable
            };
        }

        // TODO: return string of unmapped regions
        fn getUnmappedRegions() []const u8 {
            return "";
        }

        pub fn printPage(self: *Self, address: u16) !void {
            const start = address & 0xFF00;  // Set address to start of page
            var i = start;
            while (i < start + 0xFF + 1) : (i += 1) {
                if (i == address) std.debug.print("[", .{});
                std.debug.print(
                    "{X:0>2}",
                    .{try self.cpuRead(i)}
                );
                if (i == address) std.debug.print("] ", .{}) else std.debug.print(" ", .{});
                if (@mod(i + 1, 16) == 0) std.debug.print("\n", .{});
            }
        }
    };
}

pub const BusError = error {
    UnmappedRead,
    UnmappedWrite
};

test "Bus Array Write" {
    var bus = util.TestBus.init();
    try bus.cpuWrite(0x0000, 0x42);
    try bus.cpuWrite(0x0002, 0x61);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x42, 0, 0x61}, bus.memory_map.@"0000-EFFF"[0..3]);
}

test "Bus Array Write Unmapped Error" {
    var bus = util.TestBus.init();
    try std.testing.expectError(BusError.UnmappedWrite, bus.cpuWrite(0xf000, 0));
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
    try std.testing.expectError(BusError.UnmappedRead, bus.cpuRead(0xf000));
}