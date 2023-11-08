const std = @import("std");
const CPU = @import("cpu.zig").CPU;
const bus_mod = @import("bus.zig");
const Cart = @import("cart.zig").Cart;
const rl = @import("raylib");
const PPU = @import("./ppu/ppu.zig").PPU;

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
    mainBus: *NESBus,

    /// Initialize an NES console from a ROM file.
    pub fn fromROMFile(allocator: Allocator, file_path: [*:0]const u8) !Self {
        var cart = try allocator.create(Cart);
        cart.* = try Cart.loadFromFile(allocator, file_path);

        var ppu = try allocator.create(PPU);
        ppu.* = PPU{};

        var mainBus = try allocator.create(NESBus);
        mainBus.* = try NESBus.init(allocator, cart, ppu);

        var cpu = try allocator.create(CPU);
        cpu.* = CPU.init(allocator, &mainBus.bus);

        return .{
            .allocator = allocator,
            .cart = cart,
            .cpu = cpu,
            .ppu = ppu,
            .mainBus = mainBus,
        };
    }

    pub fn deinit(self: *Self) void {
        self.cart.deinit();
        self.mainBus.deinit();

        self.allocator.destroy(self.cart);
        self.allocator.destroy(self.cpu);
        self.allocator.destroy(self.ppu);
        self.allocator.destroy(self.mainBus);
    }

    pub fn powerOn(self: *Self) void {
        self.cpu.powerOn();
    }

    // Update the console state.
    // `dt`: time elapsed since last call to update in ms.
    // Retrurns the number of CPU cycles executed.
    pub fn update(self: *Self, dt: u64) !u64 {
        var cpu_cycles: u64 = @intFromFloat(
            std.math.floor(@as(f64, @floatFromInt(dt)) * cpu_cycles_per_ms),
        );
        if (cpu_cycles < 1) return 0;

        for (0..@as(usize, cpu_cycles)) |_| {
            try self.cpu.tick();
        }

        return cpu_cycles;
    }
};
