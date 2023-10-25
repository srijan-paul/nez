const Cart = @import("../cart.zig").Cart;

/// NES Mapper interface.
/// Zig interfaces are awkward :S
pub const Mapper = struct {
    const Self = @This();

    pub const ReadFn = fn (*Mapper, u16) u8;
    pub const WriteFn = fn (*Mapper, u16, u8) void;

    /// A pointer to the read-function implemented by
    /// the concrete mapper type.
    readFn: ReadFn,

    /// A pointer to the write-function implemented by
    /// the concrete mapper type.
    writeFn: WriteFn,

    /// Initialize a mapper.
    /// `impl`: a mapper implementation.
    /// `read`: a function that reads from the mapper.
    /// `write`: a function that writes to the mapper.
    pub fn new(readFn: ReadFn, writeFn: WriteFn) Self {
        return .{
            .readFn = readFn,
            .writeFn = writeFn,
        };
    }

    /// Read a byte of data from cartridge memory.
    pub fn read(self: *Self, addr: u16) u8 {
        return self.readFn(self, addr);
    }

    /// Write a byte of data to cartridge memory.
    pub fn write(self: *Self, addr: u16, value: u8) void {
        self.writeFn(self, addr, value);
    }
};
