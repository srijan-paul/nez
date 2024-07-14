const std = @import("std");
const Mapper = @import("./mapper.zig").Mapper;
const Cart = @import("../cart.zig").Cart;
const CPU = @import("../cpu.zig").CPU;
const PPU = @import("../ppu/ppu.zig").PPU;
const util = @import("../util.zig");

const Self = @This();

has_chr_ram: bool, // does the cart have CHR RAM?
prg_rom_bank_count: u4, // # of PRG ROM banks in the cart
prg_bank1: []u8 = undefined, // the currently selected PRG ROM bank
prg_bank2: []u8 = undefined, // fixed to last bank of PRG ROM
cart: *Cart,
ppu: *PPU,
mapper: Mapper,

// write to the bank select register
fn setPRGBank(self: *Self, value: u8) void {
    // mask away the high bits of the bank number if out of range.
    const bank: u32 = value & (self.prg_rom_bank_count - 1);
    const bank_start = bank * 0x4000;
    const bank_end = bank_start + 0x4000; // each PRG Bank is 16Kb
    self.prg_bank1 = self.cart.prg_rom[bank_start..bank_end];
}

fn read(m: *Mapper, addr: u16) u8 {
    const self: *Self = @fieldParentPtr("mapper", m);
    return switch (addr) {
        0x0000...0x5FFF => std.debug.panic("Open bus reads not emulated.\n", .{}),
        0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000],
        0x8000...0xBFFF => return self.prg_bank1[addr - 0x8000],
        0xC000...0xFFFF => return self.prg_bank2[addr - 0xC000],
    };
}

fn write(m: *Mapper, addr: u16, value: u8) void {
    const self: *Self = @fieldParentPtr("mapper", m);
    switch (addr) {
        0x0000...0x5FFF => std.debug.panic("Open bus reads not emulated.\n", .{}),
        0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000] = value,
        0x8000...0xFFFF => self.setPRGBank(value),
    }
}
/// Read a byte from the cartridge's CHR ROM.
fn ppuRead(m: *Mapper, addr: u16) u8 {
    const self: *Self = @fieldParentPtr("mapper", m);
    if (addr < 0x2000) {
        if (self.has_chr_ram) return self.cart.chr_ram[addr];
        return self.cart.chr_rom[addr];
    }

    if (addr < 0x3000) {
        return self.ppu.readRAM(m.unmirror_nametable(addr));
    }

    return self.ppu.readRAM(addr);
}

/// Write a byte to PPU memory.
fn ppuWrite(m: *Mapper, addr: u16, value: u8) void {
    const self: *Self = @fieldParentPtr("mapper", m);
    if (addr < 0x2000) {
        if (self.has_chr_ram) {
            self.cart.chr_ram[addr] = value;
        } else {
            self.cart.chr_rom[addr] = value;
        }
        return;
    }

    if (addr < 0x3000) {
        self.ppu.writeRAM(m.unmirror_nametable(addr), value);
    } else {
        self.ppu.writeRAM(addr, value);
    }
}

pub fn init(cart: *Cart, ppu: *PPU) Self {
    var self = Self{
        .ppu = ppu,
        .cart = cart,
        .prg_rom_bank_count = @truncate(cart.header.prg_rom_banks),
        .mapper = Mapper.init(read, write, ppuRead, ppuWrite),
        .has_chr_ram = cart.header.chr_rom_count == 0,
    };

    self.mapper.ppu_mirror_mode = if (self.cart.header.flags_6.mirroring_is_vertical)
        .vertical
    else
        .horizontal;

    const last_bank_start = @as(u32, (self.prg_rom_bank_count - 1)) * 0x4000;
    const last_bank_end = last_bank_start + 0x4000;
    self.prg_bank2 = cart.prg_rom[last_bank_start..last_bank_end];
    // initially, map the address space to the first bank.
    self.setPRGBank(0);
    return self;
}
