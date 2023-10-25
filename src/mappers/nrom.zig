const Mapper = @import("./mapper.zig").Mapper;
const Cart = @import("../cart.zig").Cart;

/// The iNES format assigns mapper 0 to the NROM board,
/// which is the most common board type.
/// This was used by most early NES games.
pub const NROM = struct {
    const Self = @This();
    cart: *Cart,
    mapper: Mapper,

    /// Given a 16-bit address, return a pointer to the corresponding byte
    /// in cartridge memory.
    fn resolve_addr(self: *Self, addr: u16) *u8 {
        // TODO: implement the mapper-0 memory map for an NES cart.
        return &self.cart.prg_rom[addr];
    }

    fn nrom_read(i_mapper: *Mapper, addr: u16) u8 {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        return self.resolve_addr(addr).*;
    }

    fn nrom_write(i_mapper: *Mapper, addr: u16, value: u8) void {
        var self: *Self = @fieldParentPtr(Self, "mapper", i_mapper);
        var ptr = self.resolve_addr(addr);
        ptr.* = value;
    }

    /// Crate a new mapper that operators on `cart`.
    pub fn new(cart: *Cart) Self {
        var self = Self{ .cart = cart, .mapper = Mapper.new(nrom_read, nrom_write) };
        return self;
    }
};
