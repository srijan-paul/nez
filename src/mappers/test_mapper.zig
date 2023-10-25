const Mapper = @import("./mapper.zig").Mapper;
const Cart = @import("../cart.zig").Cart;

/// A test mapper that directly maps any input into PRG ROM banks.
/// This is only useful for testing the CPU.
pub const TestMapper = struct {
    const Self = @This();
    cart: *Cart,
    mapper: Mapper,

    fn read(i_mapper: *Mapper, addr: u16) u8 {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        return self.cart.prg_rom[addr];
    }

    fn write(i_mapper: *Mapper, addr: u16, value: u8) void {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        self.cart.prg_rom[addr] = value;
    }

    pub fn new(cart: *Cart) Self {
        return .{
            .cart = cart,
            .mapper = Mapper.new(read, write),
        };
    }
};
