const std = @import("std");
const opcodes = @import("opcode.zig");
const cart = @import("cart.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const AddrMode = opcodes.AddrMode;
const Op = opcodes.Op;

pub const Register = i8;
pub const Byte = i8;

pub const StatusRegister = packed struct {
    // Negative Flag
    N: bool = false,
    // Overflow Flag
    V: bool = false,

    // This status flag does nothing, and is always set to 1.
    _: bool = true,
    // B-Flag. Not used by the user.
    B: bool = false,
    // Decimal Mode
    D: bool = false,

    // Interrupt Disable
    I: bool = false,
    // Zero Flag
    Z: bool = false,
    // Carry Flag
    C: bool = false,

    const Self = @This();
    comptime {
        assert(@sizeOf(Self) == 1);
        assert(@bitSizeOf(Self) == 8);
    }
};

pub const NESError = error{
    InvalidAddressingMode,
    NotImplemented,
    Unreachable,
};

pub const CPU = struct {
    const Self = @This();
    // each page in the RAM is 256 bytes.
    const PageSize = 256;

    // number of cycles to cycles to wait
    // before executing the next instruction.
    var cycles_to_wait = 0;

    // capacity of the RAM chip attached to the CPU in bytes
    // (called SRAM (S = static), or WRAM(W = work))
    pub const WRamSize = 2048;
    RAM: [WRamSize]Byte = .{0} ** WRamSize,

    // registers
    A: Register = 0,

    // Used for addressing modes, and loop counters.
    X: Register = 0,
    Y: Register = 0,

    // can be accessed using interrupts.
    S: Register = 0,

    P: Register = 0,

    PC: Register = 0,

    StatusRegister: StatusRegister = .{},

    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn index_memory(self: *Self, addr: u16) Byte {
        return self.RAM[addr];
    }

    pub fn memRead(self: *Self, addr: u16) Byte {
        // TODO: implement the whole memory map: https://www.nesdev.org/wiki/CPU_memory_map
        return self.RAM[addr];
    }

    pub fn step() !void {}

    // Fetch a byte of data from memory given an addressing mode.
    //
    pub fn readByte(self: *Self, mode: AddrMode) !u8 {
        return switch (mode) {
            .Implicit => NESError.Unreachable,
            .Accumulator => self.Accumulator,
        };
    }
};

const T = std.testing;

test "Status Register" {
    try T.expectEqual(1, @sizeOf(StatusRegister));
    try T.expectEqual(8, @bitSizeOf(StatusRegister));
}

test "CPU" {
    var cpu = CPU.init(T.allocator);
    try T.expectEqual(cpu.RAM.len, 2048);

    for (cpu.RAM) |byte| {
        try T.expectEqual(@as(i8, 0), byte);
    }
}
