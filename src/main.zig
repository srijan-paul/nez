const rl = @import("raylib");
const rg = @import("raygui");
const gui = @import("./gui/gui.zig");
const std = @import("std");
const PPU = @import("./ppu/ppu.zig").PPU;
const NESConsole = @import("./nes.zig").Console;

const fmt = std.fmt;
/// TODO: make this a relative path lol.
const style = "/Users/srijan-paul/personal/zig/zig-out/bin/style_cyber.rgs";

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

    while (!rl.WindowShouldClose()) {
        var now: u64 = @intCast(std.time.milliTimestamp());
        var dt: u64 = now - then;
        then = now;

        rl.BeginDrawing();
        defer rl.EndDrawing();

        _ = try emu.update(dt);

        drawNesScreen(emu.ppu, &tex);

        registerWin.draw();
        rl.ClearBackground(rl.BLACK);
    }
}
