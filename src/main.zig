const rl = @import("raylib");
const rg = @import("raygui");
const gui = @import("./gui/gui.zig");

const std = @import("std");
const style = "/Users/srijan-paul/personal/zig/zig-out/bin/style_cyber.rgs";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    rl.SetConfigFlags(rl.ConfigFlags{ .FLAG_WINDOW_RESIZABLE = true });
    rl.InitWindow(800, 800, "rl zig test");
    rl.SetTargetFPS(60);

    rg.GuiLoadStyle(style);

    defer rl.CloseWindow();

    var cpuState = gui.Window.new(allocator, "CPU State", 0, 0, 160, 240);

    try cpuState.addLabel("X", 16, 32, 24, 24);
    try cpuState.addLabel("Y", 16, 56, 24, 24);
    try cpuState.addLabel("S", 88, 32, 24, 24);
    try cpuState.addLabel("A", 88, 56, 24, 24);
    try cpuState.addLabel("PC", 16, 104, 30, 24);
    try cpuState.addLabel("Status", 16, 152, 56, 24);

    while (!rl.WindowShouldClose()) {
        cpuState.draw();

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.BLACK);
    }
}
