const std = @import("std");
const Mapper = @import("./mapper.zig").Mapper;
const Cart = @import("../cart.zig").Cart;
const CPU = @import("../cpu.zig").CPU;
const PPU = @import("../ppu/ppu.zig").PPU;

/// 5 bit Control register.
const FlagsControl = packed struct {
    /// Determines the mirroring mode.
    /// 0: one screen, lower bank; 1: one screen, upper bank.
    /// 2: vertical; 3: horizontal
    mirror_mode: u2 = 0,
    /// TODO: understand how this works.
    prg_rom_bank_mode: u2 = 3,
    /// 1: Switch two 8kb banks, 0: Switch 8KB banks at a time.
    chr_rom_is_4kb: bool = 0,
};

/// The iNES format assigns mapper 0 to the NROM board,
/// which is the most common board type.
/// This was used by most early NES games.
pub const MMC1 = struct {
    const Self = @This();
    cart: *Cart,
    ppu: *PPU,
    mapper: Mapper,

    /// This shift register is used to determine the currently selected bank.
    /// When the LSB is set to '1', the SR is considered to be "full".
    /// When the SR is full, any writes to this register will reset it to 0b10000,
    /// and the value being written will be used to select the bank.
    /// Ref: https://www.nesdev.org/wiki/MMC1#Examples
    shiftRegister: u8 = 0b000_10000,
    controlRegister: FlagsControl = .{},

    /// 8 KB PRG RAM bank (optional)
    const prg_ram = .{ .start = 0x6000, .end = 0x7FFF };
    /// 16 KB PRG ROM bank, either switchable or fixed to the first bank
    const prg_rom_bank_1 = .{ .start = 0x8000, .end = 0xBFFF };
    /// 16 KB PRG ROM bank, either fixed to the last bank or switchable
    const prg_rom_bank_2 = .{ .start = 0xC000, .end = 0xFFFF };

    /// Read a byte from the cartridge's CHR ROM.
    fn ppuRead(i_mapper: *Mapper, addr: u16) u8 {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        return self.cart.chr_rom[addr];
    }

    /// Write a byte to PPU memory.
    fn ppuWrite(i_mapper: *Mapper, addr: u16, value: u8) void {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        self.ppu.ppu_ram[addr] = value;
    }

    fn writeControl(self: *Self, value: u8) void {
        _ = value;
        _ = self;
    }

    fn writeShiftRegister(self: *Self, value: u8) void {
        // Writing a value with bit-7 set clears the shift register.
        if (value & 0b1000_0000 == 1) {
            self.currentBank = self.shiftRegister;
            self.shiftRegister = 0b10000;
            return;
        }

        // Set the MSB of the shift register to the LSB of the value
        self.shiftRegister >>= 1;
        self.shiftRegister |= ((value & 0b1) << 4);
    }

    fn read(i_mapper: *Mapper, addr: u16) u8 {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        _ = self;
        _ = addr;
    }

    fn write(i_mapper: *Mapper, addr: u16, value: u8) void {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        switch (addr) {
            0x8000...0xFFFF => self.writeShiftRegister(value),
        }
    }

    /// Create a new mapper that operates on `cart`.
    pub fn init(cart: *Cart, ppu: *PPU) Self {
        return .{
            .cart = cart,
            .ppu = ppu,
            .mapper = Mapper.init(read, write, ppuRead, ppuWrite),
        };
    }
};
