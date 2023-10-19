const rl // = @import("../lib/raylib/raylib.zig");
    = @import("raylib");
//

const std = @import("std");
const Cpu = @import("./cpu.zig");

pub fn main() void {
    rl.SetConfigFlags(rl.ConfigFlags{ .FLAG_WINDOW_RESIZABLE = true });
    rl.InitWindow(800, 800, "rl zig test");
    rl.SetTargetFPS(60);

    const cpu = Cpu{};
    _ = cpu;

    defer rl.CloseWindow();

    var ball_pos = rl.Vector2{ .x = 150, .y = 150 };

    while (!rl.WindowShouldClose()) {
        if (rl.IsKeyDown(rl.KeyboardKey.KEY_W)) {
            ball_pos.y -= 1;
        }

        if (rl.IsKeyDown(rl.KeyboardKey.KEY_S)) {
            ball_pos.y += 1;
        }

        if (rl.IsKeyDown(rl.KeyboardKey.KEY_A)) {
            ball_pos.x -= 1;
        }

        if (rl.IsKeyDown(rl.KeyboardKey.KEY_D)) {
            ball_pos.x += 1;
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.BLACK);

        rl.DrawCircleV(ball_pos, 50, rl.GREEN);
    }
}
