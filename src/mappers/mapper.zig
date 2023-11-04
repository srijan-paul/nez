const Cart = @import("../cart.zig").Cart;

pub const MapperKind = enum { nrom };

/// NES Mapper interface.
/// Zig interfaces are awkward :S
pub const Mapper = struct {
    const Self = @This();

    pub const ReadFn = fn (*Mapper, u16) u8;
    pub const WriteFn = fn (*Mapper, u16, u8) void;
    pub const ResolveAddrFn = fn (*Mapper, u16) ?*u8;

    /// A pointer to the read-function implemented by
    /// the concrete mapper type.
    readFn: ReadFn,

    /// A pointer to the write-function implemented by
    /// the concrete mapper type.
    writeFn: WriteFn,

    resolveAddrFn: ResolveAddrFn,

    /// Initialize a mapper.
    /// `impl`: a mapper implementation.
    /// `read`: a function that reads from the mapper.
    /// `write`: a function that writes to the mapper.
    /// `resolveAddrFn`: a function that can resolve an address to a byte ptr.
    /// `deinitFn`: a function that deinitializes the mapper.
    pub fn init(
        readFn: ReadFn,
        writeFn: WriteFn,
        resolveAddrFn: ResolveAddrFn,
    ) Self {
        return .{
            .readFn = readFn,
            .writeFn = writeFn,
            .resolveAddrFn = resolveAddrFn,
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

    /// Get an byte pointer to cartridge memory from an address.
    pub fn resolveAddr(self: *Self, addr: u16) *u8 {
        return self.resolveAddr(self, addr);
    }
};
