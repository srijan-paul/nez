const Cart = @import("./cart.zig").Cart;
const mapper_mod = @import("./mappers/mapper.zig");
const NROM = @import("./mappers/nrom.zig").NROM;
const MMC1 = @import("./mappers/mmc1.zig").MMC1;
const UxROM = @import("./mappers/UxROM.zig");
const std = @import("std");
const Gamepad = @import("./gamepad.zig");

const PPU = @import("./ppu/ppu.zig").PPU;
const MapperKind = mapper_mod.MapperKind;
const Mapper = mapper_mod.Mapper;
const Allocator = std.mem.Allocator;

pub const Bus = struct {
    const Self = @This();

    readFn: *const fn (*Self, u16) u8,
    writeFn: *const fn (*Self, u16, u8) void,
    nmiPendingFn: *const fn (*Self) bool,

    pub fn read(self: *Self, addr: u16) u8 {
        return self.readFn(self, addr);
    }

    pub fn write(self: *Self, addr: u16, val: u8) void {
        return self.writeFn(self, addr, val);
    }

    /// returns `true` if there is an NMI waiting to be serviced by the CPU.
    /// NOTE: when called, it will reset the NMI pending flag to `false`.
    pub fn isNMIPending(self: *Self) bool {
        return self.nmiPendingFn(self);
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

    fn isNMIPending(_: *Bus) bool {
        return false;
    }

    pub fn new() TestBus {
        return .{
            .bus = .{
                .readFn = read,
                .writeFn = write,
                .nmiPendingFn = isNMIPending,
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
    controller: *Gamepad,

    // holds a reference to the CPU's 0x800 bytes of RAM.
    ram: [w_ram_size]u8 = .{0} ** w_ram_size,

    fn busRead(i_bus: *Bus, addr: u16) u8 {
        var self = @fieldParentPtr(Self, "bus", i_bus);

        return switch (addr) {
            0...0x1FFF => self.ram[addr % w_ram_size],
            0x2000...0x3FFF => self.ppu.readRegister(addr),
            0x4000...0x4015 => 0, // TODO
            0x4016 => self.controller.read(),
            0x4017...0x401F => 0, // TODO
            else => self.mapper.read(addr),
        };
    }

    fn busWrite(i_bus: *Bus, addr: u16, val: u8) void {
        var self = @fieldParentPtr(Self, "bus", i_bus);
        switch (addr) {
            0...0x1FFF => self.ram[addr % w_ram_size] = val,
            0x2000...0x3FFF => self.ppu.writeRegister(addr, val),
            0x4000...0x4017 => {
                if (addr == 0x4014) {
                    self.ppu.writeOAMDMA(val);
                    return;
                }

                if (addr == 0x4016) {
                    self.controller.write(val);
                    return;
                }
                // TODO: APU.
            },
            0x4018...0x401F => {}, // TODO
            else => self.mapper.write(addr, val),
        }
    }

    /// Create a mapper based on the cart's configuration.
    fn createMapper(allocator: Allocator, cart: *Cart, ppu: *PPU) !*Mapper {
        var kind = cart.header.getMapper();
        switch (kind) {
            .nrom => {
                var nrom = try allocator.create(NROM);
                nrom.* = NROM.init(cart, ppu);
                return &nrom.mapper;
            },

            .mmc1 => {
                var mmc1 = try allocator.create(MMC1);
                mmc1.* = MMC1.init(cart, ppu);
                return &mmc1.mapper;
            },

            .UxROM => {
                var uxROM = try allocator.create(UxROM);
                uxROM.* = UxROM.init(cart, ppu);
                return &uxROM.mapper;
            },
        }
    }

    /// returns `true` if there is an NMI waiting to be serviced by the CPU.
    /// resets the NMI flag when called.
    fn isNMIPending(i_bus: *Bus) bool {
        var self = @fieldParentPtr(Self, "bus", i_bus);
        var nmi = self.ppu.is_nmi_pending;
        self.ppu.is_nmi_pending = false;
        return nmi;
    }

    /// Create a new Bus.
    /// Both `cart` and `ppu` are non-owning pointers.
    pub fn init(allocator: Allocator, cart: *Cart, ppu: *PPU, controller: *Gamepad) !Self {
        return .{
            .allocator = allocator,
            .cart = cart,
            .ppu = ppu,
            .bus = .{
                .readFn = busRead,
                .writeFn = busWrite,
                .nmiPendingFn = isNMIPending,
            },
            .mapper = try createMapper(allocator, cart, ppu),
            .controller = controller,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.cart.header.getMapper()) {
            .nrom => {
                var nrom = @fieldParentPtr(NROM, "mapper", self.mapper);
                self.allocator.destroy(nrom);
            },

            .mmc1 => {
                var mmc1 = @fieldParentPtr(MMC1, "mapper", self.mapper);
                self.allocator.destroy(mmc1);
            },

            .UxROM => {
                var uxROM = @fieldParentPtr(UxROM, "mapper", self.mapper);
                self.allocator.destroy(uxROM);
            },
        }
    }
};
