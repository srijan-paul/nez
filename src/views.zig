const std = @import("std");
const rl = @cImport(@cInclude("raylib.h"));
const ppu_module = @import("./ppu/ppu.zig");

const PPU = ppu_module.PPU;
const PPUPalette = ppu_module.Palette;
const Allocator = std.mem.Allocator;
const CPU = @import("./cpu.zig").CPU;

/// The X/Y coordinates of the UI elements.
pub const UIPositions = struct {
    pub const screen_x = 0;
    pub const screen_y = 0;
    pub const screen_width = PPU.ScreenWidth * 2;
    pub const screen_height = PPU.ScreenHeight * 2;

    pub const bg_palette_y = (screen_height + 2);
    pub const foreground_palette_y = (bg_palette_y + 40);
    pub const foreground_palette_x = 0;
    pub const pattern_table_y = foreground_palette_y + 30;
    pub const primary_oam_y = 32;
    pub const primary_oam_scale = 2.5;
    pub const primary_oam_x = screen_width + 64;

    pub const tile_preview_x = screen_width + 64;
    pub const tile_preview_y = screen_height + 64;

    pub const tile_coords_x = primary_oam_x;
    pub const tile_coords_y = screen_height + 64 + 80;
};

pub const Screen = struct {
    const Self = @This();
    const scale = struct {
        // zig doesn't have static local vars,
        // but I can use a local struct for the same purpose.
        const src = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = PPU.ScreenWidth,
            .height = PPU.ScreenHeight,
        };

        const dst = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = UIPositions.screen_width,
            .height = UIPositions.screen_height,
        };
    };

    ppu: *PPU,
    texture: rl.Texture2D,
    allocator: Allocator,

    /// Initialize the screen view.
    pub fn init(ppu: *PPU, allocator: Allocator) Self {
        const screen_img_data = rl.Image{
            .data = &ppu.render_buffer,
            .width = PPU.ScreenWidth,
            .height = PPU.ScreenHeight,
            .mipmaps = 1,
            .format = rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8,
        };
        const texture = rl.LoadTextureFromImage(screen_img_data);
        return .{ .ppu = ppu, .texture = texture, .allocator = allocator };
    }

    pub fn draw(self: *Self) !void {
        const topleft = rl.Vector2{ .x = 0, .y = 0 };
        rl.UpdateTexture(self.texture, &self.ppu.render_buffer);
        rl.DrawTexturePro(self.texture, scale.src, scale.dst, topleft, 0, rl.WHITE);

        const mx: f32 = @floatFromInt(rl.GetMouseX());
        const my: f32 = @floatFromInt(rl.GetMouseY());
        if (mx < scale.dst.width and my < scale.dst.height) {
            const tile_x: i32 = @intFromFloat(mx / (8 * 2));
            const tile_y: i32 = @intFromFloat(my / (8 * 2));

            const buf = try std.fmt.allocPrintZ(self.allocator, "Tile: {}, {}", .{ tile_y, tile_x });
            defer self.allocator.free(buf);

            rl.DrawText(
                buf,
                UIPositions.tile_coords_x,
                UIPositions.tile_coords_y,
                16,
                rl.WHITE,
            );
        }
    }

    pub fn deinit(self: *Self) void {
        rl.UnloadTexture(self.texture);
    }
};

/// Preview of the tile that the cursor is hovering over.
pub const TilePreview = struct {
    const Self = @This();

    color_buf: [8 * 8 * 3]u8 = [_]u8{0} ** (8 * 8 * 3),
    texture: rl.Texture2D,

    pub fn init() Self {
        var self = Self{
            .texture = undefined,
        };
        const image = rl.Image{
            .data = &self.color_buf,
            .width = 8,
            .height = 8,
            .mipmaps = 1,
            .format = rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8,
        };

        self.texture = rl.LoadTextureFromImage(image);
        return self;
    }

    pub fn deinit(self: *Self) void {
        rl.UnloadTexture(self.texture);
    }

    const scale = 10;
    const srcScale = rl.Rectangle{ .x = 0, .y = 0, .width = 8, .height = 8 };
    const dstScale = rl.Rectangle{ .x = 0, .y = 0, .width = 8 * scale, .height = 8 * scale };

    pub fn drawSpriteTile(self: *Self, ppu: *PPU, tile_index: u8) void {
        ppu.getSprite(tile_index, &self.color_buf);
        rl.UpdateTexture(self.texture, &self.color_buf);
        rl.DrawTexturePro(
            self.texture,
            srcScale,
            dstScale,
            rl.Vector2{
                .x = -UIPositions.tile_preview_x,
                .y = -UIPositions.tile_preview_y,
            },
            0,
            rl.WHITE,
        );

        rl.DrawRectangleLines(
            UIPositions.tile_preview_x,
            UIPositions.tile_preview_y,
            8 * scale,
            8 * scale,
            rl.WHITE,
        );
    }
};

pub const PrimaryOAMView = struct {
    const Self = @This();
    ppu: *PPU,
    texture: rl.Texture2D,
    allocator: Allocator,
    oam_buf: [64 * 64]u8 = [_]u8{0} ** (64 * 64),
    texture_buf: [bufsize]u8 = [_]u8{0} ** bufsize,

    // buffer that contains the colors in the texture for the current sprite.
    current_sprite_texture_buf: [8 * 8 * 3]u8 = [_]u8{0} ** (8 * 8 * 3),
    current_sprite_texture: rl.Texture2D,

    tile_preview: *TilePreview,

    const bufsize: usize = 64 * 64 * 3; // 64 px wide, 64 px tall, 3 bytes per px (RGB).

    pub fn init(allocator: Allocator, ppu: *PPU, tile_preview: *TilePreview) Self {
        var self = Self{
            .ppu = ppu,
            .allocator = allocator,
            .texture = undefined,
            .current_sprite_texture = undefined,
            .tile_preview = tile_preview,
        };

        const color_format = rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8;
        const oam_preview_image = rl.Image{
            .data = &self.texture_buf,
            .width = 8 * 8, // 8 sprites per row, 8 pixels per sprite.
            .height = 8 * 8, // 8 sprites per column, 8 pixels per sprite.
            .mipmaps = 1,
            .format = color_format,
        };
        self.texture = rl.LoadTextureFromImage(oam_preview_image);

        const current_sprite_image = rl.Image{
            .data = &self.current_sprite_texture_buf,
            .width = 8,
            .height = 8,
            .mipmaps = 1,
            .format = color_format,
        };
        self.current_sprite_texture = rl.LoadTextureFromImage(current_sprite_image);
        return self;
    }

    pub fn deinit(self: *Self) void {
        rl.UnloadTexture(self.texture);
        rl.UnloadTexture(self.current_sprite_texture);
    }

    const scale = UIPositions.primary_oam_scale;
    const srcScale = rl.Rectangle{ .x = 0, .y = 0, .width = 64, .height = 64 };
    const dstScale = rl.Rectangle{ .x = 0, .y = 0, .width = 64 * scale, .height = 64 * scale };

    pub fn draw(self: *Self) void {
        // TODO: support 8x16 mode.

        rl.DrawText(
            "Sprites (OAM):",
            UIPositions.primary_oam_x,
            UIPositions.primary_oam_y,
            16,
            rl.WHITE,
        );

        self.ppu.getSpriteData(&self.oam_buf);
        for (0..self.oam_buf.len) |i| {
            const color_id = self.oam_buf[i];
            const color = PPUPalette[color_id];
            self.texture_buf[i * 3] = color.r;
            self.texture_buf[i * 3 + 1] = color.g;
            self.texture_buf[i * 3 + 2] = color.b;
        }

        const oam_x: f32 = UIPositions.primary_oam_x;
        const oam_y: f32 = UIPositions.primary_oam_y + 32;
        rl.UpdateTexture(self.texture, &self.texture_buf);
        rl.DrawTexturePro(
            self.texture,
            srcScale,
            dstScale,
            rl.Vector2{
                .x = -oam_x,
                .y = -oam_y,
            },
            0,
            rl.WHITE,
        );

        // if the cursor is over a sprite, show that tile in a larger view.
        const mouse_pos = rl.GetMousePosition();
        const mx = mouse_pos.x;
        const my = mouse_pos.y;

        if (mx < oam_x or my < oam_y) return;
        if (mx >= oam_x + dstScale.width or my >= oam_y + dstScale.width) return;

        // find which tile the mouse is on
        const oam_scale: f32 = scale;
        const sprite_col = (mx - oam_x) / (8 * oam_scale);
        const sprite_row = (my - oam_y) / (8 * oam_scale);
        if (sprite_row < 0.0 or sprite_col < 0.0) return;
        std.debug.assert(sprite_row < 8.0 and sprite_col < 8.0);

        const sprite_row_u8: u8 = @intCast(@as(i32, @intFromFloat(sprite_row)));
        const sprite_col_u8: u8 = @intCast(@as(i32, @intFromFloat(sprite_col)));
        const sprite_index_in_oam = sprite_row_u8 * 8 + sprite_col_u8;

        self.tile_preview.drawSpriteTile(self.ppu, sprite_index_in_oam);
    }
};

/// The PPU's palette viewer.
/// This shows all 4 background palettes from $03F00-$03F0F.
pub const PaletteView = struct {
    const Self = @This();
    ppu: *PPU,

    pub const color_rect_width = 16;
    pub const color_rect_height = 8;

    pub fn init(ppu: *PPU) Self {
        return .{ .ppu = ppu };
    }

    /// Draw the palette at index i
    fn drawPalette(self: *Self, is_bg: bool, palette_index: u8, x: i32, y: i32) void {
        const color_ids = self.ppu.getPaletteColors(is_bg, palette_index);

        var xoff: i32 = 0;
        for (0..4) |i| {
            const color = PPUPalette[color_ids[i]];
            const rlColor = rl.Color{
                .r = color.r,
                .g = color.g,
                .b = color.b,
                .a = 255,
            };

            rl.DrawRectangle(x + xoff, y, color_rect_width, color_rect_height, rlColor);
            xoff += 16 + 1;
        }
    }

    /// Draw the background palettes from the PPU memory.
    pub fn drawBackgroundPalettes(self: *Self) void {
        const x: i32 = 0;
        const y: i32 = UIPositions.bg_palette_y;

        var xoff: i32 = 4;
        var yoff: i32 = 4;

        rl.DrawText("Palettes (Background)", x + xoff, y + yoff, 12, rl.WHITE);

        yoff += 16;
        for (0..4) |i| {
            self.drawPalette(true, @truncate(i), x + xoff, y + yoff);
            xoff += 70;
        }
    }

    /// Draw the foreground palettes from PPU memory.
    pub fn drawForegroundPalettes(self: *Self) void {
        const x: i32 = UIPositions.foreground_palette_x;
        const y: i32 = UIPositions.foreground_palette_y;

        var xoff: i32 = 4;
        var yoff: i32 = 4;
        rl.DrawText("Palettes (Sprite)", x + xoff, y + yoff, 12, rl.WHITE);

        yoff += 16;
        for (0..4) |i| {
            self.drawPalette(false, @truncate(i), x + xoff, y + yoff);
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
        const color_id_buf = try allocator.alloc(u8, PPU.pattern_table_size_px);
        const image = rl.Image{
            .data = color_id_buf.ptr,
            .width = 128,
            .height = 128,
            .mipmaps = 1,
            .format = rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8,
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
            const color_id = self.color_id_buf[i];
            const color = PPUPalette[color_id];
            self.pt_buf[i * 3] = color.r;
            self.pt_buf[i * 3 + 1] = color.g;
            self.pt_buf[i * 3 + 2] = color.b;
        }

        const texture = if (pt_index == 0) self.pt_left_texture else self.pt_right_texture;
        rl.UpdateTexture(texture, &self.pt_buf);

        var xoff: f32 = 4;
        if (pt_index == 1) {
            xoff += 128 * pt_scale + 4;
        }

        const pt_text = if (pt_index == 0) "Pattern Table 0" else "Pattern Table 1";

        rl.DrawText(pt_text, @intFromFloat(xoff), UIPositions.pattern_table_y, 12, rl.WHITE);
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

const AddrMode = @import("opcode.zig").AddrMode;

pub const CPUView = struct {
    const Self = @This();

    allocator: Allocator,
    cpu: *CPU,
    ppu: *PPU,

    pub fn init(cpu: *CPU, ppu: *PPU, allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .cpu = cpu,
            .ppu = ppu,
        };
    }

    pub fn draw(self: *const Self) !void {
        var instr_addr = self.cpu.PC;
        if (instr_addr > 0) instr_addr -= 1;
        const instr = self.cpu.currentInstr.*;

        const op = instr[0];
        const addr_mode = instr[1];

        var s: [:0]u8 = undefined;
        defer self.allocator.free(s);
        if (addr_mode == AddrMode.Absolute) {
            const lo: u16 = self.cpu.memRead(self.cpu.PC);
            const hi: u16 = self.cpu.memRead(@addWithOverflow(self.cpu.PC, 1)[1]);
            const a = lo | (hi << 8);

            s = try std.fmt.allocPrintZ(
                self.allocator,
                "${x:0>4}: {s} (${x:0>4})",
                .{ instr_addr, @tagName(op), a },
            );
        } else {
            s = try std.fmt.allocPrintZ(
                self.allocator,
                "${x:0>4}: {s} ({s})",
                .{ instr_addr, @tagName(op), @tagName(addr_mode) },
            );
        }

        rl.DrawText(s, 800, 40, 20, rl.WHITE);

        const ppustatus: u8 = @bitCast(self.ppu.ppu_status);
        const ppu_status_s = try std.fmt.allocPrintZ(
            self.allocator,
            "PPU Status: {b:0>8}",
            .{ppustatus},
        );

        defer self.allocator.free(ppu_status_s);

        rl.DrawText(ppu_status_s, 800, 60, 20, rl.WHITE);

        const cpu_regs = try std.fmt.allocPrintZ(
            self.allocator,
            "A: ${x:0>2} X: ${x:0>2} Y: ${x:0>2} SP: ${x:0>2}",
            .{
                self.cpu.A,
                self.cpu.X,
                self.cpu.Y,
                @as(u8, @bitCast(self.cpu.StatusRegister)),
            },
        );

        defer self.allocator.free(cpu_regs);
        rl.DrawText(cpu_regs, 800, 80, 20, rl.WHITE);
    }
};
