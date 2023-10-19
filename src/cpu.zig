const std = @import("std");
const assert = std.debug.assert;
const T = std.testing;
const Allocator = std.mem.Allocator;

// ref: https://www.nesdev.org/wiki/CPU_addressing_modes
pub const AddrMode = enum {
    Immediate,
    Accumulator,
    ZeroPage,
    ZeroPageX,
    ZeroPageY,
    Absolute,
    AbsoluteX,
    AbsoluteY,
    Indirect,
    IndirectX,
    IndirectY,
    Relative,
    Implicit,
};

// Useful reference: https://www.masswerk.at/6502/6502_instruction_set.html
pub const Opcode = enum(u8) {
    LDAimm = 0xA9,
    LDAzrpg = 0xA5,

    // JAMx instructions freeze the CPU
    JAM0 = 0x02,
    JAM1 = 0x12,
    JAM2 = 0x22,
    JAM3 = 0x32,
    JAM4 = 0x42,
    JAM5 = 0x52,
    JAM6 = 0x62,
    JAM7 = 0x72,
    JAM9 = 0x92,
    JAMB = 0xB2,
    JAMD = 0xB2,
    JAMF = 0xF2,
};

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

pub const NESError = error{ InvalidAddressingMode, NotImplemented, Unreachable };

pub const CPU = struct {
    const Self = @This();
    // each page in the RAM is 256 bytes.
    const PageSize = 256;

    var cycles_to_wait = 0;

    // capacity of the RAM chip attached to the CPU (in bytes)
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

    pub fn fetch_byte(self: *Self, mode: AddrMode, addr: u16) !Byte {
        return switch (mode) {
            .Immediate => NESError.Unreachable,
            .Implicit => NESError.Unreachable,
            .Absolute => self.index_memory(addr),
        };
    }
};

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
