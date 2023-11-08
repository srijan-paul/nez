const Cart = @import("./cart.zig").Cart;
const mapper_mod = @import("./mappers/mapper.zig");
const NROM = @import("./mappers/nrom.zig").NROM;
const std = @import("std");

const PPU = @import("./ppu/ppu.zig").PPU;
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
    ppu: *PPU,
    cart: *Cart,
    allocator: Allocator,

    // holds a reference to the CPU's 0x800 bytes of RAM.
    ram: [w_ram_size]u8 = .{0} ** w_ram_size,

    const MMIO_addr_start: u16 = 0x2000;
    const MMIO_addr_end: u16 = 0x4000;

    fn busRead(i_bus: *Bus, addr: u16) u8 {
        var self = @fieldParentPtr(Self, "bus", i_bus);
        if (addr < 0x2000) {
            return self.ram[addr % w_ram_size];
        }

        // addresses between 0x2000 and 0x4000 are MMIO for the PPU
        if (addr < MMIO_addr_end) {
            // TODO: simulate open bus behavior.
            // TOOD: simulate address latch reset when reading PPUSTATUS.
            var mmio_addr = (addr - MMIO_addr_start) % 8;
            switch (mmio_addr) {
                0 => return @bitCast(self.ppu.ppu_ctrl),
                1 => return @bitCast(self.ppu.ppu_mask),
                2 => return @bitCast(self.ppu.ppu_status),
                // TODO: OAMADDR, OAMDATA, PPUSCROLL
                3...6 => unreachable,
                7 => return self.ppu.readFromPPUAddr(),
                else => unreachable,
            }
        }

        return self.mapper.read(addr);
    }

    fn busWrite(i_bus: *Bus, addr: u16, val: u8) void {
        var self = @fieldParentPtr(Self, "bus", i_bus);
        if (addr < 0x2000) {
            self.ram[addr % w_ram_size] = val;
        }

        // address between 0x2000 and 0x4000 are MMIO for the PPU.
        if (addr < MMIO_addr_end) {
            var mmio_addr = (addr - MMIO_addr_start) % 8;
            switch (mmio_addr) {
                0 => self.ppu.ppu_ctrl = @bitCast(val),
                1 => self.ppu.ppu_mask = @bitCast(val),
                2 => self.ppu.ppu_status = @bitCast(val),
                // TODO: OAMADDR, OAMDATA, PPUSCROLL
                3...5 => unreachable,
                6 => self.ppu.setPPUAddr(val),
                7 => self.ppu.writeToPPUAddr(val),
                else => unreachable,
            }
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
    /// Both `cart` and `ppu` are non-owning pointers.
    pub fn init(allocator: Allocator, cart: *Cart, ppu: *PPU) !Self {
        return .{
            .allocator = allocator,
            .cart = cart,
            .ppu = ppu,
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
