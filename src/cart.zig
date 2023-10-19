const std = @import("std");
const assert = std.debug.assert;
const T = std.testing;

const Allocator = std.mem.Allocator;

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
    prg_rom_size: u8 = 0,
    chr_rom_size: u8 = 0,

    flags_6: Flags6 = .{},
    flags_7: Flags7 = .{},

    // Currently, I do not support cartridges with PRG RAM.
    _unused_prg_ram_size: u8 = 0,

    // Used to tell apart PAL TV system cartridges from NTSC ones.
    // Unused. No ROM images use this.
    _unused_tv_system: u8 = 0,

    // no ROM image in circulation uses this byte.
    _unused_prg_ram: u8 = 0,

    // Padding.
    // These are actually used by the NES 2.0 header format:
    // https://www.nesdev.org/wiki/NES_2.0
    // But NES 2.0 is backwards compatible with iNES, so we should
    // be good here.
    zero: u40 = 0,

    comptime {
        assert(@sizeOf(Self) == 16);
    }
};

pub const Cart = struct {
    header: Header,
    prg_rom: []const u8,
    allocator: Allocator,
    const Self = @This();

    pub fn loadFromFile(allocator: Allocator, path: [*:0]const u8) !Self {
        var file = try std.fs.cwd().openFileZ(path, .{});
        defer file.close();

        var buf = [_]u8{0} ** @sizeOf(Header);
        var bytes_read = try file.read(&buf);

        assert(bytes_read == @sizeOf(Header));

        var header: Header = @bitCast(buf);

        if (header.flags_6.trainer) {
            // skip the trainer, if present.
            // TODO: actually load the trainer.
            var trainer_buf = [_]u8{0} ** 512;
            bytes_read = try file.read(&trainer_buf);
            assert(bytes_read == 512);
        }

        // populate the PRG ROM.
        var prg_rom_banks: u16 = header.prg_rom_size;
        var prg_rom_size = prg_rom_banks * 16 * 1024;
        var prg_rom_buf = try allocator.alloc(u8, prg_rom_size);

        bytes_read = try file.read(prg_rom_buf);
        assert(bytes_read == prg_rom_size);

        return Self{ .header = header, .prg_rom = prg_rom_buf, .allocator = allocator };
    }

    pub fn free(self: *Self) !void {
        self.allocator.free(self.prg_rom);
    }

    // Get the mapper used in this cartridge.
    // ref: https://www.nesdev.org/wiki/List_of_mappers
    pub fn getMapper(self: *Self) u8 {
        var lo: u8 = self.header.flags_6.mapper_lower;
        var hi: u8 = self.header.flags_7.mapper_upper;
        return (hi << 4) | lo;
    }
};

test "Cartridge loading: header" {
    var allocator = std.testing.allocator;

    var cart = try Cart.loadFromFile(allocator, "roms/super-mario-bros.nes");
    try T.expectEqual(Header.Magic{ .N = 'N', .E = 'E', .S = 'S', .EOF = 0x1A }, cart.header.NES);
    try T.expectEqual(@as(u8, 2), cart.header.prg_rom_size);
    try T.expectEqual(@as(u8, 1), cart.header.chr_rom_size);
    try T.expectEqual(false, cart.header.flags_6.has_prg_ram);
    try T.expectEqual(true, cart.header.flags_6.mirroring_is_vertical);
    try T.expectEqual(@as(u8, 0), cart.getMapper());

    try cart.free();
}
