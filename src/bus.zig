const Mapper = @import("./mappers/mapper.zig").Mapper;
const std = @import("std");

pub const Bus = struct {
    const Self = @This();
    const ram_size = 0x800;

    _ram: [ram_size]u8 = .{0} ** ram_size,

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

/// a dummy bus used for testing with the ProcessorTests test suite.
pub const TestBus = struct {
    const Self = @This();
    mem: [std.math.maxInt(u16)]u8 = .{0} ** std.math.maxInt(u16),
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

pub const NesBus = struct {
    const Self = @This();
    mapper: Mapper,
    ram: []u8,

    /// Create a new Bus.
    /// Both `i_mapper` and `ram` are non-owned pointers,
    /// and are not managed by the Bus.
    pub fn new(i_mapper: *Mapper, ram: []u8) Self {
        return .{
            .mapper = i_mapper,
            .ram = ram,
        };
    }

    pub fn read(self: *const Self, addr: u16) u8 {
        if (addr < 0x2000) {
            return self.ram[addr % 0x800];
        }

        return self.mapper.read(addr);
    }
};
