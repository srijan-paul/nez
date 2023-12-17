const std = @import("std");
const palette = @import("./ppu-colors.zig");

pub const Color = palette.Color;
pub const Palette = palette.Palette;

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

    /// size of each pattern table (16 x 16 tiles * 8 bytes per bit-plane * 2 bit-planes per tile)
    pub const pattern_table_size: u16 = 16 * 16 * 8 * 2; // 0x1000
    pub const pattern_table_size_px: u16 = 128 * 128;

    /// When `true`, it means the PPU has generated an NMI interrupt,
    /// and the CPU needs to handle it.
    is_nmi_pending: bool = false,

    ppu_ram: [0x10000]u8 = [_]u8{0} ** 0x10000,

    ppu_ctrl: FlagCTRL = .{},
    ppu_mask: FlagMask = .{},

    // NOTE: reading from this register resets the address latch.
    // read-only
    ppu_status: FlagStatus = .{},

    // we want to start on the pre-render scanline.
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
    is_first_write: bool = true,

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

    /// Internal registers that store the low and high bit planes
    /// of the pattern table data for the next tile to be drawn.
    /// When it is time to draw these tiles, the data is loaded into
    /// the shift registers defined below.
    /// These internal registers are filled with data on specific cycles of
    /// visible scanlines (and the pre-render scanline) as described here:
    /// https://www.nesdev.org/w/images/default/4/4f/Ppu.svg
    pattern_lo: u8 = 0,
    pattern_hi: u8 = 0,

    /// Shift registers that hold the pattern table data for the current and next tile.
    /// Every 8 cycles, the data for the next tile is loaded into the upper 8 bits (next_tile).
    pattern_table_shifter_lo: ShiftReg16 = .{},
    pattern_table_shifter_hi: ShiftReg16 = .{},

    at_data_lo: ShiftReg8 = 0,
    at_data_hi: ShiftReg8 = 0,

    const Self = @This();

    /// 16-bit shift register to hold pattern-table data.
    /// Every 8 cycles, the data for the next tile is loaded into the upper 8 bits (next_tile).
    /// On every visible dot, the current pixel to render is fetched from the lower 8 bits (curr_tile).
    /// When the current pixel is fetched, the data in this register is shifted by 1 bit.
    pub const ShiftReg16 = packed struct {
        curr_tile: u8 = 0,
        next_tile: u8 = 1,

        /// Shift the contents of the register one bit to the right, and
        /// return the bit that was shifted out (this will be the LSB).
        pub fn shift(self: *ShiftReg16) void {
            var bits: u16 = @bitCast(self.*);
            self.* = @bitCast(bits >> 1);
        }

        /// Return the lowest bit stored in the the register as a u8.
        pub fn lsb(self: *ShiftReg16) u8 {
            return self.curr_tile & 0b1;
        }

        /// Set the pattern table data for the next tile.
        pub fn setNext(self: *ShiftReg16, value: u8) void {
            self.next_tile = value;
        }
    };

    const ShiftReg8 = u8;

    /// Flags for the PPUCTRL register.
    pub const FlagCTRL = packed struct {
        // selects one out of 4 name tables.
        // 0: $2000; 1: $2400; 2: $2800; 3: $2C00
        nametable_number: u2 = 0,
        // 0: add 1; 1: add 32
        increment_mode: bool = false,
        pattern_sprite: bool = false,
        pattern_background: bool = false,
        sprite_size: bool = false,
        slave_mode: bool = false,
        generate_nmi: bool = false,
    };

    /// Flags for the PPUMask register.
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

    /// Fetch a byte of data from one of the two pattern tables.
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

    /// Fetch a byte of data from the attribute table based on the current value of the
    /// `vram_addr` (v) register.
    fn fetchAttrTableByte(self: *Self) u8 {
        var coarse_x: u16 = self.vram_addr.coarse_x;
        var coarse_y: u16 = self.vram_addr.coarse_y;

        var at_x = coarse_x / 4;
        var at_y = coarse_y / 4;

        var nt_number: u16 = self.vram_addr.nametable;
        std.debug.assert(nt_number < 4);
        var at_base_addr = nametable_base_addr +
            (nametable_size * nt_number) +
            0x3C0; // each nametable is 960 bytes long.

        var at_addr = at_base_addr + at_y * 8 + at_x;
        std.debug.assert(at_addr >= at_base_addr and at_addr < at_base_addr + 64);

        return self.busRead(at_addr);
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

    /// Render a pixel to the frame buffer.
    fn renderPixel(self: *Self) void {
        // Fetch the pattern table bits for the current pixel.
        // Use that to select a color from the palette.
        // TODO: select the palette based on the attribute table.
        var lo_bit = self.pattern_table_shifter_lo.lsb();
        var hi_bit = self.pattern_table_shifter_hi.lsb();
        var color_index = hi_bit << 1 | lo_bit;
        var color_id = self.busRead(bg_palette_base_addr + color_index);
        std.debug.assert(color_id < 64);

        if (self.frame_buffer_pos >= self.frame_buffer.len) {
            var row = self.frame_buffer_pos / 256;
            var col = self.frame_buffer_pos % 256;
            std.debug.panic(
                "Frame buffer overflow at SC {}, dot {}, coord({}, {})\n",
                .{ self.current_scanline, self.cycle, row, col },
            );
        }

        // std.debug.print(
        // "[SC {}, dot {}, coord({}, {}), coarse-x: {}, coarse-y: {}]\n",
        // .{ self.current_scanline, self.cycle, row, col, self.vram_addr.coarse_x, self.vram_addr.coarse_y },
        // );

        self.frame_buffer[self.frame_buffer_pos] = color_id;
        var render_buf_index = self.frame_buffer_pos * 3;
        var color = Palette[color_id];
        self.render_buffer[render_buf_index] = color.r;
        self.render_buffer[render_buf_index + 1] = color.g;
        self.render_buffer[render_buf_index + 2] = color.b;
        self.frame_buffer_pos += 1;
    }

    /// Load data from internal registers into the shift registers.
    /// This function should be called on every visible cycle that is a multiple of 8.
    fn reloadBgRegisters(self: *Self) void {
        self.pattern_table_shifter_lo.next_tile = self.pattern_lo;
        self.pattern_table_shifter_hi.next_tile = self.pattern_hi;
        // TODO: also load the palette latch
    }

    /// Shift the background shift registers by one bit.
    /// ------------------------------------------------
    /// The NES contains shift registers that store pattern table data for background tiles.
    /// Every clock cycle, the contents of these registers are shifted by one bit.
    /// The bit that is shifted out represents the color of the current pixel.
    fn shiftBgRegsiters(self: *Self) void {
        self.pattern_table_shifter_lo.shift();
        self.pattern_table_shifter_hi.shift();
    }

    /// Based on the current sub-cycle, load background tile data
    /// (from pattern table/ attr table/ name table)
    /// into internal latches or shift registers.
    /// Ref: https://www.nesdev.org/w/images/default/4/4f/Ppu.svg
    fn fetchBgTile(self: *Self, subcycle: u16) void {
        switch (subcycle) {
            // fetch the name table byte.
            2 => self.nametable_byte = self.fetchNameTableByte(),
            4 => self.attr_table_byte = self.fetchAttrTableByte(),
            // Fetch the low bit plane of the pattern table for the next tile.
            6 => self.pattern_lo = self.fetchFromPatternTable(
                self.nametable_byte,
                true,
            ),

            // Fetch the high bitplane of the pattern table for the next tile.
            0 => {
                self.pattern_hi = self.fetchFromPatternTable(
                    self.nametable_byte,
                    false,
                );
                // On every (8*N)th clock cycle, load the background shifters with
                // tile data for the next tile.
                self.reloadBgRegisters();
                self.incrCoarseX();
            },
            // Fetch the high bit plane of the pattern table for the next tile.
            else => {},
        }
    }

    /// Execute one tick in a visible scanline.
    /// This should only be called for cycles 1 to 255 (inclusive)
    /// in scalines 0 to 240 (inclusive). This should *not* be called for the pre-render scanline.
    fn visibleDot(self: *Self, subcycle: u16) void {
        // On every visible dot of a visible scanline, render a pixel.
        self.renderPixel();
        // shift the background registers by one bit.
        self.shiftBgRegsiters();
        // Fetch the attribute/PT/NT data for the next tile.
        self.fetchBgTile(subcycle);
    }

    /// Copy the vertical bits from the `t` register into the `v` register.
    fn resetVert(self: *Self) void {
        self.vram_addr.coarse_y = self.t.coarse_y;
        self.vram_addr.fine_y = self.t.fine_y;
        self.vram_addr.nametable = (self.vram_addr.nametable & 0b01) | (self.t.nametable & 0b10);
    }

    /// Copy the horizontal bits from the `t` register into the `v` register.
    fn resetHorz(self: *Self) void {
        self.vram_addr.coarse_x = self.t.coarse_x;
        self.vram_addr.nametable =
            (self.vram_addr.nametable & 0b10) | (self.t.nametable & 0b01);
    }

    /// Execute one tick of a visible scanline (0 to 239 inclusive)
    fn visibleScanline(self: *Self) void {
        // On the last cycle of the last visible scanline, reset the frame buffer position
        // so that we begin drawing the next frame from the 0th pixel in the buffer.
        if ((self.current_scanline == 239 and self.cycle == 340) or
            (self.current_scanline == 0 and self.cycle == 0))
        {
            self.frame_buffer_pos = 0;
        }

        var is_prerender_line = self.current_scanline == 261;

        // The 0th cycle is idle, nothing happens apart from regular rendering.
        if (self.cycle == 0) {
            self.renderPixel();
            self.shiftBgRegsiters();
            return;
        }

        if (is_prerender_line and self.cycle >= 280 and self.cycle <= 304) {
            self.resetVert();
        }

        var subcycle = self.cycle % 8;
        switch (self.cycle) {
            // 1 -> 255 are the visible dots.
            // On these dots, one pixel is rendered to the screen.
            1...255 => self.visibleDot(subcycle),

            256 => {
                self.incrY();
                self.incrCoarseX();
            },

            // Once we're done drawing the last pixel of a scanline,
            // reset the horizontal tile position in the `v` register.
            257 => self.resetHorz(),

            258, 260, 266, 305 => self.nametable_byte = self.fetchNameTableByte(),

            // In clocks 321...336, the PPU fetches tile data for the next scanline.
            321...336 => {
                self.shiftBgRegsiters();
                self.fetchBgTile(subcycle);
            },
            // Unused name table fetches
            338, 340 => self.nametable_byte = self.fetchNameTableByte(),
            // garbage nametable byte fetches.
            else => {},
        }
    }

    /// Excute a single clock cycle of the PPU.
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

        switch (self.current_scanline) {
            // pre-render scanline.
            261 => {
                if (self.cycle == 1) {
                    // clear the vblank flag.
                    self.ppu_status.is_vblank_active = false;
                    self.is_nmi_pending = false;
                }

                // Even on the pre-render scanline, the PPU
                // goes through the same motions as a visible scanline.
                // This is done to pre-fetch the tile-data of scanline-0.
                self.visibleScanline();
            },

            0...239 => self.visibleScanline(),

            // post-render scanline. Nothing happens
            240 => {},
            241 => {
                if (self.cycle == 1) {
                    // set the vblank flag.
                    self.ppu_status.is_vblank_active = true;
                    if (self.ppu_ctrl.generate_nmi) {
                        self.is_nmi_pending = true;
                    }
                }
            },

            242...260 => {
                // Idle scanlines. Nothing happens.
                // Also known as the "VBLANK" phase.
                // The CPU freely access the PPU contents during this time.
            },

            else => unreachable,
        }
    }

    /// Write a byte to $2005 of CPU address space (PPUSCROLL register).
    pub fn writePPUScroll(self: *Self, byte: u8) void {
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
            // 1. Get the lower 6 bits of the operand byte, and
            // 2. Set the bits 9-14 of the t register.
            // 3. Clear the 15th bit of the t register.
            var t: u15 = @bitCast(self.t);
            var addr_hi: u15 = value & 0b00_111111;
            // Note that the 15th bit of t is also being cleared here.
            // Because the address space of the PPU is 14-bits, the 15-bit bit is always 0.
            t = (t & 0b0_000_000_1111_1111) | (addr_hi << 8);
            self.t = @bitCast(t);
        } else {
            // Write the byte to the lower 8 bits of t.
            var t: u15 = @bitCast(self.t);
            var lo: u15 = value;
            // Clear the existing lower 8 bits of t.
            // Then set the lower 8 bits of t to the operand byte.
            t = (t & 0b1111_111_0000_0000) | lo;
            self.t = @bitCast(t);
            self.vram_addr = self.t;
        }

        self.is_first_write = !self.is_first_write;
    }

    /// Read the PPUSTATUS register.
    /// This will reset the address latch, and clear the vblank flag.
    fn readPPUStatus(self: *Self) u8 {
        self.is_first_write = true;
        self.ppu_status.is_vblank_active = false;
        return @bitCast(self.ppu_status);
    }

    /// Write a byte of data to the address pointed to by the PPUADDR register.
    fn writePPUData(self: *Self, value: u8) void {
        // TODO: should I use t or v here?
        var t: u15 = @bitCast(self.t);
        self.busWrite(t, value);
        // TODO: increment the address based on the PPUCTRL register.
    }

    /// Read a byte of data from the address pointed to by the PPUADDR register.
    /// Reading from PPUDATA register reads from PPUADDR.
    fn readFromPPUAddr(self: *Self) u8 {
        var t: u15 = @bitCast(self.t);
        return self.busRead(t);
    }

    pub fn busWrite(self: *Self, addr: u16, value: u8) void {
        // TODO: mirroring, increment `v`
        self.ppu_ram[addr] = value;
    }

    pub fn busRead(self: *Self, addr: u16) u8 {
        // TODO: mirroring.
        return self.ppu_ram[addr];
    }

    /// Write a byte of data to the PPU registers.
    /// The address must be in range [0, 7].
    pub fn ppuWrite(self: *Self, addr: u16, val: u8) void {
        switch (addr) {
            0 => {
                self.ppu_ctrl = @bitCast(val);
                // Writing to PPUCTRL also sets the nametable number in the `t` register.
                self.t.nametable = self.ppu_ctrl.nametable_number;
            },
            1 => self.ppu_mask = @bitCast(val),
            2 => self.ppu_status = @bitCast(val),
            // TODO: OAMADDR, OAMDATA
            3...4 => unreachable,
            5 => self.writePPUScroll(val),
            6 => self.setPPUAddr(val),
            7 => self.writePPUData(val),
            else => unreachable,
        }
    }

    /// Read a byte of data from one of the PPU registers.
    /// The address must be in range [0, 7].
    pub fn ppuRead(self: *Self, addr: u16) u8 {
        switch (addr) {
            0 => return @bitCast(self.ppu_ctrl),
            1 => return @bitCast(self.ppu_mask),
            2 => return self.readPPUStatus(),
            // TODO: OAMADDR, OAMDATA, PPUSCROLL
            3...6 => unreachable,
            7 => return self.readFromPPUAddr(),
            else => unreachable,
        }
    }

    /// Load the pattern table pixel colors into a buffer.
    pub fn getPatternTableData(self: *Self, buf: []u8, pt_index: u16, palette_index: u16) void {
        if (buf.len != pattern_table_size_px) {
            std.debug.panic("Buffer must be of size {d}\n", .{pattern_table_size_px});
        }

        if (pt_index != 0 and pt_index != 1) {
            std.debug.panic("Pattern table index must be either 0 or 1 \n", .{});
        }

        if (palette_index > 3) {
            std.debug.panic("Palette index must be in range [0, 3]\n", .{});
        }

        for (0..16) |y| { // iterate over row of tiles in the pattern table.
            var tile_y: u16 = @truncate(y);
            for (0..16) |x| { // iterate over tiles in the PT row.
                var tile_x: u16 = @truncate(x);
                // address of the first byte of the tile in the pattern table.
                // This is used to index the pattern table in PPU RAM.
                var tile_offset = tile_y * 256 + tile_x * 16;
                var pt_addr = pt_index * 0x1000 + tile_offset;

                for (0..8) |pxrow| { // a row of pixels within the tile.
                    var px_row: u16 = @truncate(pxrow);
                    // each row is 2 bytes – a low byte and high byte.
                    var lo_byte = self.busRead(pt_addr + px_row);
                    var hi_byte = self.busRead(pt_addr + px_row + 8);
                    // loop over each pixel in the first row of the 8x8 tile.
                    for (0..8) |px| {
                        var lo_bit = (lo_byte >> @truncate(px)) & 0b1;
                        var hi_bit = (hi_byte >> @truncate(px)) & 0b1;

                        var color_index = hi_bit << 1 | lo_bit;
                        var color_id = self.busRead(bg_palette_base_addr + 16 * palette_index + color_index);

                        // address of the pixel in the buffer.
                        // it took me a good while to figure this out. OOF
                        var buf_addr_row = tile_y * 8 + px_row;
                        var buf_addr_col = tile_x * 8 + (7 - px);
                        var buf_addr = buf_addr_row * 128 + buf_addr_col;
                        std.debug.assert(buf_addr < buf.len);
                        buf[buf_addr] = color_id;
                    }
                }
            }
        }
    }
};

test "(PPU) fetching NT and AT bytes based on `v` register" {
    var ppu = PPU{};

    ppu.vram_addr.nametable = 2; // 3rd nametable
    ppu.vram_addr.coarse_x = 3;
    ppu.vram_addr.coarse_y = 5;
    ppu.vram_addr.fine_y = 0;

    ppu.ppu_ram[11208] = 42;
    ppu.ppu_ram[10403] = 69;

    var at_byte = ppu.fetchAttrTableByte();
    try std.testing.expectEqual(@as(u8, 42), at_byte);

    var nt_byte = ppu.fetchNameTableByte();
    try std.testing.expectEqual(@as(u8, 69), nt_byte);
}

test "(PPU) writing to $2006" {
    var ppu = PPU{};
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
    var ppu = PPU{};
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
