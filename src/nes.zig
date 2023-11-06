const std = @import("std");
const CPU = @import("cpu.zig").CPU;
const bus_mod = @import("bus.zig");
const Cart = @import("cart.zig").Cart;
const rl = @import("raylib");

const Bus = bus_mod.Bus;
const NESBus = bus_mod.NESBus;

const Allocator = std.mem.Allocator;

/// An NES console.
pub const Console = struct {
    const Self = @This();

    allocator: Allocator,
    cart: *Cart,
    cpu: *CPU,
    mainBus: *NESBus,

    /// Initialize an NES console from a ROM file.
    pub fn fromROMFile(allocator: Allocator, file_path: [*:0]const u8) !Self {
        var cart = try allocator.create(Cart);
        cart.* = try Cart.loadFromFile(allocator, file_path);

        var mainBus = try allocator.create(NESBus);
        mainBus.* = try NESBus.init(allocator, cart);

        var cpu = try allocator.create(CPU);
        cpu.* = CPU.init(allocator, &mainBus.bus);

        return .{
            .allocator = allocator,
            .cart = cart,
            .cpu = cpu,
            .mainBus = mainBus,
        };
    }

    pub fn deinit(self: *Self) void {
        self.cart.deinit();
        self.mainBus.deinit();

        self.allocator.destroy(self.cart);
        self.allocator.destroy(self.cpu);
        self.allocator.destroy(self.mainBus);
    }

    pub fn powerOn(self: *Self) void {
        self.cpu.powerOn();
    }

    pub fn tick(self: *Self) !void {
        return self.cpu.tick();
    }
};
