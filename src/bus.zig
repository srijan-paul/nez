const Cart = @import("./cart.zig").Cart;
const mapper_mod = @import("./mappers/mapper.zig");
const NROM = @import("./mappers/nrom.zig").NROM;
const std = @import("std");

const MapperKind = mapper_mod.MapperKind;
const Mapper = mapper_mod.Mapper;
const Allocator = std.mem.Allocator;

pub const Bus = struct {
    const Self = @This();

    readFn: *const fn (*Self, u16) u8,
    writeFn: *const fn (*Self, u16, u8) void,

    pub fn read(self: *Self, addr: u16) u8 {
        return self.readFn(self, addr);
    }

    pub fn write(self: *Self, addr: u16, val: u8) void {
        return self.writeFn(self, addr, val);
    }
};

/// A dummy bus used for testing with the ProcessorTests test suite.
pub const TestBus = struct {
    const Self = @This();
    mem: [std.math.maxInt(u16) + 1]u8 = .{0} ** (std.math.maxInt(u16) + 1),
    bus: Bus,

    fn write(i_bus: *Bus, addr: u16, val: u8) void {
        var self: *Self = @fieldParentPtr(Self, "bus", i_bus);
        self.mem[addr] = val;
    }

    fn read(i_bus: *Bus, addr: u16) u8 {
        var self: *Self = @fieldParentPtr(Self, "bus", i_bus);
        return self.mem[addr];
    }

    pub fn new() TestBus {
        return .{
            .bus = .{
                .readFn = read,
                .writeFn = write,
            },
        };
    }
};

pub const NESBus = struct {
    const Self = @This();
    const w_ram_size = 0x800;
    bus: Bus,
    mapper: *Mapper,
    cart: *Cart,
    allocator: Allocator,

    // holds a reference to the CPU's 0x800 bytes of RAM.
    ram: [w_ram_size]u8 = .{0} ** w_ram_size,

    fn busRead(i_bus: *Bus, addr: u16) u8 {
        var self = @fieldParentPtr(Self, "bus", i_bus);
        if (addr < 0x2000) {
            return self.ram[addr % w_ram_size];
        }

        return self.mapper.read(addr);
    }

    fn busWrite(i_bus: *Bus, addr: u16, val: u8) void {
        var self = @fieldParentPtr(Self, "bus", i_bus);
        if (addr < 0x2000) {
            self.ram[addr % w_ram_size] = val;
        }

        self.mapper.write(addr, val);
    }

    fn createMapper(allocator: Allocator, cart: *Cart) !*Mapper {
        var kind = cart.header.getMapper();
        if (kind == .nrom) {
            var nrom = try allocator.create(NROM);
            nrom.* = NROM.init(cart);
            return &nrom.mapper;
        }
        unreachable;
    }

    /// Create a new Bus.
    pub fn init(allocator: Allocator, cart: *Cart) !Self {
        return .{
            .allocator = allocator,
            .cart = cart,
            .bus = .{
                .readFn = busRead,
                .writeFn = busWrite,
            },
            .mapper = try createMapper(allocator, cart),
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.cart.header.getMapper()) {
            .nrom => {
                var nrom = @fieldParentPtr(NROM, "mapper", self.mapper);
                self.allocator.destroy(nrom);
            },
        }
    }
};
