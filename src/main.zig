const rl = @import("raylib");
const rg = @import("raygui");
const gui = @import("./gui/gui.zig");
const views = @import("./gui/views.zig");
const std = @import("std");
const PPU = @import("./ppu/ppu.zig").PPU;
const PPUPalette = @import("./ppu/ppu.zig").Palette;
const NESConsole = @import("./nes.zig").Console;

const PatternTableView = views.PatternTableView;
const PaletteView = views.PaletteView;
const PrimaryOAMView = views.PrimaryOAMView;

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    rl.SetConfigFlags(rl.ConfigFlags{ .FLAG_WINDOW_RESIZABLE = false });
    rl.InitWindow(800, 800, "nez");
    rl.SetTargetFPS(200);

    rg.GuiLoadStyle(style);

    defer rl.CloseWindow();

    var registerWin = gui.Window.new(allocator, "CPU State", 0, 0, 160, 240);

    var emu = try NESConsole.fromROMFile(allocator, "./roms/dk.nes");
    defer emu.deinit();

    emu.powerOn();

    try registerWin.addLabel("A", 88, 56, 24, 24);
    try registerWin.addLabel("X", 16, 32, 24, 24);
    try registerWin.addLabel("Y", 16, 56, 24, 24);
    try registerWin.addLabel("S", 88, 32, 24, 24);
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

    var palette_view = PaletteView.init(emu.ppu);

    var sprite_view = PrimaryOAMView.init(allocator, emu.ppu);
    defer sprite_view.deinit();

    while (!rl.WindowShouldClose()) {
        var now: u64 = @intCast(std.time.milliTimestamp());
        var dt: u64 = now - then;
        then = now;

        rl.BeginDrawing();
        defer rl.EndDrawing();

        _ = try emu.update(dt);
        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_SPACE)) {
            try emu.ppu.dumpSprites();
            // try emu.debugTick();
        }

        drawNesScreen(emu.ppu, &tex);
        pt_view.draw(emu.ppu, 0);
        pt_view.draw(emu.ppu, 1);
        palette_view.draw();
        sprite_view.draw();

        registerWin.draw();
        try registerWin.drawLabelUint(100, 56, 24, 24, emu.cpu.A);
        try registerWin.drawLabelUint(32, 32, 24, 24, emu.cpu.X);
        try registerWin.drawLabelUint(32, 56, 24, 24, emu.cpu.Y);
        try registerWin.drawLabelUint(100, 32, 24, 24, emu.cpu.S);
        // PC points to the next instruction to be executed. (TODO: dont do this)
        try registerWin.drawLabelUint(40, 104, 40, 24, emu.cpu.PC - 1);

        var cpu_status: u8 = @bitCast(emu.cpu.StatusRegister);
        try registerWin.drawLabelUint(60, 152, 24, 24, cpu_status);

        rl.ClearBackground(rl.BLACK);
    }
}
