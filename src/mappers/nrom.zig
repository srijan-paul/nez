const std = @import("std");
const Mapper = @import("./mapper.zig").Mapper;
const Cart = @import("../cart.zig").Cart;
const CPU = @import("../cpu.zig").CPU;
const PPU = @import("../ppu/ppu.zig").PPU;

/// The iNES format assigns mapper 0 to the NROM board,
/// which is the most common board type.
/// This was used by most early NES games.
pub const NROM = struct {
    const Self = @This();
    cart: *Cart,
    ppu: *PPU,
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
            const resolved_addr = if (addr >= prg_rom_bank_2.start)
                addr - prg_rom_bank_2.start
            else
                addr - prg_rom_bank_1.start;

            return &self.cart.prg_rom[resolved_addr];
        }

        // No mirroring needed when there are 2 banks.
        return &self.cart.prg_rom[addr - prg_rom_bank_1.start];
    }

    /// Perform a read issued by the CPU
    fn nromRead(i_mapper: *Mapper, addr: u16) u8 {
        const self: *Self = @fieldParentPtr("mapper", i_mapper);
        const ptr = self.resolveAddr(addr);
        return ptr.*;
    }

    /// Perform a write issued by the CPU
    fn nromWrite(i_mapper: *Mapper, addr: u16, value: u8) void {
        const self: *Self = @fieldParentPtr("mapper", i_mapper);
        const ptr = self.resolveAddr(addr);
        ptr.* = value;
    }

    /// Read a byte from the cartridge's CHR ROM.
    fn ppuRead(i_mapper: *Mapper, addr: u16) u8 {
        const self: *Self = @fieldParentPtr("mapper", i_mapper);
        if (addr < 0x2000) return self.cart.chr_rom[addr];
        return self.ppu.readRAM(addr);
    }

    /// Write a byte to PPU memory.
    fn ppuWrite(i_mapper: *Mapper, addr: u16, value: u8) void {
        const self: *Self = @fieldParentPtr("mapper", i_mapper);
        // CHR ROM is read-only.
        if (addr < 0x2000) return;
        self.ppu.writeRAM(addr, value);
    }

    /// Create a new mapper that operates on `cart`.
    pub fn init(cart: *Cart, ppu: *PPU) Self {
        return .{
            .cart = cart,
            .ppu = ppu,
            .mapper = Mapper.init(nromRead, nromWrite, ppuRead, ppuWrite),
        };
    }
};
