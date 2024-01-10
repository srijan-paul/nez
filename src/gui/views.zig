const std = @import("std");
const rl = @import("raylib");
const ppu_module = @import("../ppu/ppu.zig");

const PPU = ppu_module.PPU;
const PPUPalette = ppu_module.Palette;
const Allocator = std.mem.Allocator;

/// The coordinates of the UI elements.
pub const UIPositions = struct {
    pub const bg_palette_y = (PPU.ScreenHeight * 2 + 16);
    pub const pattern_table_y = (PPU.ScreenHeight * 2 + 64);
    pub const primary_oam_y = 32;
    pub const primary_oam_scale = 2.5;
    pub const primary_oam_x = PPU.ScreenWidth * 2 + 64;
    pub const foreground_palette_y = (primary_oam_y + 64 * primary_oam_scale + 64);
    pub const foreground_palette_x = primary_oam_x;
};

pub const PrimaryOAMView = struct {
    const Self = @This();
    ppu: *PPU,
    texture: rl.Texture2D,
    allocator: Allocator,
    oam_buf: [64 * 64]u8 = [_]u8{0} ** (64 * 64),
    texture_buf: [bufsize]u8 = [_]u8{0} ** bufsize,

    const bufsize: usize = 64 * 64 * 3; // 64 px wide, 64 px tall, 3 bytes per px (RGB).

    pub fn init(allocator: Allocator, ppu: *PPU) Self {
        var self = Self{
            .ppu = ppu,
            .allocator = allocator,
            .texture = undefined,
        };

        var image = rl.Image{
            .data = &self.texture_buf,
            .width = 8 * 8, // 8 sprites per row, 8 pixels per sprite.
            .height = 8 * 8, // 8 sprites per column, 8 pixels per sprite.
            .mipmaps = 1,
            .format = @intFromEnum(rl.rlPixelFormat.RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8),
        };

        self.texture = rl.LoadTextureFromImage(image);
        return self;
    }

    pub fn deinit(self: *Self) void {
        rl.UnloadTexture(self.texture);
    }

    const scale = UIPositions.primary_oam_scale;
    const srcScale = rl.Rectangle{ .x = 0, .y = 0, .width = 64, .height = 64 };
    const dstScale = rl.Rectangle{ .x = 0, .y = 0, .width = 64 * scale, .height = 64 * scale };

    pub fn draw(self: *Self) void {
        // TODO: suppot 8x16 mode.

        rl.DrawText(
            "Sprites (OAM):",
            UIPositions.primary_oam_x,
            UIPositions.primary_oam_y,
            16,
            rl.WHITE,
        );

        self.ppu.getSpriteData(&self.oam_buf);
        for (0..self.oam_buf.len) |i| {
            var color_id = self.oam_buf[i];
            var color = PPUPalette[color_id];
            self.texture_buf[i * 3] = color.r;
            self.texture_buf[i * 3 + 1] = color.g;
            self.texture_buf[i * 3 + 2] = color.b;
        }

        rl.UpdateTexture(self.texture, &self.texture_buf);
        rl.DrawTexturePro(
            self.texture,
            srcScale,
            dstScale,
            rl.Vector2{
                .x = -UIPositions.primary_oam_x,
                .y = -(UIPositions.primary_oam_y + 32),
            },
            0,
            rl.WHITE,
        );
    }
};

/// The PPU's palette viewer.
/// This shows all 4 background palettes from $03F00-$03F0F.
pub const PaletteView = struct {
    const Self = @This();
    ppu: *PPU,

    pub fn init(ppu: *PPU) Self {
        return .{ .ppu = ppu };
    }

    /// Draw the palette at index i
    fn drawPalette(self: *Self, is_bg: bool, palette_index: u8, x: i32, y: i32) void {
        var color_ids = self.ppu.getPaletteColors(is_bg, palette_index);

        var xoff: i32 = 0;
        for (0..4) |i| {
            var color = PPUPalette[color_ids[i]];
            var rlColor = rl.Color{
                .r = color.r,
                .g = color.g,
                .b = color.b,
                .a = 255,
            };

            rl.DrawRectangle(x + xoff, y, 16, 12, rlColor);
            xoff += 16 + 1;
        }
    }

    /// Draw the background palettes from the PPU memory.
    pub fn drawBackgroundPalettes(self: *Self) void {
        var x: i32 = 0;
        var y: i32 = UIPositions.bg_palette_y;

        var xoff: i32 = 4;
        var yoff: i32 = 4;

        rl.DrawText("Palettes (Background)", x + xoff, y + yoff, 16, rl.WHITE);

        yoff += 20;
        for (0..4) |i| {
            self.drawPalette(true, @truncate(i), x + xoff, y + yoff);
            xoff += 70;
        }
    }

    /// Draw the foreground palettes from PPU memory.
    pub fn drawForegroundPalettes(self: *Self) void {
        var x: i32 = UIPositions.foreground_palette_x;
        var y: i32 = UIPositions.foreground_palette_y;

        var xoff: i32 = 4;
        var yoff: i32 = 4;
        rl.DrawText("Palettes (Sprite)", x + xoff, y + yoff, 16, rl.WHITE);

        yoff += 20;
        for (0..4) |i| {
            self.drawPalette(false, @truncate(i), x + xoff, y + yoff);
            yoff += 20;
        }
    }
};

/// The PPU's pattern table viewer.
pub const PatternTableView = struct {
    const Self = @This();

    allocator: Allocator,
    color_id_buf: []u8,
    pt_buf: [PPU.pattern_table_size_px * 3]u8 = [_]u8{1} ** (PPU.pattern_table_size_px * 3),

    pt_left_texture: rl.Texture2D,
    pt_right_texture: rl.Texture2D,

    pub fn init(allocator: Allocator) !Self {
        var color_id_buf = try allocator.alloc(u8, PPU.pattern_table_size_px);
        var image = rl.Image{
            .data = color_id_buf.ptr,
            .width = 128,
            .height = 128,
            .mipmaps = 1,
            .format = @intFromEnum(rl.rlPixelFormat.RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8),
        };

        return .{
            .allocator = allocator,
            .color_id_buf = color_id_buf,
            .pt_left_texture = rl.LoadTextureFromImage(image),
            .pt_right_texture = rl.LoadTextureFromImage(image),
        };
    }

    pub fn deinit(self: *Self) void {
        rl.UnloadTexture(self.pt_left_texture);
        rl.UnloadTexture(self.pt_right_texture);
        self.allocator.free(self.color_id_buf);
    }

    const pt_scale = 1.5;
    const srcScale = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = 128,
        .height = 128,
    };

    const dstScale = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = 128 * pt_scale,
        .height = 128 * pt_scale,
    };

    pub fn draw(self: *Self, ppu: *PPU, pt_index: u8) void {
        // load the 8 bit color IDs from the pattern table.
        ppu.getPatternTableData(self.color_id_buf, pt_index, 0);
        // convert the 8 bit color IDs to 24 bit colors.
        for (0..self.color_id_buf.len) |i| {
            var color_id = self.color_id_buf[i];
            // std.debug.print("{}: {}, ", .{ i, color_id });
            var color = PPUPalette[color_id];
            self.pt_buf[i * 3] = color.r;
            self.pt_buf[i * 3 + 1] = color.g;
            self.pt_buf[i * 3 + 2] = color.b;
        }

        var texture = if (pt_index == 0) self.pt_left_texture else self.pt_right_texture;
        rl.UpdateTexture(texture, &self.pt_buf);

        var xoff: f32 = 4;
        if (pt_index == 1) {
            xoff += 128 * pt_scale + 4;
        }

        var pt_text = if (pt_index == 0) "Pattern Table 0" else "Pattern Table 1";

        rl.DrawText(pt_text, @intFromFloat(xoff), UIPositions.pattern_table_y, 16, rl.WHITE);
        rl.DrawTexturePro(
            texture,
            srcScale,
            dstScale,
            rl.Vector2{
                .x = -xoff,
                .y = -(UIPositions.pattern_table_y + 20),
            },
            0,
            rl.WHITE,
        );
    }
};
