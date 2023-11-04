const std = @import("std");
const CPU = @import("cpu.zig").CPU;
const bus_mod = @import("bus.zig");
const Cart = @import("cart.zig").Cart;

const Bus = bus_mod.Bus;
const NESBus = bus_mod.NESBus;

const Allocator = std.heap.Allocator;

pub const NES = struct {
    const Self = @This();
    cart: Cart,
    cpu: CPU,

    pub fn fromFile(allocator: Allocator, file_path: []u8) Self {
        const cart = Cart.loadFromFile(allocator, file_path);
        const bus = NESBus.init(cart.mapper, cart);
        const cpu = CPU.init(allocator, bus);
        return .{
            .cart = cart,
            .cpu = cpu,
        };
    }
};
