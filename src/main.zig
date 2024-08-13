const rl = @cImport(@cInclude("raylib.h"));
const views = @import("./views.zig");
const std = @import("std");
const PPU = @import("./ppu/ppu.zig").PPU;
const PPUPalette = @import("./ppu/ppu.zig").Palette;
const NESConsole = @import("./nes.zig").Console;
const Gamepad = @import("./gamepad.zig");
const Queue = @import("util.zig").Queue;

const PatternTableView = views.PatternTableView;
const PaletteView = views.PaletteView;
const PrimaryOAMView = views.PrimaryOAMView;
const TilePreview = views.TilePreview;
const CPUView = views.CPUView;

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
    cpu_view: CPUView,
    ppu: *PPU,
    emu: *NESConsole,

    pub fn init(allocator: Allocator, emu: *NESConsole) !Self {
        // TODO: refactor
        var self: Self = undefined;
        self.allocator = allocator;

        self.emu = emu;
        self.pt_view = try PatternTableView.init(allocator);
        self.palette_view = PaletteView.init(emu.ppu);
        self.tile_preview = TilePreview.init();
        self.sprite_view = PrimaryOAMView.init(allocator, emu.ppu, &self.tile_preview);
        self.cpu_view = CPUView.init(emu.cpu, emu.ppu, allocator);

        return self;
    }

    pub fn draw(self: *Self) !void {
        self.pt_view.draw(self.emu.ppu, 0);
        self.pt_view.draw(self.emu.ppu, 1);
        self.palette_view.drawBackgroundPalettes();
        self.palette_view.drawForegroundPalettes();
        self.sprite_view.draw();
        try self.cpu_view.draw();
    }

    pub fn deinit(self: *Self) void {
        self.pt_view.deinit();
        self.tile_preview.deinit();
        self.sprite_view.deinit();
    }
};

const debugFlag = "--debug";

var apu_samples_queue: ?*Queue(i16) = null;

fn rlAudioInputCallback(buffer_: ?*anyopaque, frames: c_uint) callconv(.C) void {
    const buffer = buffer_ orelse return;
    const buf: [*]i16 = @alignCast(@ptrCast(buffer));

    const queue = apu_samples_queue orelse return;

    for (0..frames) |i| {
        if (queue.isEmpty()) {
            for (i..frames) |j| {
                buf[j] = 0;
            }
            break;
        } else {
            buf[i] = queue.pop() catch
                std.debug.panic("popping from empty queue!", .{});
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

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
        rl.InitWindow(1200, 768, "nez");
    } else {
        rl.InitWindow(256 * 2, 240 * 2, "nez");
    }

    rl.SetTargetFPS(200);
    defer rl.CloseWindow();

    var emu = try NESConsole.fromROMFile(allocator, romPath);
    defer emu.deinit();

    apu_samples_queue = &emu.audio_sample_queue;

    var debug_view = try DebugView.init(allocator, &emu);
    defer debug_view.deinit();
    emu.powerOn();

    var then: u64 = @intCast(std.time.milliTimestamp());

    var screen = views.Screen.init(emu.ppu, allocator);
    defer screen.deinit();

    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();
    rl.SetAudioStreamBufferSizeDefault(1024);

    var audio_sample: [1024]i16 = undefined;

    const audio_stream = rl.LoadAudioStream(44100, 8, 1);
    rl.UpdateAudioStream(audio_stream, &audio_sample, audio_sample.len);
    defer rl.UnloadAudioStream(audio_stream);
    rl.SetAudioStreamCallback(audio_stream, rlAudioInputCallback);

    rl.PlayAudioStream(audio_stream);

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
        if (isDebug) try debug_view.draw();

        rl.ClearBackground(rl.BLACK);
    }
}
