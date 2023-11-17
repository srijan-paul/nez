const std = @import("std");
const Mapper = @import("./mapper.zig").Mapper;
const Cart = @import("../cart.zig").Cart;
const CPU = @import("../cpu.zig").CPU;

/// The iNES format assigns mapper 0 to the NROM board,
/// which is the most common board type.
/// This was used by most early NES games.
pub const NROM = struct {
    const Self = @This();
    cart: *Cart,
    mapper: Mapper,

    const prg_ram = .{ .start = 0x6000, .end = 0x7FFF };
    const prg_rom_bank_1 = .{ .start = 0x8000, .end = 0xBFFF };
    const prg_rom_bank_2 = .{ .start = 0xC000, .end = 0xFFFF };

    /// Given a 16-bit address, return a pointer to the corresponding byte
    /// in cartridge memory.
    fn resolveAddr(self: *Self, addr: u16) *u8 {
        if (!(addr >= prg_ram.start and addr <= prg_rom_bank_2.end)) {
            std.debug.panic("Bad address to NROM: {x}", .{addr});
        }

        // PRG RAM
        if (addr < prg_rom_bank_1.start) {
            return &self.cart.prg_ram[addr - prg_ram.start];
        }

        // PRG ROM
        if (self.cart.header.prg_rom_banks == 1) {
            // If there is only 1 bank, it is mirrored into both banks 1 and two.
            // To avoid maintaining two identical memory regions,
            // I route all read/writes to the second bank into the first one.
            var resolved_addr = if (addr >= prg_rom_bank_2.start)
                addr - prg_rom_bank_2.start
            else
                addr - prg_rom_bank_1.start;

            return &self.cart.prg_rom[resolved_addr];
        }

        // No mirroring needed when there are 2 banks.
        return &self.cart.prg_rom[addr - prg_rom_bank_1.start];
    }

    fn nromRead(i_mapper: *Mapper, addr: u16) u8 {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        var ptr = self.resolveAddr(addr);
        return ptr.*;
    }

    fn nromWrite(i_mapper: *Mapper, addr: u16, value: u8) void {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        var ptr = self.resolveAddr(addr);
        ptr.* = value;
    }

    /// Create a new mapper that operates on `cart`.
    pub fn init(cart: *Cart) Self {
        return .{
            .cart = cart,
            .mapper = Mapper.init(nromRead, nromWrite),
        };
    }
};
