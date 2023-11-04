const Cart = @import("./cart.zig").Cart;
const mapper_mod = @import("./mappers/mapper.zig");
const NROM = @import("./mappers/nrom.zig").NROM;
const std = @import("std");

const MapperKind = mapper_mod.MapperKind;
const Mapper = mapper_mod.Mapper;
const Allocator = std.heap.Allocator;

pub const Bus = struct {
    const Self = @This();

    readFn: *const fn (*Self, u16) u8,
    writeFn: *const fn (*Self, u16, u8) void,
    resolveAddrFn: *const fn (self: *Self, addr: u16) *u8,

    pub fn resolveAddr(self: *Self, addr: u16) *u8 {
        return self.resolveAddrFn(self, addr);
    }

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

    fn resolveAddr(i_bus: *Bus, addr: u16) *u8 {
        var self: *Self = @fieldParentPtr(Self, "bus", i_bus);
        return &self.mem[addr];
    }

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
                .resolveAddrFn = resolveAddr,
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

    fn resolveAddr(i_bus: *Bus, addr: u16) *u8 {
        var self = @fieldParentPtr(Self, "bus", i_bus);
        if (addr < 0x2000) {
            return &self.ram[addr % w_ram_size];
        }

        return self.mapper.resolveAddr(addr);
    }

    fn busRead(i_bus: *Bus, addr: u16) u8 {
        var mem = resolveAddr(i_bus, addr);
        return mem.*;
    }

    fn busWrite(i_bus: *Bus, addr: u16, val: u8) void {
        var mem = resolveAddr(i_bus, addr);
        mem.* = val;
    }

    fn createMapper(cart: *Cart, allocator: Allocator, kind: MapperKind) !*Mapper {
        if (kind == .nrom) {
            var nrom = try allocator.create(NROM);
            nrom.init(cart);
            return &nrom.mapper;
        }
        unreachable;
    }

    /// Create a new Bus.
    /// i_mapper is non-owned pointer.
    pub fn new(allocator: Allocator, cart: *Cart) Self {
        var mapper: *Mapper = undefined;
        switch (cart.mapperKind) {
            .nrom => {
                var nrom = try allocator.create(NROM);
                nrom.init(cart);
                mapper = &nrom.mapper;
            },
            else => unreachable,
        }

        return .{
            .allocator = allocator,
            .cart = cart,
            .bus = .{
                .resolveAddrFn = resolveAddr,
                .readFn = busRead,
                .writeFn = busWrite,
            },
            .mapper = mapper,
        };
    }

    pub fn deinit(_: *Self) void {
        // TODO;
    }
};
