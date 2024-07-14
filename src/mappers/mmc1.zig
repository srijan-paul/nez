const std = @import("std");
const Mapper = @import("./mapper.zig").Mapper;
const Cart = @import("../cart.zig").Cart;
const CPU = @import("../cpu.zig").CPU;
const PPU = @import("../ppu/ppu.zig").PPU;
const util = @import("../util.zig");

/// 5 bit Control register.
const FlagsControl = packed struct {
    /// Determines the mirroring mode.
    /// 0: one screen, lower bank; 1: one screen, upper bank.
    /// 2: vertical; 3: horizontal
    mirror_mode: u2 = 0,
    /// 0,1: Switch 32KB at $8000, ignoring low bit of bank number.
    /// 2: fix first bank at $8000, and switch 16KB bank at $C000.
    /// 3: fix last bank at $C000, and switch 16KB bank at $8000.
    prg_rom_bank_mode: u2 = 3,
    /// 1: Switch two 4kb banks, 0: Switch 8KB banks at a time.
    chr_rom_is_4kb: bool = false,

    comptime {
        std.debug.assert(@bitSizeOf(FlagsControl) == 5);
    }
};

/// The iNES format assigns mapper 1 to the MMC1 board.
/// Used by games like Megaman 2, Robocop 2, Robocop 3, Zelda,
/// Silius, and many others.
pub const MMC1 = struct {
    const Self = @This();

    const PrgBankSize = 0x4000; // 16KiB per bank.
    const ChrBankSize = 0x1000; // 4KiB per bank.

    mapper: Mapper,
    cart: *Cart,
    ppu: *PPU,

    /// This shift register is used to determine the currently selected bank.
    /// When the LSB is set to '1', the SR is considered to be "full".
    /// When the SR is full, any writes to this register first shift one bit into it as usual,
    /// then copy its contents to an internal register depending on the address used to reach it.
    /// Finally, the SR is cleared back to 0b10000.
    /// Ref: https://www.nesdev.org/wiki/MMC1#Examples
    shift_register: u5 = 0b10000,

    /// Controls mirroring, PRG bank mode, and CHR bank mode.
    ctrl_register: FlagsControl = .{}, // when SR is written via $8000 - $9FFF
    chr_bank0: u5 = 0, // when SR is written via $A000 - $BFFF
    chr_bank1: u5 = 0, // when SR is written via $C000 - $DFFF
    prg_bank: u5 = 0, // when SR is written via $E000 - $FFFF

    prg_rom_bank_count: u5, // # of 16 KB PRG ROM banks in the cart
    chr_rom_bank_count: u8, // # of 8 KB CHR ROM banks in the cart
    has_chr_ram: bool, // whether the cart has CHR RAM

    /// CPU address space $8000 - $BFFF
    prg_rom_lo: []u8,
    /// CPU address space $C000 - $FFFF
    prg_rom_hi: []u8,

    /// PPU address space $0000 - $0FFF
    chr_rom_lo: []u8,
    /// PPU address space $1000 - $1FFF
    chr_rom_hi: []u8,

    inline fn writePrgBank(self: *Self, value: u5) void {
        self.prg_bank = value & (self.prg_rom_bank_count - 1);
    }

    /// Update the memory-maps for PRG and CHR banks based on the current control register.
    fn updateBankOffsets(self: *Self) void {
        switch (self.ctrl_register.prg_rom_bank_mode) {
            0, 1 => {
                // Switch 32KB at $8000, ignoring low bit of bank number.
                const bank_number = self.prg_bank & (self.prg_rom_bank_count - 1);

                const bank1_start = @as(u32, bank_number) * 2 * PrgBankSize;
                const bank1_end = bank1_start + PrgBankSize;
                self.prg_rom_lo = self.cart.prg_rom[bank1_start..bank1_end];

                const bank2_start = bank1_end;
                const bank2_end = bank2_start + PrgBankSize;
                self.prg_rom_hi = self.cart.prg_rom[bank2_start..bank2_end];
            },
            2 => {
                // fix first bank at $8000, and switch 16KB bank at $C000.
                self.prg_rom_lo = self.cart.prg_rom[0..PrgBankSize];

                const bank_start = PrgBankSize * @as(u32, self.prg_bank);
                const bank_end = bank_start + PrgBankSize;
                self.prg_rom_hi = self.cart.prg_rom[bank_start..bank_end];
            },
            3 => {
                // fix last bank at $C000, and switch the 16Kb bank at $8000.
                const bank_offset = PrgBankSize * @as(u32, self.prg_bank);
                self.prg_rom_lo = self.cart.prg_rom[bank_offset .. bank_offset + PrgBankSize];

                const last_bank_start = (@as(u32, self.prg_rom_bank_count) - 1) * PrgBankSize;
                self.prg_rom_hi = self.cart.prg_rom[last_bank_start .. last_bank_start + PrgBankSize];
            },
        }

        // The bank switching controls do not do anything if the cart has CHR RAM (not ROM).
        // The CHR RAM resides in the same address space as CHR ROM, the only real difference
        // is that a program can write to CHR RAM whereas CHR ROM is (obviously) Read only.
        if (self.has_chr_ram) return;

        // std.debug.print("is 4kb: {}\n", .{self.ctrl_register.chr_rom_is_4kb});
        if (self.ctrl_register.chr_rom_is_4kb) {
            // Switch two 4kb banks.
            const n_4kb_banks: usize = self.chr_rom_bank_count * 2;

            const bank0_index = @as(usize, self.chr_bank0) & (n_4kb_banks - 1);
            const bank0_start = bank0_index * ChrBankSize;
            self.chr_rom_lo = self.cart.chr_rom[bank0_start .. bank0_start + ChrBankSize];

            const bank1_index = @as(usize, self.chr_bank1) & (n_4kb_banks - 1);
            const bank1_start = bank1_index * ChrBankSize;
            self.chr_rom_hi = self.cart.chr_rom[bank1_start .. bank1_start + ChrBankSize];
        } else {
            // Switch 8KB banks at a time.
            const bank_index = self.chr_bank0 & (self.chr_rom_bank_count - 1);
            const offset = @as(usize, bank_index) * (2 * ChrBankSize);
            self.chr_rom_lo = self.cart.chr_rom[offset .. offset + ChrBankSize];
            self.chr_rom_hi = self.cart.chr_rom[offset + ChrBankSize .. offset + 2 * ChrBankSize];
        }
    }

    /// Write to the 5-bit control register.
    fn writeControl(self: *Self, value: u5) void {
        self.ctrl_register = @bitCast(value);
        switch (self.ctrl_register.mirror_mode) {
            0 => self.mapper.ppu_mirror_mode = .one_screen_lower,
            1 => self.mapper.ppu_mirror_mode = .one_screen_upper,
            2 => self.mapper.ppu_mirror_mode = .vertical,
            3 => self.mapper.ppu_mirror_mode = .horizontal,
        }
    }

    /// Write to an internal register.
    /// This subroutine is called whenever a full shift register (xxxx1) is written to.
    /// The destination register is determined by bit 13 and 14 of the address used to
    /// reach the shift register (addr).
    /// Ref: https://www.nesdev.org/wiki/MMC1#Registers
    fn writeRegister(self: *Self, addr: u16, value: u5) void {
        // if (0xA000 <= addr and addr <= 0xBFFF) {
        //     std.debug.print("(first CHR bank) {x} <- {x}\n", .{ addr, value });
        // }
        //
        switch (addr) {
            0x8000...0x9FFF => self.writeControl(value),
            0xA000...0xBFFF => self.chr_bank0 = value,
            0xC000...0xDFFF => self.chr_bank1 = value,
            0xE000...0xFFFF => self.writePrgBank(value),
            else => std.debug.panic("MMC1: Bad register address", .{}),
        }
        self.updateBankOffsets();
    }

    /// Write to the shift register.
    fn writeShiftRegister(self: *Self, addr: u16, value: u8) void {
        // when bit 7 of the load register is set:
        // 1. clear the SR.
        // 2. Ctrl = Ctrl | $0C
        if (value & 0b1000_0000 != 0) {
            self.shift_register = 0b10000;
            const ctrl: u5 = @bitCast(self.ctrl_register);
            self.ctrl_register = @bitCast(ctrl | 0x0C);
            self.updateBankOffsets();
            return;
        }

        // std.debug.print("SR: {x}, value: {x}\n", .{ self.shift_register, value });

        // check if the SR is full when this write is Done.
        // "full" = '1' is shifted out of the SR (when its the 5th write to the SR).
        const is_last_write = self.shift_register & 0b00001 != 0;

        // Set the MSB of the shift register to the LSB of the value.
        const ls_bit: u5 = @truncate(value & 0b1);
        self.shift_register = (self.shift_register >> 1) | (ls_bit << 4);

        // When the SR is full, any write to this register will:
        // 1. Copy the contents of SR to an internal register depending on `addr`.
        // 2. Clear the SR.
        if (is_last_write) {
            self.writeRegister(addr, self.shift_register);
            self.shift_register = 0b10000; // reset SR.
        }
    }

    fn read(i_mapper: *Mapper, addr: u16) u8 {
        const self: *Self = @fieldParentPtr("mapper", i_mapper);
        return switch (addr) {
            0x0000...0x5FFF => std.debug.panic("Open bus reads not emulated.\n", .{}),
            0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000],
            0x8000...0xBFFF => self.prg_rom_lo[addr - 0x8000],
            0xC000...0xFFFF => self.prg_rom_hi[addr - 0xC000],
        };
    }

    fn write(i_mapper: *Mapper, addr: u16, value: u8) void {
        const self: *Self = @fieldParentPtr("mapper", i_mapper);
        switch (addr) {
            0x0000...0x5FFF => std.debug.panic("Open bus writes not emulated.\n", .{}),
            0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000] = value,
            0x8000...0xFFFF => self.writeShiftRegister(addr, value),
        }
    }

    pub fn init(cart: *Cart, ppu: *PPU) Self {
        var self = Self{
            .ppu = ppu,
            .cart = cart,
            .has_chr_ram = cart.header.chr_rom_count == 0,
            .prg_rom_bank_count = @truncate(cart.header.prg_rom_banks),
            .chr_rom_bank_count = @truncate(cart.header.chr_rom_count),
            .mapper = Mapper.init(read, write, ppuRead, ppuWrite),
            // these are initialized when `updateBankOffsets` is called below.
            .prg_rom_lo = undefined,
            .prg_rom_hi = undefined,
            .chr_rom_lo = undefined,
            .chr_rom_hi = undefined,
        };

        // Initialize the PRG and CHR address spaces.
        // Initially, the PRG ROM bank mode is 3, and the CHR ROM bank mode is 0.
        self.updateBankOffsets();
        return self;
    }

    /// Read a byte from the cartridge's CHR ROM.
    fn ppuRead(m: *Mapper, addr: u16) u8 {
        const self: *Self = @fieldParentPtr("mapper", m);
        if (addr < 0x2000) {
            if (self.has_chr_ram) return self.cart.chr_ram[addr];
            return if (addr < 0x1000)
                self.chr_rom_lo[addr]
            else
                self.chr_rom_hi[addr - 0x1000];
        }

        if (addr < 0x3000)
            return self.ppu.readRAM(m.unmirror_nametable(addr));

        return self.ppu.readRAM(addr);
    }

    /// Write a byte to PPU memory.
    fn ppuWrite(m: *Mapper, addr: u16, value: u8) void {
        const self: *Self = @fieldParentPtr("mapper", m);
        if (addr < 0x2000) {
            if (self.has_chr_ram) self.cart.chr_ram[addr] = value;
            return;
        }

        if (addr < 0x3000)
            return self.ppu.writeRAM(m.unmirror_nametable(addr), value);

        self.ppu.writeRAM(addr, value);
    }
};
