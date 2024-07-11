const rl = @cImport(@cInclude("raylib.h"));
const views = @import("./views.zig");
const std = @import("std");
const PPU = @import("./ppu/ppu.zig").PPU;
const PPUPalette = @import("./ppu/ppu.zig").Palette;
const NESConsole = @import("./nes.zig").Console;
const Gamepad = @import("./gamepad.zig");

const PatternTableView = views.PatternTableView;
const PaletteView = views.PaletteView;
const PrimaryOAMView = views.PrimaryOAMView;
const TilePreview = views.TilePreview;

const Allocator = std.mem.Allocator;

const Button = Gamepad.Button;
fn readGamepad(pad: *Gamepad) void {
    var buttons: [8]bool = undefined;
    buttons[@intFromEnum(Button.A)] = rl.IsKeyDown(rl.KEY_Q);
    buttons[@intFromEnum(Button.B)] = rl.IsKeyDown(rl.KEY_E);
    buttons[@intFromEnum(Button.Start)] = rl.IsKeyDown(rl.KEY_ENTER);
    buttons[@intFromEnum(Button.Select)] = rl.IsKeyDown(rl.KEY_X);
    buttons[@intFromEnum(Button.Up)] = rl.IsKeyDown(rl.KEY_UP);
    buttons[@intFromEnum(Button.Down)] = rl.IsKeyDown(rl.KEY_DOWN);
    buttons[@intFromEnum(Button.Left)] = rl.IsKeyDown(rl.KEY_LEFT);
    buttons[@intFromEnum(Button.Right)] = rl.IsKeyDown(rl.KEY_RIGHT);
    pad.setInputs(buttons);
}

const DebugView = struct {
    const Self = @This();
    allocator: Allocator,
    pt_view: PatternTableView,
    palette_view: PaletteView,
    tile_preview: TilePreview,
    sprite_view: PrimaryOAMView,
    ppu: *PPU,
    emu: *NESConsole,

    pub fn init(allocator: Allocator, emu: *NESConsole) !Self {
        var self: Self = undefined;
        self.allocator = allocator;

        self.emu = emu;
        self.pt_view = try PatternTableView.init(allocator);
        self.palette_view = PaletteView.init(emu.ppu);
        self.tile_preview = TilePreview.init();
        self.sprite_view = PrimaryOAMView.init(allocator, emu.ppu, &self.tile_preview);

        return self;
    }

    pub fn draw(self: *Self) !void {
        self.pt_view.draw(self.emu.ppu, 0);
        self.pt_view.draw(self.emu.ppu, 1);
        self.palette_view.drawBackgroundPalettes();
        self.palette_view.drawForegroundPalettes();
        self.sprite_view.draw();
    }

    pub fn deinit(self: *Self) void {
        self.pt_view.deinit();
        self.tile_preview.deinit();
        self.sprite_view.deinit();
    }
};

const debugFlag = "--debug";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    var isDebug = false;
    var flags: [2]?[:0]const u8 = undefined;

    flags[0] = args.next();
    flags[1] = args.next();

    var romPath: [:0]const u8 = "./roms/beepboop.nes";
    if (flags[0]) |arg| {
        isDebug = std.mem.eql(u8, arg, debugFlag);
        // If it wasnt the debug flag, then it must be a path to the ROM
        if (!isDebug) romPath = arg;
    }

    if (flags[1]) |arg| {
        if (isDebug) {
            // debug flag already given, this must be the rom path
            romPath = arg;
        } else {
            // debug flag not given, this must be the debug flag
            isDebug = std.mem.eql(u8, arg, debugFlag);
        }
    }

    if (isDebug) {
        rl.InitWindow(800, 800, "nez");
    } else {
        rl.InitWindow(256 * 2, 240 * 2, "nez");
    }

    rl.SetTargetFPS(200);
    defer rl.CloseWindow();

    var emu = try NESConsole.fromROMFile(allocator, romPath);
    defer emu.deinit();

    var debug_view = try DebugView.init(allocator, &emu);
    defer debug_view.deinit();
    emu.powerOn();

    var then: u64 = @intCast(std.time.milliTimestamp());

    var screen = views.Screen.init(emu.ppu, allocator);
    defer screen.deinit();

    while (!rl.WindowShouldClose()) {
        const now: u64 = @intCast(std.time.milliTimestamp());
        const dt: u64 = now - then;
        then = now;

        rl.BeginDrawing();
        defer rl.EndDrawing();

        _ = try emu.update(dt);
        if (!emu.is_paused) readGamepad(emu.controller);
        if (rl.IsKeyPressed(rl.KEY_SPACE)) {
            emu.is_paused = !emu.is_paused;
        }

        try screen.draw();
        if (isDebug) {
            try debug_view.draw();
        }
        rl.ClearBackground(rl.BLACK);
    }
}
