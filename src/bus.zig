const Mapper = @import("./mappers/mapper.zig").Mapper;

pub const Bus = struct {
    const Self = @This();
    mapper: Mapper,
    ram: []u8,

    /// Create a new Bus.
    /// Both `i_mapper` and `ram` are non-owned pointers,
    /// and are not managed by the Bus.
    pub fn new(i_mapper: *Mapper, ram: []u8) Self {
        return .{
            .mapper = i_mapper,
            .ram = ram,
        };
    }

    pub fn read(self: *const Self, addr: u16) u8 {
        if (addr < 0x2000) {
            return self.ram[addr % 0x800];
        }

        return self.mapper.read(addr);
    }
};
