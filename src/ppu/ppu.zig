const std = @import("std");
const palette = @import("./ppu-colors.zig");

const Color = palette.Color;
const Palette = palette.Palette;

// Emulator for the NES PPU.
pub const PPU = struct {
    pub const ScreenWidth = 256;
    pub const ScreenHeight = 240;
    pub const NPixels = ScreenWidth * ScreenHeight;

    const nametable_base_addr: u16 = 0x2000;
    // nametable bytes + attribute bytes.
    const nametable_size = 0x400;
    // base address of palettes for background rendering
    const bg_palette_base_addr: u16 = 0x3F00;

    /// When `true`, it means the PPU has generated an NMI interrupt,
    /// and the CPU needs to handle it.
    is_nmi_pending: bool = false,

    ppu_ram: [0x10000]u8 = [_]u8{0} ** 0x10000,

    ppu_ctrl: FlagCTRL = .{},
    ppu_mask: FlagMask = .{},

    // NOTE: reading from this register resets the address latch.
    // read-only
    ppu_status: FlagStatus = .{},

    ppu_addr: u16 = 0,

    cycle: u16 = 340,
    current_scanline: u16 = 260,

    /// Current position inside the frame buffer.
    /// This depends on the current scanline and cycle.
    frame_buffer_pos: usize = 0,
    /// A 256x240 1D array of colors IDs that is filled in dot-by-dot by the CPU.
    frame_buffer: [NPixels]u8 = .{0} ** NPixels,
    /// The actual buffer that should be drawn to the screen every frame by raylib.
    /// Note that this is stored in R8G8B8 format (24 bits-per-pixel).
    /// I store it like this so its easier to pass it to raylib for rendering
    /// using the PIXELFORMAT_UNCOMPRESSED_R8G8B8.
    render_buffer: [NPixels * 3]u8 = .{0} ** (NPixels * 3),

    palette_attr_next_tile: u8 = 0,

    /// Stores the current VRAM address when loading tile and sprite data.
    vram_addr: VRamAddr = .{},

    /// The "t" register is the "source of truth" for the base vram address.
    t: VRamAddr = .{},

    /// the write toggle bit.
    /// This is shared by PPU registers at $2005 and $2006
    is_first_write: bool = false,

    /// In the original 2A03 chip, this was a 3-bit register.
    /// But mine is a u8 just so a modern CPU can crunch this number quick.
    fine_x: u8 = 0,

    // Every 8 cycles, the PPU fetches a byte from the pattern table,
    // and places it into an internal latch. This byte is meant to represent that latch.
    // In the following cycle, the PPU fetches the palette attribute byte for this nametable byte.
    // And then, it fetches two bytes,
    // each representing a sliver of a pattern table plane for the tile to be rendered.
    nametable_byte: u8 = 0,
    attr_table_byte: u8 = 0,
    pattern_table_byte_lo: u8 = 0,
    pattern_table_byte_hi: u8 = 0,

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

    /// The internal `t` and `v` registers have
    /// there bits arranged like this:
    pub const VRamAddr = packed struct {
        coarse_x: u5 = 0,
        coarse_y: u5 = 0,
        nametable: u2 = 0,
        fine_y: u3 = 0,
        comptime {
            std.debug.assert(@bitSizeOf(VRamAddr) == 15);
        }
    };

    // Fetch a byte of data from one of the two pattern tables.
    fn fetchFromPatternTable(self: *Self, addr: u8, is_low_plane: bool) u8 {
        var fine_y: u16 = self.vram_addr.fine_y;
        var pt_number: u16 =
            if (self.ppu_ctrl.pattern_background) 0 else 1;

        var pt_addr =
            (pt_number * 0x1000) +
            (addr * 16) +
            fine_y;

        return if (is_low_plane)
            self.busRead(pt_addr)
        else
            self.busRead(pt_addr + 8);
    }

    /// Fetch the next byte from the name table
    fn fetchNameTableByte(self: *Self) u8 {
        var coarse_y: u16 = self.vram_addr.coarse_y;
        var coarse_x: u16 = self.vram_addr.coarse_x;
        var nt_number: u16 = self.vram_addr.nametable;

        var nt_addr =
            nametable_base_addr +
            (nametable_size * nt_number) +
            coarse_y * 32 +
            coarse_x;

        return self.busRead(nt_addr);
    }

    fn fetchAttrTableByte(self: *Self) u8 {
        _ = self;
        return 0;
    }

    /// increment the fine and coarse Y based on the current
    /// clock cycle.
    fn incrY(self: *Self) void {
        // TODO: nametable switching.
        var fine_y: u8 = self.vram_addr.fine_y;
        var coarse_y: u8 = self.vram_addr.coarse_y;
        if (fine_y == std.math.maxInt(@TypeOf(self.vram_addr.fine_y))) {
            fine_y = 0;
            if (coarse_y == 31) {
                coarse_y = 0;
            } else {
                coarse_y += 1;
            }
        } else {
            fine_y += 1;
        }

        self.vram_addr.fine_y = @truncate(fine_y);
        self.vram_addr.coarse_y = @truncate(coarse_y);
    }

    /// Increment the coarse X based on the current
    /// clock cycle.
    fn incrCoarseX(self: *Self) void {
        // TODO: implement nametable switching.
        var coarse_x: u8 = self.vram_addr.coarse_x;
        if (coarse_x < std.math.maxInt(u5)) {
            coarse_x += 1;
        } else {
            coarse_x = 0;
        }
        self.vram_addr.coarse_x = @truncate(coarse_x);
    }

    fn visibleDot(self: *Self, subcycle: u16) void {
        switch (subcycle) {
            0 => {
                self.incrCoarseX();
            },

            // fetch the name table byte.
            2 => self.nametable_byte = self.fetchNameTableByte(),
            4 => self.attr_table_byte = self.fetchAttrTableByte(),
            6 => self.pattern_table_byte_lo = self.fetchFromPatternTable(
                self.nametable_byte,
                true,
            ),
            7 => {
                self.pattern_table_byte_hi = self.fetchFromPatternTable(
                    self.nametable_byte,
                    false,
                );
                var hi = self.pattern_table_byte_hi;
                var lo = self.pattern_table_byte_lo;
                if (self.cycle >= 256) return;
                for (0..8) |i| {
                    // TODO: Are PT bits stored left to right or right
                    // to left?
                    comptime {
                        std.debug.assert(@TypeOf(hi) == u8);
                        std.debug.assert(@TypeOf(lo) == u8);
                    }
                    var color_index: u8 = 0;
                    var lo_bit: u8 = (lo >> @truncate(i)) & 0b1;
                    var hi_bit: u8 = (hi >> @truncate(i)) & 0b1;
                    color_index |= hi_bit << 1;
                    color_index |= lo_bit;
                    var color_id = self.busRead(bg_palette_base_addr + color_index);
                    std.debug.assert(color_id < 64);
                    self.frame_buffer[self.frame_buffer_pos] = color_id;
                    self.frame_buffer_pos += 1;
                }
            },
            else => {},
        }
    }

    /// Load the PPU's shift registers with necessary data.
    fn visibleScanline(self: *Self) void {
        if (self.cycle < 256) {
            // draw one pixel to the screen.
            var frame_buf_index = @as(usize, ScreenWidth) * self.current_scanline + self.cycle;
            var render_buf_index = frame_buf_index * 3;
            var color = &Palette[self.frame_buffer[frame_buf_index]];
            self.render_buffer[render_buf_index] = color.r;
            self.render_buffer[render_buf_index + 1] = color.g;
            self.render_buffer[render_buf_index + 2] = color.b;
        }

        if (self.cycle == 257) {
            // TODO: copy nametable horizontal info
            self.vram_addr.coarse_x = self.t.coarse_x;
        }

        // The 0th cycle is idle, nothing happens.
        // TODO: apparently, some fetches do happen here.
        if (self.cycle == 0) {
            return;
        }

        var subcycle = self.cycle % 8;
        switch (self.cycle) {
            // visible dots that draw to the screen.
            // 1 -> 255 are the visible dots.
            // 321 -> 340 are cycles where the PPU fetches
            // tile data for the next scanline.
            1...255, 321...340 => self.visibleDot(subcycle),
            256 => {
                self.incrY();
                self.incrCoarseX();
            },
            257 => {
                self.vram_addr.coarse_x = self.t.coarse_x;
            },
            // garbage nametable byte fetches.
            258, 260, 266, 305 => self.nametable_byte = self.fetchNameTableByte(),

            else => {},
        }

        if (self.cycle >= 1 and self.cycle <= 256) {}
    }

    fn preRenderScanline(_: *Self) void {}

    pub fn tick(self: *PPU) void {
        // TODO: odd/even frame shenanigans.
        self.cycle += 1;
        if (self.cycle > 340) {
            self.cycle = 0;
            self.current_scanline += 1;
            if (self.current_scanline > 261) {
                self.current_scanline = 0;
            }
        }

        if (self.cycle == 0 and self.current_scanline == 0) {
            self.frame_buffer_pos = 0;
        }

        switch (self.current_scanline) {
            // pre-render scanline.
            261 => {
                // TODO: this scanline can vary in length depending on whether its an odd or even
                // frame. Implement this behavior.
                if (self.cycle == 1) {
                    // clear the vblank flag.
                    self.ppu_status.is_vblank_active = false;
                    self.is_nmi_pending = false;
                } else if (self.cycle >= 280 and self.cycle <= 304) {
                    // copy the t register into v.
                    // TODO: copy nametable;
                    self.vram_addr.coarse_y = self.t.coarse_y;
                }
            },

            0...239 => self.visibleScanline(),

            // post-render scanline. Nothing happens
            240 => {},
            241 => {
                if (self.cycle == 1) {
                    // set the vblank flag.
                    self.ppu_status.is_vblank_active = true;
                    if (self.ppu_ctrl.generate_nmi) {}
                }
            },

            242...260 => {
                // idle scanlines. Nothing happens.
                // Also known as the "VBLANK" phase.
                // The CPU freely access the PPU contents during this time.
            },

            else => unreachable,
        }
    }

    /// Write a byte to $2005 of CPU address space (PPUSCROLL register).
    pub fn setPPUScroll(self: *Self, byte: u8) void {
        if (self.is_first_write) {
            // set the fine and coarse X scroll.
            self.t.coarse_x = @truncate(byte >> 3);
            self.fine_x = @truncate(byte & 0b00000_111);
        } else {
            // set the fine and coarse Y scroll.
            self.t.coarse_y = @truncate(byte >> 3);
            self.t.fine_y = @truncate(byte & 0b00000_111);
        }

        self.is_first_write = !self.is_first_write;
    }

    /// Write to the PPUADDR register ($2006 of CPU address space).
    pub fn setPPUAddr(self: *Self, value: u8) void {
        if (self.is_first_write) {
            // set high byte
            self.ppu_addr = @as(u16, value) << 8;
            var t: u15 = @bitCast(self.t);
            // clear the 15th bit of t.
            t &= 0b011_1111_1111_1111;
            // get the lower 6 bits of the operand byte, and
            // set the bits of the t register.
            var addr_hi: u15 = value & 0b00_111111;
            // set bits 9th-14th bits of t to addr_hi
            t |= addr_hi << 8;
            self.t = @bitCast(t);
        } else {
            self.ppu_addr = self.ppu_addr | @as(u16, value);
            var t: u15 = @bitCast(self.t);
            var lo: u15 = value; // lower 8 bits
            var hi: u15 = t & 0b1111_111_0000_0000; // high 7 bits
            t = lo | hi;
            self.t = @bitCast(t);
            self.vram_addr = self.t;
        }

        self.is_first_write = !self.is_first_write;
    }

    /// Read the PPUSTATUS register.
    /// This will reset the address latch, and clear the vblank flag. // TODO: reset vbl??
    pub fn readPPUStatus(self: *Self) u8 {
        self.is_first_write = true;
        return @bitCast(self.ppu_status);
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
        // TODO: mirroring, increment `v`
        self.ppu_ram[addr] = value;
    }

    pub fn busRead(self: *Self, addr: u16) u8 {
        // TODO: mirroring.
        return self.ppu_ram[addr];
    }
};
