const std = @import("std");
const util = @import("util.zig");
const MapperKind = @import("mappers/mapper.zig").MapperKind;

const NROM = @import("mappers/nrom.zig").NROM;

const NESError = util.NESError;

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const T = std.testing;

// https://www.nesdev.org/wiki/INES#Flags_6
pub const Flags6 = packed struct {
    pub const Self = @This();
    // 0 = horizontal mirroring, 1 = vertical mirroring.
    mirroring_is_vertical: bool = false,

    // true if the cartridge contains battery-backed PRG RAM ($6000-7FFF)
    // or other persistent memory.
    has_prg_ram: bool = false,

    // true if the cartridge contains a 512-byte trainer at $7000-$71FF.
    trainer: bool = false,

    // true if the cartridge contains a 4-screen VRAM layout.
    ignore_mirroring: bool = false,

    // lower nibble of mapper #
    mapper_lower: u4 = 0,

    comptime {
        assert(@sizeOf(Self) == 1);
    }
};

// https://www.nesdev.org/wiki/INES#Flags_7
pub const Flags7 = packed struct {
    pub const Self = @This();
    // 0: NES
    // 1: Nintendo VS Unisystem
    // 2: PlayChoice-10
    // 3: Extended Console Type
    console_type: u2 = 0b00,

    // always set to "2".
    // However, the default is set to 0 to catch loading errors.
    nes_idenfitier: u2 = 0b00,

    // upper nibble of mapper #
    mapper_upper: u4 = 0,

    comptime {
        assert(@sizeOf(Self) == 1);
    }
};

// an NES ROM image header in the INES format (https://www.nesdev.org/wiki/INES)
pub const Header = packed struct {
    const Self = @This();

    // A magic sequence of bytes in the beginning of every
    // ROM file.
    pub const Magic = packed struct {
        N: u8 = 0,
        E: u8 = 0,
        S: u8 = 0,
        EOF: u8 = 0,
        comptime {
            assert(@sizeOf(Magic) == 4);
        }
    };

    NES: Magic = .{}, // "NES" followed by MS-DOS end-of-file (0x1A)
    prg_rom_banks: u8 = 0,
    chr_rom_size: u8 = 0,

    flags_6: Flags6 = .{},
    flags_7: Flags7 = .{},

    // A value of 0 assumes 8KB of PRG RAM for compatibility.
    _unused_prg_ram_size: u8 = 0,

    // Used to tell apart PAL TV system cartridges from NTSC ones.
    // Unused. No ROM images use this.
    _unused_tv_system: u8 = 0,

    // no ROM image in circulation uses this byte.
    _unused_prg_ram: u8 = 0,

    // Padding.
    // These bits are used by the NES 2.0 header format:
    // https://www.nesdev.org/wiki/NES_2.0
    // But NES 2.0 is backwards compatible with iNES, so we should
    // be good here.
    zero: u40 = 0,

    comptime {
        assert(@sizeOf(Self) == 16);
    }

    /// check if the header is valid.
    pub fn isValid(self: *Self) bool {
        return self.NES.N == 'N' and self.NES.E == 'E' and self.NES.S == 'S' and self.NES.EOF == 0x1A;
    }

    /// Get the kind of mapper used for the ROM to which
    /// this header belongs.
    pub fn getMapper(self: *Self) MapperKind {
        var lo: u8 = self.flags_6.mapper_lower;
        var hi: u8 = self.flags_7.mapper_upper;
        var mapper_code = (hi << 4) | lo;
        return switch (mapper_code) {
            0 => MapperKind.nrom,
            else => unreachable,
        };
    }
};

// Represents a NES Cartridge.
pub const Cart = struct {
    pub const prg_ram_size = 1024 * 8; // 8KiB of PRG RAM.
    header: Header,
    prg_ram: [prg_ram_size]u8 = [_]u8{0} ** prg_ram_size,
    prg_rom: []u8,
    chr_rom: []u8,
    allocator: Allocator,

    const Self = @This();

    pub fn loadFromFile(allocator: Allocator, path: [*:0]const u8) !Self {
        var file = try std.fs.cwd().openFileZ(path, .{});
        defer file.close();

        var buf = [_]u8{0} ** @sizeOf(Header);
        var total_bytes_read: usize = 0;
        var bytes_read = try file.read(&buf);
        total_bytes_read += bytes_read;

        assert(bytes_read == @sizeOf(Header));

        var header: Header = @bitCast(buf);

        if (!header.isValid()) {
            return NESError.InvalidROM;
        }

        // Value of 0 = 8KiB PRG RAM.
        assert(header._unused_prg_ram_size == 0);

        if (header.flags_6.trainer) {
            // skip the trainer, if present.
            // TODO: actually load the trainer.
            var trainer_buf = [_]u8{0} ** 512;
            bytes_read = try file.read(&trainer_buf);
            total_bytes_read += bytes_read;
            assert(bytes_read == 512);
        }

        // populate the PRG ROM.
        const prg_rom_banksize: usize = 16 * 1024; // size of each ROM bank

        var prg_rom_buf = try allocator.alloc(u8, header.prg_rom_banks * prg_rom_banksize);
        bytes_read = try file.read(prg_rom_buf);
        std.debug.assert(bytes_read == prg_rom_buf.len);

        total_bytes_read += bytes_read;
        var chr_rom_size = @as(usize, header.chr_rom_size) * 8 * 1024;
        var chr_rom_buf = try allocator.alloc(u8, chr_rom_size);

        bytes_read = try file.read(chr_rom_buf);
        total_bytes_read += bytes_read;
        assert(bytes_read == chr_rom_size);

        // I do not support playchoice inst-rom and prom (yet).

        return .{
            .header = header,
            .prg_rom = prg_rom_buf,
            .chr_rom = chr_rom_buf,
            .allocator = allocator,
        };
    }

    /// uninitialize a cartridge.
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.prg_rom);
        self.allocator.free(self.chr_rom);
    }
};

fn foo(allocator: Allocator) void {
    var cart = try allocator.create(Cart);
    var any: *anyopaque = &cart;
    allocator.free(any);
}

test "Cartridge loading: header" {
    var cart = try Cart.loadFromFile(T.allocator, "roms/super-mario-bros.nes");
    defer cart.deinit();

    try T.expectEqual(Header.Magic{ .N = 'N', .E = 'E', .S = 'S', .EOF = 0x1A }, cart.header.NES);
    try T.expectEqual(@as(u8, 2), cart.header.prg_rom_banks);
    try T.expectEqual(@as(u8, 1), cart.header.chr_rom_size);
    try T.expectEqual(false, cart.header.flags_6.has_prg_ram);
    try T.expectEqual(true, cart.header.flags_6.mirroring_is_vertical);
    try T.expectEqual(MapperKind.nrom, cart.header.getMapper());
}
