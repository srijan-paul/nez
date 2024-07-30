const std = @import("std");
const CPU = @import("cpu.zig").CPU;
const bus_mod = @import("bus.zig");
const Cart = @import("cart.zig").Cart;
const rl = @import("raylib");
const PPU = @import("./ppu/ppu.zig").PPU;
const Gamepad = @import("gamepad.zig");
const APU = @import("./apu/apu.zig");

const Bus = bus_mod.Bus;
const NESBus = bus_mod.NESBus;

const Allocator = std.mem.Allocator;

/// Clockrate of NES CPU in Hz (1.789773 Mhz).
const cpu_cycles_per_second: f64 = 1.789773 * 1_000_000;
const cpu_cycles_per_ms: f64 = cpu_cycles_per_second / 1_000;

/// An NES console.
pub const Console = struct {
    const Self = @This();

    allocator: Allocator,
    cart: *Cart,
    cpu: *CPU,
    ppu: *PPU,
    apu: *APU,
    mainBus: *NESBus,
    controller: *Gamepad,
    is_paused: bool = false,

    /// Initialize an NES console from a ROM file.
    pub fn fromROMFile(allocator: Allocator, file_path: [*:0]const u8) !Self {
        const cart = try allocator.create(Cart);
        cart.* = try Cart.loadFromFile(allocator, file_path);

        const cpu = try allocator.create(CPU);
        const apu = try allocator.create(APU);
        const ppu = try allocator.create(PPU);

        const gamepad = try allocator.create(Gamepad);
        gamepad.* = Gamepad{};

        var mainBus = try allocator.create(NESBus);
        mainBus.* = try NESBus.init(allocator, cart, apu, ppu, gamepad);

        cpu.* = CPU.init(allocator, &mainBus.bus);
        apu.* = APU.init(cpu);
        ppu.* = PPU.init(cpu, mainBus.mapper);

        return .{
            .allocator = allocator,
            .cart = cart,
            .cpu = cpu,
            .ppu = ppu,
            .apu = apu,
            .mainBus = mainBus,
            .controller = gamepad,
        };
    }

    pub fn deinit(self: *Self) void {
        self.cart.deinit();
        self.mainBus.deinit();

        self.allocator.destroy(self.cart);
        self.allocator.destroy(self.cpu);
        self.allocator.destroy(self.ppu);
        self.allocator.destroy(self.apu);
        self.allocator.destroy(self.mainBus);
        self.allocator.destroy(self.controller);
    }

    pub inline fn powerOn(self: *Self) void {
        self.cpu.powerOn();
    }

    pub inline fn tick(self: *Self) !void {
        try self.cpu.tick();
        self.apu.tickByCpuClock();

        // one CPU tick is 3 PPU ticks
        self.ppu.tick();
        self.ppu.tick();
        self.ppu.tick();
    }

    // Update the console state.
    // `dt`: time elapsed since last call to update in ms.
    // Retrurns the number of CPU cycles executed.
    pub fn update(self: *Self, dt: u64) !u64 {
        if (self.is_paused) return 0;
        const cpu_cycles: u64 = @intFromFloat(
            std.math.floor(@as(f64, @floatFromInt(dt)) * cpu_cycles_per_ms),
        );
        if (cpu_cycles < 1) return 0;

        for (0..@as(usize, cpu_cycles)) |_| {
            try self.tick();
        }

        return cpu_cycles;
    }
};
