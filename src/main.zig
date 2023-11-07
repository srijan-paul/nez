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
    rl.SetTargetFPS(200);

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

    var then: u64 = @intCast(std.time.milliTimestamp());

    while (!rl.WindowShouldClose()) {
        var now: u64 = @intCast(std.time.milliTimestamp());
        var dt: u64 = now - then;
        then = now;

        rl.BeginDrawing();
        defer rl.EndDrawing();

        registerWin.draw();
        var cycles_elapsed = try emu.update(dt);

        std.debug.print("Cycles elapsed: {}\n", .{cycles_elapsed});
        std.debug.print("Time elapsed: {}\n", .{dt});

        rl.ClearBackground(rl.BLACK);
    }
}
