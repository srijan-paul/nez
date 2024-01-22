const rl = @import("raylib");
const rg = @import("raygui");
const gui = @import("./gui/gui.zig");
const views = @import("./gui/views.zig");
const std = @import("std");
const PPU = @import("./ppu/ppu.zig").PPU;
const PPUPalette = @import("./ppu/ppu.zig").Palette;
const NESConsole = @import("./nes.zig").Console;
const Gamepad = @import("./gamepad.zig");

const PatternTableView = views.PatternTableView;
const PaletteView = views.PaletteView;
const PrimaryOAMView = views.PrimaryOAMView;
const TilePreview = views.TilePreview;

const fmt = std.fmt;
const Allocator = std.mem.Allocator;

const Button = Gamepad.Button;
fn readGamepad(pad: *Gamepad) void {
    var buttons: [8]bool = undefined;
    buttons[@intFromEnum(Button.A)] = rl.IsKeyDown(rl.KeyboardKey.KEY_Q);
    buttons[@intFromEnum(Button.B)] = rl.IsKeyDown(rl.KeyboardKey.KEY_E);
    buttons[@intFromEnum(Button.Start)] = rl.IsKeyDown(rl.KeyboardKey.KEY_ENTER);
    buttons[@intFromEnum(Button.Select)] = rl.IsKeyDown(rl.KeyboardKey.KEY_X);
    buttons[@intFromEnum(Button.Up)] = rl.IsKeyDown(rl.KeyboardKey.KEY_UP);
    buttons[@intFromEnum(Button.Down)] = rl.IsKeyDown(rl.KeyboardKey.KEY_DOWN);
    buttons[@intFromEnum(Button.Left)] = rl.IsKeyDown(rl.KeyboardKey.KEY_LEFT);
    buttons[@intFromEnum(Button.Right)] = rl.IsKeyDown(rl.KeyboardKey.KEY_RIGHT);
    pad.setInputs(buttons);
}

const DebugView = struct {
    const Self = @This();
    registerWin: gui.Window,
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
        self.registerWin = gui.Window.new(allocator, "CPU State", 0, 0, 160, 240);
        try self.registerWin.addLabel("A", 88, 56, 24, 24);
        try self.registerWin.addLabel("X", 16, 32, 24, 24);
        try self.registerWin.addLabel("Y", 16, 56, 24, 24);
        try self.registerWin.addLabel("S", 88, 32, 24, 24);
        try self.registerWin.addLabel("PC", 16, 104, 30, 24);
        try self.registerWin.addLabel("Status", 16, 152, 56, 24);

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

        var emu = self.emu;
        self.registerWin.draw();
        try self.registerWin.drawLabelUint(100, 56, 24, 24, emu.cpu.A);
        try self.registerWin.drawLabelUint(32, 32, 24, 24, emu.cpu.X);
        try self.registerWin.drawLabelUint(32, 56, 24, 24, emu.cpu.Y);
        try self.registerWin.drawLabelUint(100, 32, 24, 24, emu.cpu.S);
        // PC points to the next instruction to be executed. (TODO: dont do this)
        try self.registerWin.drawLabelUint(40, 104, 40, 24, emu.cpu.PC - 1);

        var cpu_status: u8 = @bitCast(emu.cpu.StatusRegister);
        try self.registerWin.drawLabelUint(60, 152, 24, 24, cpu_status);
    }

    pub fn deinit(self: *Self) void {
        self.pt_view.deinit();
        self.tile_preview.deinit();
        self.sprite_view.deinit();
    }
};

const debugFlag = "--debug";

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

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

    rl.SetConfigFlags(rl.ConfigFlags{ .FLAG_WINDOW_RESIZABLE = false });

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
        var now: u64 = @intCast(std.time.milliTimestamp());
        var dt: u64 = now - then;
        then = now;

        rl.BeginDrawing();
        defer rl.EndDrawing();

        _ = try emu.update(dt);
        if (!emu.is_paused) readGamepad(emu.controller);
        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_SPACE)) {
            emu.is_paused = !emu.is_paused;
        }

        try screen.draw();
        if (isDebug) {
            try debug_view.draw();
        }
        rl.ClearBackground(rl.BLACK);
    }
}
