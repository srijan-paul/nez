const rl = @import("raylib");
const rg = @import("raygui");
const gui = @import("./gui/gui.zig");
const std = @import("std");
const NESConsole = @import("./nes.zig").Console;

const fmt = std.fmt;
const style = "/Users/srijan-paul/personal/zig/zig-out/bin/style_cyber.rgs";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    rl.SetConfigFlags(rl.ConfigFlags{ .FLAG_WINDOW_RESIZABLE = false });
    rl.InitWindow(800, 800, "rl zig test");
    rl.SetTargetFPS(60);

    rg.GuiLoadStyle(style);

    defer rl.CloseWindow();

    var registerWin = gui.Window.new(allocator, "CPU State", 0, 0, 160, 240);

    var emu = try NESConsole.fromROMFile(allocator, "./roms/power-on.nes");
    defer emu.deinit();
    emu.powerOn();

    try registerWin.addLabel("X", 16, 32, 24, 24);
    try registerWin.addLabel("Y", 16, 56, 24, 24);
    try registerWin.addLabel("S", 88, 32, 24, 24);
    try registerWin.addLabel("A", 88, 56, 24, 24);
    try registerWin.addLabel("PC", 16, 104, 30, 24);
    try registerWin.addLabel("Status", 16, 152, 56, 24);

    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();

        registerWin.draw();
        try emu.tick();

        try registerWin.drawLabelUint(32, 32, 40, 24, emu.cpu.X);
        try registerWin.drawLabelUint(56, 104, 72, 24, emu.cpu.PC);

        rl.ClearBackground(rl.BLACK);
    }
}
