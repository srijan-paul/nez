const rl = @cImport(@cInclude("raylib.h"));

pub fn main() void {
    rl.InitWindow(800, 600, "raylib test");
    rl.SetTargetFPS(60);
    defer rl.CloseWindow();

    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        rl.ClearBackground(rl.RAYWHITE);
        rl.DrawRectangle(100, 100, 200, 200, rl.RED);
        rl.DrawText("Hello from raylib 6.0 + zig 0.16!", 190, 400, 20, rl.DARKGRAY);
        rl.EndDrawing();
    }
}
