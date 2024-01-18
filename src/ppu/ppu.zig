const std = @import("std");
const palette = @import("./ppu-colors.zig");
const Mapper = @import("../mappers/mapper.zig").Mapper;
const CPU = @import("../cpu.zig").CPU;

pub const Color = palette.Color;
pub const Palette = palette.Palette;

/// `reversed_bits[0b0000_1111] = 0b1111_0000`
const reversed_bits = [256]u8{
    0x00, 0x80, 0x40, 0xc0, 0x20, 0xa0, 0x60, 0xe0,
    0x10, 0x90, 0x50, 0xd0, 0x30, 0xb0, 0x70, 0xf0,
    0x08, 0x88, 0x48, 0xc8, 0x28, 0xa8, 0x68, 0xe8,
    0x18, 0x98, 0x58, 0xd8, 0x38, 0xb8, 0x78, 0xf8,
    0x04, 0x84, 0x44, 0xc4, 0x24, 0xa4, 0x64, 0xe4,
    0x14, 0x94, 0x54, 0xd4, 0x34, 0xb4, 0x74, 0xf4,
    0x0c, 0x8c, 0x4c, 0xcc, 0x2c, 0xac, 0x6c, 0xec,
    0x1c, 0x9c, 0x5c, 0xdc, 0x3c, 0xbc, 0x7c, 0xfc,
    0x02, 0x82, 0x42, 0xc2, 0x22, 0xa2, 0x62, 0xe2,
    0x12, 0x92, 0x52, 0xd2, 0x32, 0xb2, 0x72, 0xf2,
    0x0a, 0x8a, 0x4a, 0xca, 0x2a, 0xaa, 0x6a, 0xea,
    0x1a, 0x9a, 0x5a, 0xda, 0x3a, 0xba, 0x7a, 0xfa,
    0x06, 0x86, 0x46, 0xc6, 0x26, 0xa6, 0x66, 0xe6,
    0x16, 0x96, 0x56, 0xd6, 0x36, 0xb6, 0x76, 0xf6,
    0x0e, 0x8e, 0x4e, 0xce, 0x2e, 0xae, 0x6e, 0xee,
    0x1e, 0x9e, 0x5e, 0xde, 0x3e, 0xbe, 0x7e, 0xfe,
    0x01, 0x81, 0x41, 0xc1, 0x21, 0xa1, 0x61, 0xe1,
    0x11, 0x91, 0x51, 0xd1, 0x31, 0xb1, 0x71, 0xf1,
    0x09, 0x89, 0x49, 0xc9, 0x29, 0xa9, 0x69, 0xe9,
    0x19, 0x99, 0x59, 0xd9, 0x39, 0xb9, 0x79, 0xf9,
    0x05, 0x85, 0x45, 0xc5, 0x25, 0xa5, 0x65, 0xe5,
    0x15, 0x95, 0x55, 0xd5, 0x35, 0xb5, 0x75, 0xf5,
    0x0d, 0x8d, 0x4d, 0xcd, 0x2d, 0xad, 0x6d, 0xed,
    0x1d, 0x9d, 0x5d, 0xdd, 0x3d, 0xbd, 0x7d, 0xfd,
    0x03, 0x83, 0x43, 0xc3, 0x23, 0xa3, 0x63, 0xe3,
    0x13, 0x93, 0x53, 0xd3, 0x33, 0xb3, 0x73, 0xf3,
    0x0b, 0x8b, 0x4b, 0xcb, 0x2b, 0xab, 0x6b, 0xeb,
    0x1b, 0x9b, 0x5b, 0xdb, 0x3b, 0xbb, 0x7b, 0xfb,
    0x07, 0x87, 0x47, 0xc7, 0x27, 0xa7, 0x67, 0xe7,
    0x17, 0x97, 0x57, 0xd7, 0x37, 0xb7, 0x77, 0xf7,
    0x0f, 0x8f, 0x4f, 0xcf, 0x2f, 0xaf, 0x6f, 0xef,
    0x1f, 0x9f, 0x5f, 0xdf, 0x3f, 0xbf, 0x7f, 0xff,
};

/// Emulator for the NES PPU.
pub const PPU = struct {
    pub const ScreenWidth = 256;
    pub const ScreenHeight = 240;
    pub const NPixels = ScreenWidth * ScreenHeight;

    /// Base address of nametables in PPU memory.
    const nametable_base_addr: u16 = 0x2000;
    /// Nametable bytes + attribute bytes = 1024 bytes total.
    const nametable_size = 0x400;
    /// Base address of palettes for background rendering
    const bg_palette_base_addr: u16 = 0x3F00;
    /// Size of each palette in bytes (= 4).
    const palette_size: u16 = 4;

    /// Base address of palettes for foreground rendering
    const fg_palette_base_addr: u16 = 0x3F10;

    /// size of each pattern table (16 x 16 tiles * 8 bytes per bit-plane * 2 bit-planes per tile)
    pub const pattern_table_size: u16 = 16 * 16 * 8 * 2; // 0x1000
    pub const pattern_table_size_px: u16 = 128 * 128;

    /// A reference to the CPU connected to this PPU device.
    cpu: *CPU,

    /// When `true`, it means the PPU has generated an NMI interrupt,
    /// and the CPU needs to handle it.
    is_nmi_pending: bool = false,

    /// In reality, the PPU RAM is only 2kB in size.
    /// $3000 - $EFFF is a mirror of $2000 - $2EFF.
    /// $0000 - $1FFF is mapped to the CHR ROM.
    /// Therefore, all indices below $2000 in this buffer are unused.
    /// The only reason I'm allocating 64kB is because it's easier to
    /// directly use PPU memory addresses as indices into this buffer.
    ppu_ram: [0x10000]u8 = [_]u8{0} ** 0x10000,

    ppu_ctrl: FlagCTRL = .{},
    ppu_mask: FlagMask = .{},

    // NOTE: reading from this register resets the address latch.
    // read-only
    ppu_status: FlagStatus = .{},

    // OAM registers and memory.
    oam_addr: u8 = 0, // $2003
    oam_data: u8 = 0, // $2004
    oam_dma: u8 = 0, // $4014
    // Stores the sprite data for 64 sprites.
    oam: [256]u8 = [_]u8{0} ** 256,
    /// Secondary OAM stores the sprites for the current scanline (for upto 8 sprites).
    /// Each sprite uses 4 bytes (Y-pos, PT tile-index, attributes, X-pos).
    /// Therefore, secondary OAM is 32 bytes long (8 sprites * 4 bytes for each sprite).
    secondary_oam: [32]u8 = [_]u8{0} ** 32,

    /// Number of sprites currently present in the secondary OAM and sprite latches.
    num_sprites_on_scanline: u8 = 0,
    /// `true` if the current scanline has sprite 0 in it.
    scanline_has_sprite0: bool = false,

    // We want the PPU to start on the pre-render scanline.
    // So the scanline and dot are set to 260, and 240 respectively.
    // When the first tick() is called, the scanline and dot will be
    // incremented to 261 and 0 respectively.
    cycle: u16 = 340,
    current_scanline: u16 = 260,

    /// Current position inside the frame buffer.
    /// This depends on the current scanline and cycle.
    frame_buffer_pos: usize = 0,

    /// A 256x240 1D array of color IDs that is filled in dot-by-dot by the CPU.
    /// A color ID is an index into the 64-color palette of the NES.
    frame_buffer: [NPixels]u8 = .{0} ** NPixels,

    /// The actual buffer that should be drawn to the screen every frame by raylib.
    /// Note that this is stored in R8G8B8 format (24 bits-per-pixel).
    /// I store it like this so its easier to pass it to raylib for rendering
    /// using the PIXELFORMAT_UNCOMPRESSED_R8G8B8.
    render_buffer: [NPixels * 3]u8 = .{0} ** (NPixels * 3),

    /// This corresponds to the `v` register of the PPU.
    /// Stores the current VRAM address when loading tile and sprite data.
    vram_addr: VRamAddr = .{},

    /// The "t" register is the "source of truth" for the base vram address.
    /// It gets written to when the programmer sets PPUADDR.
    t: VRamAddr = .{},

    /// The write toggle bit.
    /// This is shared by PPU registers at $2005 and $2006
    /// NOTE: Because this variable is called "is_first_write", its value
    /// will be opposite to NES PPU's toggle bit.
    /// In a real PPU, this bit is 0 when its doing the first write,
    /// and becomes 1 when its time to do the second write.
    /// In my case, its `true` when its time to do the first write,
    /// and becomes `false` when its time to do the second write.
    is_first_write: bool = true,

    /// In the original 2A03 chip, this was a 3-bit register.
    /// But mine is a u8 just so a modern CPU can crunch this number quick.
    fine_x: u8 = 0,

    /// A latch that contains the name table byte for the next tile.
    nametable_byte: u8 = 0,

    /// Every 8 cycles, the PPU makes fetches the pattern table data for the next tile,
    /// and stores the data into two internal latches (one for high bit plane, and one for low).
    /// These bytes in these latches are then loaded into shift registers that
    /// are shifted once every dot.
    ///
    /// The "latches" are filled with data on specific cycles of
    /// visible scanlines (and the pre-render scanline) as described here:
    /// https://www.nesdev.org/w/images/default/4/4f/Ppu.svg
    pattern_lo: u8 = 0,
    pattern_hi: u8 = 0,
    /// Storesthe 2-bit palete index for the next tile.
    /// This latch is loaded on every 8th visible clock-cycle.
    bg_palette_latch: u8 = 0,
    /// Stores the 8-bit attribute byte for the next tile.
    bg_attr_latch: u8 = 0,

    /// Shift registers that hold the pattern table data for the current and next tile.
    /// Every 8 cycles, the data for the next tile is loaded into the upper 8 bits (next_tile).
    pattern_table_shifter_lo: ShiftReg16 = .{},
    pattern_table_shifter_hi: ShiftReg16 = .{},
    bg_palette_shifter_lo: u8 = 0,
    bg_palette_shifter_hi: u8 = 0,

    /// To access the CHR-ROM (and possibly other data on the cartridge),
    /// The PPU bus is connected to a Mapper on the cartridge.
    mapper: *Mapper,

    /// Internal latches that store sprite data for the current scanline.
    sprites_on_scanline: [8]Sprite = .{.{}} ** 8,

    const Self = @This();

    /// A Foreground sprite.
    /// This struct is loaded from secondary OAM into sprite latches between cycles 257 and 320.
    const Sprite = struct {
        x: u8 = 0,
        y: u8 = 0,
        /// lo bitplane of the pattern byte belonging to this sprite.
        pattern_lo: u8 = 0,
        /// hi bitplane of the pattern byte belonging to this sprite.
        pattern_hi: u8 = 0,
        /// Attributes of the sprite.
        attr: SpriteAttributes = .{},
    };

    /// Internal representation of a foreground sprite (8x8)
    const SpriteAttributes = packed struct {
        /// The palette number to use for this sprite.
        palette: u2 = 0,
        __unused: u3 = 0,
        is_behind_bg: bool = false,
        flip_horz: bool = false,
        flip_vert: bool = false,

        comptime {
            std.debug.assert(@bitSizeOf(SpriteAttributes) == 8);
        }
    };

    /// 16-bit shift register to hold pattern-table data.
    /// Every 8 cycles, the data for the next tile is loaded into the upper 8 bits (next_tile).
    /// When the current pixel is fetched, the data in this register is shifted by 1 bit.
    pub const ShiftReg16 = packed struct {
        /// NOTE: The order of these two fields matter!
        /// A sliver of pattern table bits for the current tile being rendered.
        curr_tile: u8 = 0,
        /// A sliver of pattern table bits The next tile to be rendered.
        next_tile: u8 = 0,

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

        pub fn nextTile(self: *ShiftReg16, tile: u8) void {
            self.next_tile = reversed_bits[tile];
        }
    };

    /// Flags for the PPUCTRL register.
    pub const FlagCTRL = packed struct {
        /// selects one out of 4 name tables.
        /// 0: $2000; 1: $2400; 2: $2800; 3: $2C00
        nametable_number: u2 = 0,
        /// 0: add 1; 1: add 32
        increment_mode_32: bool = false,
        /// The pattern table to use for drawing sprites. (0 = left; 1 = right)
        pattern_sprite: bool = false,
        /// The pattern table to use for drawing the background. (0 = left; 1 = right)
        pattern_background: bool = false,
        /// 0: 8x8; 1: 8x16
        sprite_is_8x16: bool = false,
        slave_mode: bool = false,
        /// If set, the PPU will trigger an NMI when it enters VBLANK.
        generate_nmi: bool = false,
    };

    /// Flags for the PPUMask register.
    pub const FlagMask = packed struct {
        is_grayscale: bool = false,
        left_bg: bool = false,
        left_fg: bool = false,
        draw_bg: bool = false,
        draw_sprites: bool = false,
        enhance_red: bool = false,
        enhance_green: bool = false,
        enhance_blue: bool = false,
    };

    // flags for the PPUStatus register.
    pub const FlagStatus = packed struct {
        _ppu_open_bus_unused: u5 = 0,
        sprite_overflow: bool = false,
        sprite_zero_hit: bool = false,
        in_vblank: bool = false,
    };

    /// The internal `t` and `v` registers have
    /// their bits arranged like this:
    pub const VRamAddr = packed struct {
        coarse_x: u5 = 0,
        coarse_y: u5 = 0,
        nametable: u2 = 0,
        fine_y: u3 = 0,
        comptime {
            std.debug.assert(@bitSizeOf(VRamAddr) == 15);
        }
    };

    pub fn init(cpu: *CPU, mapper: *Mapper) PPU {
        return Self{ .mapper = mapper, .cpu = cpu };
    }

    /// Fetch a byte of data from one of the two pattern tables.
    ///
    /// `addr`: Address of the tile to fetch (0-256)
    ///
    /// `is_low_plane`: `true` if we're fetching the low bitplane.
    ///
    /// `pt_number`: 0 if we're fetching from the PT at $0000, 1 if we're using the one at $1000
    ///
    /// `row`: The row of the tile to fetch (0-7)
    fn fetchFromPatternTable(self: *Self, addr: u16, is_low_plane: bool, pt_number: u1, row: u8) u8 {
        std.debug.assert(row < 8);
        var pt_addr = (@as(u16, pt_number) * 0x1000) + (addr * 16) + row;
        return if (is_low_plane) self.busRead(pt_addr) else self.busRead(pt_addr + 8);
    }

    /// Fetch a byte of data from the pattern table for background use.
    /// The pattern table is chosen from the `pattern_background` bit of the PPUCTRL register.
    ///
    /// `addr`: Index of the tile to fetch from within the pattern table (0-256)
    ///
    /// `is_low_plane`: `true` if we're fetching a byte from the low-bitplane of the tile.
    fn fetchPatternTableBG(self: *Self, addr: u16, is_low_plane: bool) u8 {
        var pt_number: u1 = if (self.ppu_ctrl.pattern_background) 1 else 0;
        return self.fetchFromPatternTable(addr, is_low_plane, pt_number, self.vram_addr.fine_y);
    }

    /// Fetch a byte of data from the pattern table for foreground use.
    /// The pattern table is chosen from the `pattern_sprite` bit of the PPUCTRL register.
    ///
    /// `addr`: Index of the tile to fetch from within the pattern table (0-256)
    ///
    /// `is_low_plane`: `true` if we're fetching a byte from the low-bitplane of the tile.
    fn fetchSpritePattern(self: *Self, addr: u16, is_low_plane: bool, row: u8) u8 {
        var pt_number: u1 = if (self.ppu_ctrl.pattern_sprite) 1 else 0;
        return self.fetchFromPatternTable(addr, is_low_plane, pt_number, row);
    }

    /// Fetch the next byte from the name table.
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

    /// Fetch the 8-bit attribute byte for the tile at the current VRAM address.
    fn fetchAttrTableByte(self: *Self) u8 {
        var tile_col: u8 = self.vram_addr.coarse_x;
        var tile_row: u8 = self.vram_addr.coarse_y;

        var at_col: u16 = tile_col / 4;
        var at_row: u16 = tile_row / 4;

        var nt_number: u16 = self.vram_addr.nametable;
        std.debug.assert(nt_number < 4);
        var at_base_addr = nametable_base_addr +
            (nametable_size * nt_number) +
            0x3C0; // each nametable is 960 bytes long.

        var at_offset = at_row * 8 + at_col;
        var at_addr = at_base_addr + at_offset;

        std.debug.assert(at_addr >= at_base_addr and at_addr < at_base_addr + 64);
        return self.busRead(at_addr);
    }

    /// Increment the fine and coarse Y based on the current clock cycle.
    fn incrY(self: *Self) void {
        var fine_y: u8 = self.vram_addr.fine_y;
        var coarse_y: u8 = self.vram_addr.coarse_y;
        if (fine_y == std.math.maxInt(@TypeOf(self.vram_addr.fine_y))) {
            // reset fine-y to 0, now that we're on the first pixel of the next tile.
            fine_y = 0;
            if (coarse_y == 29) {
                // If we were on the last tile of current scanline,
                // wrap back to first tile of next scanline.
                coarse_y = 0;
            } else if (coarse_y == 31) {
                // I don't fully understand this part yet.
                coarse_y = 0;
                // goto next vertical nametable. (0 -> 2, 1 -> 3)
                self.vram_addr.nametable ^= 0b10;
            } else {
                coarse_y += 1;
            }
        } else {
            fine_y += 1;
        }

        self.vram_addr.fine_y = @truncate(fine_y);
        self.vram_addr.coarse_y = @truncate(coarse_y);
    }

    /// Increment the coarse X based on the current clock cycle.
    /// Once we're past the last tile, we wrap to the first tile of the
    /// next nametable.
    fn incrCoarseX(self: *Self) void {
        var coarse_x: u8 = self.vram_addr.coarse_x;
        if (coarse_x < std.math.maxInt(u5)) {
            coarse_x += 1;
        } else {
            coarse_x = 0;
            // Goto next horizontal nametable. (0 -> 1, 2 -> 3)
            self.vram_addr.nametable ^= 0b01;
        }
        self.vram_addr.coarse_x = @truncate(coarse_x);
    }

    /// Fetch an address to the color of the current background pixel.
    fn fetchBGPixel(self: *Self) u16 {
        // Fetch the pattern table bits for the current pixel.
        // Use that to select a color from the palette.
        var pt_lo = self.pattern_table_shifter_lo.lsb();
        var pt_hi = self.pattern_table_shifter_hi.lsb();
        var color_index = pt_hi << 1 | pt_lo;

        var palette_lo = self.bg_palette_shifter_lo & 0b1;
        var palette_hi = self.bg_palette_shifter_hi & 0b1;
        var palette_index = palette_hi << 1 | palette_lo;
        var palette_base_addr = bg_palette_base_addr + palette_index * palette_size;
        return palette_base_addr + color_index;
    }

    /// Write a pixel to the frame buffer.
    fn renderPixel(self: *Self) void {
        var color_addr = self.fetchBGPixel();
        if (self.frame_buffer_pos >= self.frame_buffer.len) {
            var row = self.frame_buffer_pos / 256;
            var col = self.frame_buffer_pos % 256;
            std.debug.panic(
                "Frame buffer overflow at SC {}, dot {}, coord({}, {})\n",
                .{ self.current_scanline, self.cycle, row, col },
            );
        }

        // Visit all the sprite latches and see if any of the sprites in
        // there should be drawn on top of the background.
        // Ref: https://www.nesdev.org/wiki/PPU_sprite_priority
        for (0..self.num_sprites_on_scanline) |i| {
            var sprite = self.sprites_on_scanline[i];
            var sprite_x_start = sprite.x;
            var sprite_x_end = @addWithOverflow(sprite_x_start, 8)[0];
            var current_x = self.cycle;
            if (current_x >= sprite_x_start and current_x < sprite_x_end) {
                var lo_bitplane = sprite.pattern_lo;
                var hi_bitplane = sprite.pattern_hi;
                var pxcol = current_x - sprite_x_start;
                var color_hi = (hi_bitplane >> @truncate(7 - pxcol)) & 0b1;
                var color_lo = (lo_bitplane >> @truncate(7 - pxcol)) & 0b1;

                // index of the color inside a palette (0-4)
                var color_index: u16 = color_hi << 1 | color_lo;
                // The sprite pixel only gets drawn on top of the background pixel if:
                // 1. The sprite pixel is opaque (i.e not color 0, 4, 8, 12), AND has front priority.
                // 2. The background pixel is transparent (i.e color 0, 4, 8, 12 in the background palette).
                var is_sprite_px_opaque = color_index % 4 != 0;
                var is_sprite_fg = !sprite.attr.is_behind_bg;
                var is_bg_transparent = (color_addr - bg_palette_base_addr) % 4 == 0;

                if (is_sprite_px_opaque and (is_sprite_fg or is_bg_transparent)) {
                    var palette_index: u16 = sprite.attr.palette;
                    color_addr = fg_palette_base_addr + palette_index * palette_size + color_index;
                    // If opaque pixel of sprite#0 from OAM overlaps opaque pixel of background,
                    // set the sprite 0 hit flag.
                    if (i == 0 and self.scanline_has_sprite0 and !is_bg_transparent) {
                        self.ppu_status.sprite_zero_hit = true;
                    }
                }

                break;
            }
        }

        var color_id = self.busRead(color_addr);
        var color = Palette[color_id];
        self.frame_buffer[self.frame_buffer_pos] = color_id;
        var render_buf_index = self.frame_buffer_pos * 3;
        self.render_buffer[render_buf_index] = color.r;
        self.render_buffer[render_buf_index + 1] = color.g;
        self.render_buffer[render_buf_index + 2] = color.b;
        self.frame_buffer_pos += 1;
    }

    /// Load data from internal latches into the two background shift registers that store pattern table data.
    /// The palette latch is also reloaded. The two 8-bit palette shift registers are not affected.
    /// This function should be called on every visible cycle that is a multiple of 8.
    fn reloadBgRegisters(self: *Self) void {
        self.pattern_table_shifter_lo.nextTile(self.pattern_lo);
        self.pattern_table_shifter_hi.nextTile(self.pattern_hi);

        // Load the 2-bit attribute latch from the 8-bit attribute latch.
        var tile_col: u8 = self.vram_addr.coarse_x;
        var tile_row: u8 = self.vram_addr.coarse_y;

        // Find the 2-bit palette index for the current tile from within the 8-bit attribute byte.
        var y = tile_row % 4;
        var x = tile_col % 4;
        var shift = (((y >> 1) & 1) << 1 | ((x >> 1) & 1)) * 2;
        std.debug.assert(shift < 8 and shift % 2 == 0);

        var palette_index = (self.bg_attr_latch >> @truncate(shift)) & 0b0000_0011;
        self.bg_palette_latch = palette_index;
    }

    /// Shift the background shift registers by one bit.
    /// ------------------------------------------------
    /// The NES contains shift registers that store pattern table data for background tiles.
    /// Every clock cycle, the contents of these registers are shifted by one bit.
    /// The bit that is shifted out represents the color of the current pixel.
    fn shiftBgRegsiters(self: *Self) void {
        self.pattern_table_shifter_lo.shift();
        self.pattern_table_shifter_hi.shift();
        self.bg_palette_shifter_lo = self.bg_palette_shifter_lo >> 1;
        self.bg_palette_shifter_hi = self.bg_palette_shifter_hi >> 1;
    }

    /// The PPU has two 8 bit shift registers, and a two 1-bit palette latches.
    /// The palette index is 2-bit, so each 1-bit latch stores a bit of the palette index.
    /// Every clock-cycle, the MSB of a shift register is loaded with the bit present in the 1 bit latch.
    /// Then, as the register shifts to the right, this data is propagated forward.
    fn loadPaletteShifters(self: *Self) void {
        var lo = self.bg_palette_shifter_lo;
        var hi = self.bg_palette_shifter_hi;
        lo = lo | ((self.bg_palette_latch & 0b01) << 7);
        hi = hi | ((self.bg_palette_latch & 0b10) << 6);
        self.bg_palette_shifter_lo = lo;
        self.bg_palette_shifter_hi = hi;
    }

    /// Based on the current sub-cycle, load background tile data
    /// (from pattern table / attr table / name table)
    /// into internal latches or shift registers.
    /// Ref: https://www.nesdev.org/w/images/default/4/4f/Ppu.svg
    fn fetchBgTile(self: *Self, subcycle: u16) void {
        std.debug.assert(subcycle < 8);
        // On every clock cycle, copy the background palette latches into palette shift registers.
        self.loadPaletteShifters();
        switch (subcycle) {
            // fetch the name table byte.
            2 => self.nametable_byte = self.fetchNameTableByte(),
            // fetch the palette to use for the next tile from the attribute table.
            4 => self.bg_attr_latch = self.fetchAttrTableByte(),
            // Fetch the low bit plane of the pattern table for the next tile.
            6 => self.pattern_lo = self.fetchPatternTableBG(
                self.nametable_byte,
                true,
            ),
            // Fetch the high bitplane of the pattern table for the next tile.
            0 => {
                self.pattern_hi = self.fetchPatternTableBG(
                    self.nametable_byte,
                    false,
                );
                // On every (8*N)th clock cycle, load the background shifters with
                // tile data for the next tile.
                self.reloadBgRegisters();
                self.incrCoarseX();
            },
            else => {},
        }
    }

    /// Execute one tick in a visible scanline.
    /// This should only be called for cycles 1 to 255 (inclusive)
    /// in scanlines 0 to 240 (inclusive).
    /// This should *not* be called for the pre-render scanline.
    fn visibleDot(self: *Self, subcycle: u16) void {
        // On every visible dot of a visible scanline, render a pixel.
        self.renderPixel();
        // shift the background registers by one bit.
        self.shiftBgRegsiters();
        // Fetch the AT/PT/NT data for the next tile.
        self.fetchBgTile(subcycle);
    }

    /// Copy the vertical bits from the `t` register into the `v` register.
    /// This is done on the pre-render line (scanline 261) during cycles 280 to 304.
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

    /// copy the first 8 sprites on current scanline from primary OAM to secondary OAM.
    fn copySpritesToSecondaryOAM(self: *Self) void {
        var num_sprites: u8 = 0;
        for (0..64) |sprite_index| {
            // If we've already found 8 sprites, stop copying.
            if (num_sprites >= 8) break;

            var oam_index = 4 * sprite_index;
            var y: u16 = self.oam[oam_index];
            var screen_y = self.current_scanline;

            var is_visible_on_line = y <= screen_y and (y + 8) > screen_y;
            if (!is_visible_on_line) continue;

            // Does this scanline contain the 0th sprite from OAM?
            // (will be useful later to calculate the sprite zero hit flag)
            if (sprite_index == 0) self.scanline_has_sprite0 = true;

            // Since the sprite is visible on this scanline, copy all its bytes to secondary OAM.
            // Later, the pattern table bytes for these sprites will be loaded into the sprite latches.
            for (0..4) |attr_index| {
                self.secondary_oam[4 * num_sprites + attr_index] = self.oam[oam_index + attr_index];
            }
            num_sprites += 1;
        }

        self.num_sprites_on_scanline = num_sprites;
    }

    /// Sprite evaluation that occurrs on every dot of a visible scanline.
    /// Ref: https://www.nesdev.org/wiki/PPU_sprite_evaluation
    fn spriteEval(self: *Self) void {
        if (!self.ppu_mask.draw_sprites) return;

        if (self.cycle == 1) {
            for (0..32) |i| self.secondary_oam[i] = 0xFF;
        }

        // This should happen between scanlines 64 and 256, but I do it all at once on dot-64.
        if (self.cycle == 64) self.copySpritesToSecondaryOAM();

        // TODO: should I do these in a cycle accurate manner, since we're reading from the pattern table?
        if (self.cycle == 257) {
            for (0..self.num_sprites_on_scanline) |i| {
                std.debug.assert(i <= 7);
                var j = i * 4; // each sprite is 4 bytes long.
                var sprite_y = self.secondary_oam[j];
                var tile_index = self.secondary_oam[j + 1];
                var attrs: SpriteAttributes = @bitCast(self.secondary_oam[j + 2]);
                var sprite_x = self.secondary_oam[j + 3];

                std.debug.assert(self.current_scanline - sprite_y < 8);
                var row: u8 = @truncate(self.current_scanline - sprite_y);
                if (attrs.flip_vert) {
                    row = 7 - row;
                }

                var pt_lo = self.fetchSpritePattern(tile_index, true, row);
                var pt_hi = self.fetchSpritePattern(tile_index, false, row);

                if (attrs.flip_horz) {
                    pt_lo = reversed_bits[pt_lo];
                    pt_hi = reversed_bits[pt_hi];
                }

                var sprite: Sprite = .{
                    .y = sprite_y,
                    .x = sprite_x,
                    .pattern_lo = pt_lo,
                    .pattern_hi = pt_hi,
                    .attr = attrs,
                };

                self.sprites_on_scanline[i] = sprite;
            }
        }
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

        var draw_bg = self.ppu_mask.draw_bg;

        // The 0th cycle is idle, nothing happens apart from regular rendering.
        if (self.cycle == 0) {
            // TODO: handle bg and fg separately.
            if (draw_bg) {
                self.renderPixel();
                self.shiftBgRegsiters();
            }
            return;
        }

        if (is_prerender_line) {
            if (self.cycle == 1) {
                self.ppu_status.sprite_zero_hit = false;
                self.scanline_has_sprite0 = false;
            } else if (self.cycle >= 280 and self.cycle <= 304 and draw_bg) {
                self.resetVert();
            }
        }

        // OAMADDR is zeroed out on dots 257-320 of pre-render and visible scanlines.
        if (self.cycle >= 257 and self.cycle <= 320) {
            self.oam_addr = 0;
        }

        if (self.ppu_mask.draw_sprites) {
            if (self.ppu_ctrl.sprite_is_8x16) {
                // TODO: support 8x16 sprites.
                std.debug.panic("8x16 mode not supported", .{});
            }
            self.spriteEval();
        }

        var subcycle = self.cycle % 8;
        switch (self.cycle) {
            // 1 -> 255 are the visible dots.
            // On these dots, one pixel is rendered to the screen.
            1...255 => {
                if (draw_bg) {
                    // TODO: check draw_sprites
                    self.visibleDot(subcycle);
                }
            },

            256 => {
                // TODO: check draw_sprites
                if (draw_bg) {
                    self.incrY();
                    self.incrCoarseX();
                }
            },

            // Once we're done drawing the last pixel of a scanline,
            // reset the horizontal tile position in the `v` register.
            257 => {
                if (draw_bg) {
                    self.resetHorz();
                }
            },

            258, 260, 266, 305 => if (draw_bg) {
                self.nametable_byte = self.fetchNameTableByte();
            },

            // In clocks 321...336, the PPU fetches tile data for the next scanline.
            321...336 => if (draw_bg) {
                self.shiftBgRegsiters();
                self.fetchBgTile(subcycle);
            },
            // Unused name table fetches
            338, 340 => if (draw_bg) {
                self.nametable_byte = self.fetchNameTableByte();
            },
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
                    self.ppu_status.in_vblank = false;
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
                    self.ppu_status.in_vblank = true;
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
    pub fn writePPUADDR(self: *Self, value: u8) void {
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
        var status: u8 = @bitCast(self.ppu_status);
        self.is_first_write = true;
        self.ppu_status.in_vblank = false;
        return status;
    }

    /// Write a byte of data to the address pointed to by the PPUADDR register.
    /// This will also auto-increment the PPUADDR register by an amount that depends
    /// on the value of a control bit in the PPUCTRL register.
    fn writePPUDATA(self: *Self, value: u8) void {
        var addr: u15 = @bitCast(self.vram_addr);
        self.busWrite(addr, value);
        var addr_increment: u15 = if (self.ppu_ctrl.increment_mode_32) 32 else 1;
        addr = @addWithOverflow(addr, addr_increment)[0];
        self.vram_addr = @bitCast(addr);
    }

    /// Read a byte of data from the address pointed to by the PPUADDR register.
    /// Reading from PPUDATA register reads from PPUADDR.
    fn readPPUDATA(self: *Self) u8 {
        var addr: u15 = @bitCast(self.vram_addr);
        var data = self.busRead(addr);
        var addr_increment: u15 = if (self.ppu_ctrl.increment_mode_32) 32 else 1;
        addr = @addWithOverflow(addr, addr_increment)[0];
        self.vram_addr = @bitCast(addr);
        return data;
    }

    fn busWrite(self: *Self, address: u16, value: u8) void {
        var addr = address; // parameters are immutable in Zig -_-
        if (addr < 0x2000) return self.mapper.ppuWrite(addr, value);

        if (addr >= 0x3000 and addr < 0x3F00) addr -= 0x1000;
        if (addr >= 0x3F20 and addr < 0x4000) addr -= 0x20;

        // universal transparent color mirroring.
        if (addr >= bg_palette_base_addr and (addr - bg_palette_base_addr) % 4 == 0) {
            addr = bg_palette_base_addr;
        }

        self.ppu_ram[addr] = value;
    }

    fn busRead(self: *Self, address: u16) u8 {
        var addr = address; // parameters are immutable in Zig -_-
        if (addr < 0x2000) return self.mapper.ppuRead(addr);
        // TODO: verify mirroring impl with the wiki.
        // $3000 - $3FEFF mirrors $2000 - $2EFF
        // $3F20 - $3FFF mirrors $3F00 - $3F1F
        if (addr >= 0x3000 and addr < 0x3F00) addr -= 0x1000;
        if (addr >= 0x3F20 and addr < 0x4000) addr -= 0x20;
        // universal transparent color mirroring.
        if (addr >= bg_palette_base_addr and (addr - bg_palette_base_addr) % 4 == 0) {
            addr = bg_palette_base_addr;
        }
        return self.ppu_ram[addr];
    }

    /// Perform a DMA transfer of 256 bytes from CPU memory to OAM memory.
    /// `oamDMA`: The byte that was written to OAMDMA register.
    /// (This function should be called when the CPU writes to $4014).
    pub fn writeOAMDMA(self: *Self, page_start: u16) void {
        // When writing to OAM memory, the programmer will write the
        // high byte of the CPU address to OAMADDR, and then write the
        // low byte of the CPU address to OAMDMA.
        // eg: This program transfers 256 bytes from $0200 to OAM.
        // LDA #$00
        // STA OAMADDR
        // LDA #$02
        // STA OAMDMA
        // TODO: make this async.
        var cpu_addr = page_start << 8;
        for (0..256) |_| {
            self.oam[self.oam_addr] = self.cpu.memRead(cpu_addr);
            self.oam_addr = @addWithOverflow(self.oam_addr, 1)[0];
            cpu_addr = @addWithOverflow(cpu_addr, 1)[0];
        }
        self.cpu.cycles_to_wait += 513;
    }

    /// Write a byte of data to the OAMDATA register.
    /// This will also increment the value in OAMADDR register.
    fn writeOAMDATA(self: *Self, value: u8) void {
        self.oam[self.oam_addr] = value;
        self.oam_addr = @addWithOverflow(self.oam_addr, 1)[0];
    }

    /// Write a byte of data to the PPU registers.
    /// The address must be in range [0, 7].
    pub fn writeRegister(self: *Self, addr: u16, val: u8) void {
        std.debug.assert(addr >= 0x2000 and addr < 0x4000);
        var register = addr & 0b111;

        switch (register) {
            0 => { // PPUCTRL
                self.ppu_ctrl = @bitCast(val);
                // Writing to PPUCTRL also sets the nametable number in the `t` register.
                self.t.nametable = self.ppu_ctrl.nametable_number;
            },
            1 => self.ppu_mask = @bitCast(val), // PPUMASK
            2 => self.ppu_status = @bitCast(val), // PPUSTATUS
            3 => self.oam_addr = val, // OAMADDR
            4 => self.writeOAMDATA(val), // OAMDATA
            5 => self.writePPUScroll(val), // PPUSCROLL
            6 => self.writePPUADDR(val), // PPUADDR
            7 => self.writePPUDATA(val), // PPUDATA
            else => unreachable,
        }
    }

    /// Read a byte of data from one of the PPU registers.
    /// The address must be in range [0, 7].
    pub fn readRegister(self: *Self, addr: u16) u8 {
        std.debug.assert(addr >= 0x2000 and addr < 0x4000);
        var register = addr & 0b111;

        // TODO: emulate the PPU's memory access timing delay.
        return switch (register) {
            2 => self.readPPUStatus(),
            4 => self.oam[self.oam_addr],
            7 => self.readPPUDATA(),
            // reading from any other register is undefined behavior
            else => 0,
        };
    }

    fn concat(allocator: std.mem.Allocator, one: []const u8, two: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ one, two });
    }

    /// Dump the contents of the name table to a buffer.
    pub fn dumpNameTable(self: *Self, allocator: std.mem.Allocator) !void {
        var buf = try allocator.alloc(u8, 0);
        defer allocator.free(buf);

        for (nametable_base_addr..nametable_base_addr + nametable_size) |i| {
            var byte = self.busRead(@truncate(i));

            if (i % 32 == 0) {
                var newBuf = try std.fmt.allocPrint(allocator, "\n[${x}]: ", .{i});
                defer allocator.free(newBuf);

                var tmp = try concat(allocator, buf, newBuf);
                allocator.free(buf);
                buf = tmp;
            }

            var newBuf = try std.fmt.allocPrint(allocator, "{x} ", .{byte});
            defer allocator.free(newBuf);

            var tmp = try concat(allocator, buf, newBuf);
            allocator.free(buf);
            buf = tmp;
        }

        std.debug.print("{s}\n", .{buf});
    }

    pub fn dumpSprites(self: *Self) !void {
        std.debug.print("OAM: \n", .{});
        for (0..256) |i| {
            if (i % 16 == 0) {
                std.debug.print("\n", .{});
                std.debug.print("${x:0>4}: ", .{i});
            }
            std.debug.print("${x:0>2} ", .{self.oam[i]});
        }
        std.debug.print("\nASCII View:\n", .{});
        for (0..256) |i| {
            if (i % 16 == 0) {
                std.debug.print("\n", .{});
            }
            var byte = self.oam[i];
            if (byte >= 0x20 and byte < 0x7F) {
                std.debug.print("{c}", .{byte});
            } else {
                std.debug.print(".", .{});
            }
        }
    }

    /// Load a 4-item buffer with colors from the specified PPU palette.
    pub fn getPaletteColors(self: *Self, is_background: bool, palette_index: u8) [4]u8 {
        std.debug.assert(palette_index < 4);

        var base_addr = if (is_background) bg_palette_base_addr else fg_palette_base_addr;

        var colors_buf: [4]u8 = undefined;
        for (0..4) |i| {
            var iu16: u16 = @truncate(i);
            colors_buf[i] = self.busRead(
                base_addr + // base address of PPU palette RAM
                    (palette_size * palette_index) + // offset to the palette
                    iu16, // offset to the color
            );
        }

        return colors_buf;
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
                        var addr = bg_palette_base_addr + 16 * palette_index + color_index;
                        var color_id = self.busRead(addr);

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

    /// Loads foreground sprite color data into a buffer (Used for debugging).
    pub fn getSpriteData(self: *Self, buf: []u8) void {
        // TODO: support 8x16 mode.
        std.debug.assert(buf.len == 64 * 8 * 8); // 64 sprites, each is 8x8
        // decide the pattern table to use for the sprites based on the PPUCTRL register
        var pt_base_addr: u16 = if (self.ppu_ctrl.pattern_sprite) 0x1000 else 0x0000;
        const sprites_per_row = 8;
        const sprites_per_col = 8;
        for (0..64) |sprite_index| {
            var tile_index: u16 = self.oam[sprite_index * 4 + 1];
            var attrs: SpriteAttributes = @bitCast(self.oam[sprite_index * 4 + 2]);
            var palette_index: u16 = attrs.palette;
            for (0..8) |pxrow| {
                var px_row: u16 = @truncate(pxrow);
                var lo_byte = self.busRead(pt_base_addr + tile_index * 16 + px_row);
                var hi_byte = self.busRead(pt_base_addr + tile_index * 16 + px_row + 8);
                for (0..8) |px| {
                    var lo_bit = (lo_byte >> @truncate(7 - px)) & 0b1;
                    var hi_bit = (hi_byte >> @truncate(7 - px)) & 0b1;
                    var color_index = hi_bit << 1 | lo_bit;
                    var addr = fg_palette_base_addr + palette_size * palette_index + color_index;
                    var color_id = self.busRead(addr);

                    var bufrow = (sprite_index / sprites_per_row) * 8 + px_row;
                    var bufcol = (sprite_index % sprites_per_col) * 8 + px;
                    var buf_index = bufrow * 64 + bufcol;
                    std.debug.assert(buf_index < buf.len);
                    buf[buf_index] = color_id;
                }
            }
        }
    }

    /// Load the colors of a sprite into a buffer.
    pub fn getSprite(self: *Self, oam_index: u8, buf: []u8) void {
        // TODO: support 8x16 mode.
        std.debug.assert(buf.len == 8 * 8 * 3);
        var pt_base_addr: u16 = if (self.ppu_ctrl.pattern_sprite) 0x1000 else 0x0000;
        var tile_index: u16 = self.oam[oam_index * 4 + 1];
        var attrs: SpriteAttributes = @bitCast(self.oam[oam_index * 4 + 2]);
        var palette_index = attrs.palette;
        for (0..8) |pxrow| {
            var px_row: u16 = @truncate(pxrow);
            var lo_byte = self.busRead(pt_base_addr + tile_index * 16 + px_row);
            var hi_byte = self.busRead(pt_base_addr + tile_index * 16 + px_row + 8);
            for (0..8) |px_| {
                var pxcol: u8 = @truncate(px_);
                var lo_bit = (lo_byte >> @truncate(7 - pxcol)) & 0b1;
                var hi_bit = (hi_byte >> @truncate(7 - pxcol)) & 0b1;
                var color_index = hi_bit << 1 | lo_bit;
                var addr = fg_palette_base_addr + palette_size * palette_index + color_index;
                var color_id = self.busRead(addr);

                var color = Palette[color_id];

                var buf_index = (pxrow * 8 + pxcol) * 3;
                std.debug.assert(buf_index < buf.len);
                buf[buf_index] = color.r;
                buf[buf_index + 1] = color.g;
                buf[buf_index + 2] = color.b;
            }
        }
    }
};

test "(PPU) fetching NT and AT bytes based on `v` register" {
    const Console = @import("../nes.zig").Console;
    var nes = try Console.fromROMFile(std.testing.allocator, "../../roms/beepboop.zig");
    var ppu = nes.ppu;

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
