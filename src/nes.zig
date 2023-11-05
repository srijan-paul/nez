const std = @import("std");
const CPU = @import("cpu.zig").CPU;
const bus_mod = @import("bus.zig");
const Cart = @import("cart.zig").Cart;
const rl = @import("raylib");

const Bus = bus_mod.Bus;
const NESBus = bus_mod.NESBus;

const Allocator = std.heap.Allocator;

pub const Console = struct {
    const Self = @This();
    cart: Cart,
    cpu: CPU,

    /// Initialize an NES console from a ROM file.
    pub fn fromROMFile(allocator: Allocator, file_path: []u8) !Self {
        const cart = try Cart.loadFromFile(allocator, file_path);
        const bus = NESBus.new(allocator, cart);
        const cpu = CPU.init(allocator, bus);
        return .{
            .cart = cart,
            .cpu = cpu,
        };
    }

    fn raylibInit() !void {
        rl.SetConfigFlags(rl.ConfigFlags{ .FLAG_WINDOW_RESIZABLE = false });
        const screenWidth = 800;
        const screenHeight = 600;
        rl.InitWindow(screenWidth, screenHeight, "nez");
        rl.SetTargetFPS(60);
    }

    pub fn powerOn(self: *Self) void {
        self.cpu.powerOn();
    }

    pub fn tick(self: *Self) !void {
        return self.cpu.tick();
    }
};
