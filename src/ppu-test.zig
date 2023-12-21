const std = @import("std");
const ppu_mod = @import("./ppu/ppu.zig");
const PPU = ppu_mod.PPU;
const Console = @import("nes.zig").Console;

const t = std.testing;

test "(PPU) writing to $2006" {
    var console = try Console.fromROMFile(t.allocator, "../roms/beepboop.nes");
    defer console.deinit();

    var ppu = console.ppu;

    ppu.t = @bitCast(@as(u15, 0b0000_000_1010_1010));
    ppu.vram_addr = ppu.t;

    // test first write
    ppu.ppuWrite(6, 0b0011_1101);
    try std.testing.expectEqual(@as(u15, 0b0111101_1010_1010), @as(u15, @bitCast(ppu.t)));
    try std.testing.expect(!ppu.is_first_write);

    // test second write
    ppu.ppuWrite(6, 0b0011_1101);
    try std.testing.expectEqual(@as(u15, 0b0111101_0011_1101), @as(u15, @bitCast(ppu.t)));
    try std.testing.expect(ppu.is_first_write);
}

test "(PPU) Writing to $2005" {
    var console = try Console.fromROMFile(t.allocator, "../roms/beepboop.nes");
    defer console.deinit();

    var ppu = console.ppu;

    ppu.t = @bitCast(@as(u15, 0));

    // test first write
    try std.testing.expect(ppu.is_first_write);
    ppu.ppuWrite(5, 0b01111_101);
    try std.testing.expectEqual(@as(u5, 0b01111), ppu.t.coarse_x);
    try std.testing.expectEqual(@as(u8, 0b101), ppu.fine_x);

    // test second write
    try std.testing.expect(!ppu.is_first_write);
    ppu.ppuWrite(5, 0b01011110);
    try std.testing.expectEqual(@as(u5, 0b01_011), ppu.t.coarse_y);
    try std.testing.expectEqual(@as(u3, 0b110), ppu.t.fine_y);
    try std.testing.expect(ppu.is_first_write);
}
