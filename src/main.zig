const rl = @import("raylib");
const rg = @import("raygui");
const gui = @import("./gui/gui.zig");
const std = @import("std");
const PPU = @import("./ppu/ppu.zig").PPU;
const PPUPalette = @import("./ppu/ppu.zig").Palette;
const NESConsole = @import("./nes.zig").Console;

const fmt = std.fmt;
/// TODO: make this a relative path lol.
const style = "/Users/srijan-paul/personal/zig/zig-out/bin/style_cyber.rgs";

const Allocator = std.mem.Allocator;

/// Render the NES screen to the window.
pub fn drawNesScreen(ppu: *PPU, ppu_texture: *rl.Texture2D) void {
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
            .width = PPU.ScreenWidth * 2,
            .height = PPU.ScreenHeight * 2,
        };
    };

    rl.UpdateTexture(ppu_texture.*, &ppu.render_buffer);
    rl.DrawTexturePro(
        ppu_texture.*,
        scale.src,
        scale.dst,
        rl.Vector2{ .x = 0, .y = 0 },
        0,
        rl.WHITE,
    );
}

const PatternTableView = struct {
    const Self = @This();

    allocator: Allocator,
    color_id_buf: []u8,
    pt_buf: [PPU.pattern_table_size_px * 3]u8 = [_]u8{1} ** (PPU.pattern_table_size_px * 3),
    texture: rl.Texture2D,

    pub fn init(allocator: Allocator) !Self {
        var color_id_buf = try allocator.alloc(u8, PPU.pattern_table_size_px);
        var image = rl.Image{
            .data = color_id_buf.ptr,
            .width = 128,
            .height = 128,
            .mipmaps = 1,
            .format = @intFromEnum(rl.rlPixelFormat.RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8),
        };
        // defer rl.UnloadImage(image); TODO: why does uncommenting this crash?
        return .{
            .allocator = allocator,
            .color_id_buf = color_id_buf,
            .texture = rl.LoadTextureFromImage(image),
        };
    }

    pub fn deinit(self: *Self) void {
        rl.UnloadTexture(self.texture);
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

        rl.UpdateTexture(self.texture, &self.pt_buf);

        var xoff: f32 = 4;
        if (pt_index == 1) {
            xoff += 128 * pt_scale + 4;
        }

        var pt_text = if (pt_index == 0) "Pattern Table 0" else "Pattern Table 1";

        rl.DrawText(pt_text, @intFromFloat(xoff), PPU.ScreenHeight * 2 + 16, 16, rl.WHITE);
        rl.DrawTexturePro(
            self.texture,
            srcScale,
            dstScale,
            rl.Vector2{
                .x = -xoff,
                .y = -(PPU.ScreenHeight * 2 + 32),
            },
            0,
            rl.WHITE,
        );
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    rl.SetConfigFlags(rl.ConfigFlags{ .FLAG_WINDOW_RESIZABLE = false });
    rl.InitWindow(800, 800, "nez");
    rl.SetTargetFPS(200);

    rg.GuiLoadStyle(style);

    defer rl.CloseWindow();

    var registerWin = gui.Window.new(allocator, "CPU State", 0, 0, 160, 240);

    var emu = try NESConsole.fromROMFile(allocator, "./roms/beepboop.nes");
    defer emu.deinit();

    emu.powerOn();

    try registerWin.addLabel("X", 16, 32, 24, 24);
    try registerWin.addLabel("Y", 16, 56, 24, 24);
    try registerWin.addLabel("S", 88, 32, 24, 24);
    try registerWin.addLabel("A", 88, 56, 24, 24);
    try registerWin.addLabel("PC", 16, 104, 30, 24);
    try registerWin.addLabel("Status", 16, 152, 56, 24);

    var then: u64 = @intCast(std.time.milliTimestamp());
    var screen_img_data = rl.Image{
        .data = &emu.ppu.render_buffer,
        .width = PPU.ScreenWidth,
        .height = PPU.ScreenHeight,
        .mipmaps = 1,
        .format = @intFromEnum(rl.rlPixelFormat.RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8),
    };

    var tex = rl.LoadTextureFromImage(screen_img_data);
    defer rl.UnloadTexture(tex);

    var pt_view = try PatternTableView.init(allocator);
    defer pt_view.deinit();

    while (!rl.WindowShouldClose()) {
        var now: u64 = @intCast(std.time.milliTimestamp());
        var dt: u64 = now - then;
        then = now;

        rl.BeginDrawing();
        defer rl.EndDrawing();

        _ = try emu.update(dt);

        drawNesScreen(emu.ppu, &tex);
        pt_view.draw(emu.ppu, 0);
        pt_view.draw(emu.ppu, 1);

        registerWin.draw();
        rl.ClearBackground(rl.BLACK);
    }
}
