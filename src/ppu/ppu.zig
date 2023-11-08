const std = @import("std");
const palette = @import("./ppu-colors.zig").PPU_Palette;

/// State of the PPUADDR register.
const PPUAddrState = enum {
    /// The high byte has been set (the first write to PPUADDR).
    high_byte_set,
    /// The low byte has been set (the second write to PPUADDR).
    addr_set,
};

// Emulator for the NES PPU.
pub const PPU = struct {
    ppu_ram: [0x10000]u8 = [_]u8{0} ** 0x10000,

    ppu_ctrl: FlagCTRL = .{},
    ppu_mask: FlagMask = .{},

    // NOTE: reading from this register resets the address latch.
    // read-only
    ppu_status: FlagStatus = .{},

    ppu_addr: u16 = 0,
    ppu_addr_state: PPUAddrState = PPUAddrState.addr_set,

    cycle: u16 = 0,
    current_scanline: u16 = 0,

    const Self = @This();
    // flags for the PPUCTRL register.
    pub const FlagCTRL = packed struct {
        nametable_lo: u1 = 0,
        nametable_hi: u1 = 0,
        increment_mode: bool = false,
        pattern_sprite: bool = false,
        pattern_background: bool = false,
        sprite_size: bool = false,
        slave_mode: bool = false,
        generate_nmi: bool = false,
    };

    // flags for the PPUMask register.
    pub const FlagMask = packed struct {
        enhance_blue: bool = false,
        enhance_green: bool = false,
        enhance_red: bool = false,

        foreground_enabled: bool = false,
        background_enabled: bool = false,

        left_fg: bool = false,
        left_bg: bool = false,
        grayscale_enabled: bool = false,
    };

    // flags for the PPUStatus register.
    pub const FlagStatus = packed struct {
        _ppu_open_bus_unused: u5 = 0,
        sprite_overflow: bool = false,
        sprite_zero_hit: bool = false,
        is_vblank_active: bool = false,
    };

    pub fn tick(self: *PPU) void {
        self.cycle += 1;
        if (self.cycle > 340) {
            self.cycle = 0;
            // TODO: reset scanline.
        }
    }

    /// Write to the PPUCTRL register.
    pub fn setPPUAddr(self: *Self, value: u8) void {
        if (self.ppu_addr_state == .addr_set) {
            // Set the high byte of PPUADDR.
            self.ppu_addr_state = .high_byte_set;
            self.ppu_addr = @as(u16, value) << 8;
            return;
        }

        // set the low byte of PPUADDR.
        self.ppu_addr_state = .addr_set;
        self.ppu_addr = self.ppu_addr | @as(u16, value);
    }

    /// Writing to PPUDATA register writes to PPUADDR.
    /// Write a byte of data to the address pointed to by the PPUADDR register.
    pub fn writeToPPUAddr(self: *Self, value: u8) void {
        self.busWrite(self.ppu_addr, value);
        // TODO: increment the address based on the PPUCTRL register.
        self.ppu_addr += 1;
    }

    /// Read a byte of data from the address pointed to by the PPUADDR register.
    /// Reading from PPUDATA register reads from PPUADDR.
    pub fn readFromPPUAddr(self: *Self) u8 {
        return self.busRead(self.ppu_addr);
    }

    pub fn busWrite(self: *Self, addr: u16, value: u8) void {
        // TODO: mirroring
        self.ppu_ram[addr] = value;
    }

    pub fn busRead(self: *Self, addr: u16) u8 {
        // TODO: mirroring.
        return self.ppu_ram[addr];
    }
};
