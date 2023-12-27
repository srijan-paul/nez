const std = @import("std");
const rl = @import("raylib");
const ppu_module = @import("../ppu/ppu.zig");

const PPU = ppu_module.PPU;
const PPUPalette = ppu_module.Palette;
const Allocator = std.mem.Allocator;

/// The coordinates of the UI elements.
pub const UIPositions = struct {
    pub const palette_y = (PPU.ScreenHeight * 2 + 16);
    pub const pattern_table_y = (PPU.ScreenHeight * 2 + 64);
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
    fn drawPalette(self: *Self, palette_index: u8, x: i32, y: i32) void {
        var color_ids = self.ppu.getPaletteColors(palette_index);

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

    /// Draw the palettes from the PPU memory.
    pub fn draw(self: *Self) void {
        var x: i32 = 0;
        var y: i32 = UIPositions.palette_y;

        var xoff: i32 = 4;
        var yoff: i32 = 4;

        rl.DrawText("Palettes (BG)", x + xoff, y + yoff, 16, rl.WHITE);

        yoff += 20;
        for (0..4) |i| {
            self.drawPalette(@truncate(i), x + xoff, y + yoff);
            xoff += 70;
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
