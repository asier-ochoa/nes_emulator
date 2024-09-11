const std = @import("std");

pub const logger = std.log.scoped(.Bus);

pub fn Bus(SuppliedMMap: type) type {
    return struct {
        const Self = @This();

        memory_map: MemoryMap,

        // Represents the entire address space of the CPU
        // Each member can be:
        // - A struct instance with a onRead and onWrite function
        // - A var array representing read and write memory
        // The name of the member must denote the address range in the following format:
        //    @"XXXX[Lower bound in hex uppercase]-XXXX[Upper bound in hex uppercase]"
        // TODO: Allow for struct instances to have init functions that initialize their internal state, if not present zero initialize
        pub const MemoryMap = CheckedMemoryMap(SuppliedMMap);

        // TODO: Allow for an anonymous struct to be passed that details each RAM segment's content
        // make sure to check for if the region is an array
        pub fn init() Self {
            return std.mem.zeroes(Self);
        }

        pub fn cpuRead(self: Self, address: u16) BusError!u8 {
            // Find appropriate field on memory map to call or read from
            inline for (@typeInfo(MemoryMap).Struct.fields) |field| {
                // Already checked format at compile time
                const bounds = comptime blk: {
                    break :blk extractBoundsFromMemoryRegionName(field.name) catch unreachable;
                };
                if (address >= bounds.lower and address <= bounds.upper) {
                    return switch (@typeInfo(field.type)) {
                        .Struct => @TypeOf(@field(self.memory_map, field.name)).onRead(address),
                        .Array => @field(self.memory_map, field.name)[address - bounds.lower],
                        else => 0
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
                        .Struct => @TypeOf(@field(self.memory_map, field.name)).onWrite(address, data),
                        .Array => @field(self.memory_map, field.name)[address - bounds.lower] = data,
                        else => 0
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
        // - All declarations must be struct type and have one "onRead" and one "onWrite" method
        // - Arrays must represent their bound's size
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
                            "Memory region \"" ++ field.name ++ "\" is missing an onWrite or onRead method" ++
                            " with the signatures \"fn (u16, u8) void\" and \"fn (u16) u8\""
                        ),
                        // Check array is properly sized
                        .Array => |mem_array| if (bounds.upper - bounds.lower + 1 != mem_array.len) @compileError(
                            "Memory region \"" ++ field.name ++ "\"'s size doesn't correspond to type's size, " ++
                            "correct size is " ++ std.fmt.comptimePrint("0x{X:0>4}", .{bounds.upper - bounds.lower + 1})
                        ),
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
            if (!@hasDecl(region_type, "onRead") or !@hasDecl(region_type, "onWrite")) return false;
            return @TypeOf(@field(region_type, "onRead")) == fn (u16) u8 and
            @TypeOf(@field(region_type, "onWrite")) == fn (u16, u8) void;
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
    };
}

pub const BusError = error {
    UnmappedRead,
    UnmappedWrite
};