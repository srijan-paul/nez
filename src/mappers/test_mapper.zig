const std = @import("std");
const Mapper = @import("./mapper.zig").Mapper;
const Cart = @import("../cart.zig").Cart;

/// A test mapper that directly maps any input into PRG ROM banks.
/// This is only useful for testing the CPU.
pub const TestMapper = struct {
    const Self = @This();
    mapper: Mapper,
    // All 64k of ROM is reserved.
    // Nothing is mapped to PPU.
    // Nothing is mirrored.
    memory: [0xffff]u8,

    fn read(i_mapper: *Mapper, addr: u16) u8 {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        return self.memory[addr];
    }

    fn write(i_mapper: *Mapper, addr: u16, value: u8) void {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        self.memory[addr] = value;
    }

    pub fn new() Self {
        return .{
            .mapper = Mapper.new(read, write),
        };
    }
};
