const Cart = @import("../cart.zig").Cart;

pub const MapperKind = enum { nrom };

/// NES Mapper interface.
/// Zig interfaces are awkward :S
pub const Mapper = struct {
    const Self = @This();

    pub const ReadFn = *const fn (*Mapper, u16) u8;
    pub const PPUReadFn = *const fn (*Mapper, u16) u8;
    pub const WriteFn = *const fn (*Mapper, u16, u8) void;
    pub const PPUWriteFn = *const fn (*Mapper, u16, u8) void;

    /// A pointer to the read-function implemented by
    /// the concrete mapper type.
    readFn: ReadFn,

    /// A pointer to the write-function implemented by
    /// the concrete mapper type.
    writeFn: WriteFn,

    /// A pointer to the PPU read-function implemented the
    /// concrete mapper type.
    ppuReadFn: ReadFn,

    /// A pointer to the PPU write-function implemented by
    /// the concrete mapper type.
    ppuWriteFn: WriteFn,

    /// Initialize a mapper.
    /// `impl`: a mapper implementation.
    /// `read`: a function that reads from the mapper.
    /// `write`: a function that writes to the mapper.
    /// `resolveAddrFn`: a function that can resolve an address to a byte ptr.
    /// `deinitFn`: a function that deinitializes the mapper.
    pub fn init(
        readFn: ReadFn,
        writeFn: WriteFn,
        ppuReadFn: PPUReadFn,
        ppuWriteFn: PPUWriteFn,
    ) Self {
        return .{
            .readFn = readFn,
            .writeFn = writeFn,
            .ppuReadFn = ppuReadFn,
            .ppuWriteFn = ppuWriteFn,
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

    /// Read a byte of data from PPU address space.
    pub fn ppuRead(self: *Self, addr: u16) u8 {
        return self.ppuReadFn(self, addr);
    }

    /// Write a byte of data to PPU address space.
    pub fn ppuWrite(self: *Self, addr: u16, value: u8) void {
        self.ppuWriteFn(self, addr, value);
    }
};
