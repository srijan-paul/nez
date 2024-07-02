const std = @import("std");

// Useful reference: https://www.masswerk.at/6502/6502_instruction_set.html
pub const Op = enum(u8) {
    ADC,
    AND,
    ASL,
    BCC,
    BCS,
    BEQ,
    BIT,
    BMI,
    BNE,
    BPL,
    BRK,
    BVC,
    BVS,
    CLC,
    CLD,
    CLI,
    CLV,
    CMP,
    CPX,
    CPY,
    DEC,
    DEX,
    DEY,
    EOR,
    INC,
    INX,
    INY,
    JMP,
    JSR,
    LDA,
    LDX,
    LDY,
    LSR,
    NOP,
    ORA,
    PHA,
    PHP,
    PLA,
    PLP,
    ROL,
    ROR,
    RTI,
    RTS,
    SBC,
    SEC,
    SED,
    SEI,
    STA,
    STX,
    STY,
    TAX,
    TAY,
    TSX,
    TXA,
    TXS,
    TYA,
    Unknown,
};

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
    Implicit,
    Relative,
    Invalid,
};

// 3-tuple: opcode, addressing mode, cycles
pub const Instruction = struct { Op, AddrMode, u8 };

// Returns the number of bytes needed for an instruction that has the given addressing mode.
pub fn bytesForAddrMode(addrMode: AddrMode) u8 {
    return switch (addrMode) {
        AddrMode.Immediate => 2,
        AddrMode.Accumulator => 1,
        AddrMode.ZeroPage => 2,
        AddrMode.ZeroPageX => 2,
        AddrMode.ZeroPageY => 2,
        AddrMode.Absolute => 3,
        AddrMode.AbsoluteX => 3,
        AddrMode.AbsoluteY => 3,
        AddrMode.Indirect => 3,
        AddrMode.IndirectX => 2,
        AddrMode.IndirectY => 2,
        AddrMode.Implicit => 1,
        AddrMode.Invalid => 0,
    };
}

// Returns a table that maps opcodes to instructions.
// This instruction set table is referenced from:
// https://www.nesdev.org/obelisk-6502-guide/reference.html
fn makeLookupTable() [256]Instruction {
    comptime {
        const Mode = AddrMode;
        var instr_lookup_table: [256]Instruction = .{BadInstruction} ** 256;

        instr_lookup_table[0x69] = .{ Op.ADC, Mode.Immediate, 2 };
        instr_lookup_table[0x65] = .{ Op.ADC, Mode.ZeroPage, 3 };
        instr_lookup_table[0x75] = .{ Op.ADC, Mode.ZeroPageX, 4 };
        instr_lookup_table[0x6D] = .{ Op.ADC, Mode.Absolute, 4 };
        instr_lookup_table[0x7D] = .{ Op.ADC, Mode.AbsoluteX, 4 };
        instr_lookup_table[0x79] = .{ Op.ADC, Mode.AbsoluteY, 4 };
        instr_lookup_table[0x61] = .{ Op.ADC, Mode.IndirectX, 6 };
        instr_lookup_table[0x71] = .{ Op.ADC, Mode.IndirectY, 5 };

        instr_lookup_table[0x29] = .{ Op.AND, Mode.Immediate, 2 };
        instr_lookup_table[0x25] = .{ Op.AND, Mode.ZeroPage, 3 };
        instr_lookup_table[0x35] = .{ Op.AND, Mode.ZeroPageX, 4 };
        instr_lookup_table[0x2D] = .{ Op.AND, Mode.Absolute, 4 };
        instr_lookup_table[0x3D] = .{ Op.AND, Mode.AbsoluteX, 4 };
        instr_lookup_table[0x39] = .{ Op.AND, Mode.AbsoluteY, 4 };
        instr_lookup_table[0x21] = .{ Op.AND, Mode.IndirectX, 6 };
        instr_lookup_table[0x31] = .{ Op.AND, Mode.IndirectY, 5 };

        instr_lookup_table[0x0A] = .{ Op.ASL, Mode.Accumulator, 2 };
        instr_lookup_table[0x06] = .{ Op.ASL, Mode.ZeroPage, 5 };
        instr_lookup_table[0x16] = .{ Op.ASL, Mode.ZeroPageX, 6 };
        instr_lookup_table[0x0E] = .{ Op.ASL, Mode.Absolute, 6 };
        instr_lookup_table[0x1E] = .{ Op.ASL, Mode.AbsoluteX, 7 };

        instr_lookup_table[0x90] = .{ Op.BCC, Mode.Relative, 2 };

        instr_lookup_table[0xB0] = .{ Op.BCS, Mode.Relative, 2 };

        instr_lookup_table[0xF0] = .{ Op.BEQ, Mode.Relative, 2 };

        instr_lookup_table[0x24] = .{ Op.BIT, Mode.ZeroPage, 3 };
        instr_lookup_table[0x2C] = .{ Op.BIT, Mode.Absolute, 4 };

        instr_lookup_table[0x30] = .{ Op.BMI, Mode.Relative, 2 };

        instr_lookup_table[0xD0] = .{ Op.BNE, Mode.Relative, 2 };

        instr_lookup_table[0x10] = .{ Op.BPL, Mode.Relative, 2 };

        instr_lookup_table[0x00] = .{ Op.BRK, Mode.Implicit, 7 };

        instr_lookup_table[0x50] = .{ Op.BVC, Mode.Relative, 2 };

        instr_lookup_table[0x70] = .{ Op.BVS, Mode.Relative, 2 };

        instr_lookup_table[0x18] = .{ Op.CLC, Mode.Implicit, 2 };

        instr_lookup_table[0xD8] = .{ Op.CLD, Mode.Implicit, 2 };

        instr_lookup_table[0x58] = .{ Op.CLI, Mode.Implicit, 2 };

        instr_lookup_table[0xB8] = .{ Op.CLV, Mode.Implicit, 2 };

        instr_lookup_table[0xC9] = .{ Op.CMP, Mode.Immediate, 2 };
        instr_lookup_table[0xC5] = .{ Op.CMP, Mode.ZeroPage, 3 };
        instr_lookup_table[0xD5] = .{ Op.CMP, Mode.ZeroPageX, 4 };
        instr_lookup_table[0xCD] = .{ Op.CMP, Mode.Absolute, 4 };
        instr_lookup_table[0xDD] = .{ Op.CMP, Mode.AbsoluteX, 4 };
        instr_lookup_table[0xD9] = .{ Op.CMP, Mode.AbsoluteY, 4 };
        instr_lookup_table[0xC1] = .{ Op.CMP, Mode.IndirectX, 6 };
        instr_lookup_table[0xD1] = .{ Op.CMP, Mode.IndirectY, 5 };

        instr_lookup_table[0xE0] = .{ Op.CPX, Mode.Immediate, 2 };
        instr_lookup_table[0xE4] = .{ Op.CPX, Mode.ZeroPage, 3 };
        instr_lookup_table[0xEC] = .{ Op.CPX, Mode.Absolute, 4 };

        instr_lookup_table[0xC0] = .{ Op.CPY, Mode.Immediate, 2 };
        instr_lookup_table[0xC4] = .{ Op.CPY, Mode.ZeroPage, 3 };
        instr_lookup_table[0xCC] = .{ Op.CPY, Mode.Absolute, 4 };

        instr_lookup_table[0xC6] = .{ Op.DEC, Mode.ZeroPage, 5 };
        instr_lookup_table[0xD6] = .{ Op.DEC, Mode.ZeroPageX, 6 };
        instr_lookup_table[0xCE] = .{ Op.DEC, Mode.Absolute, 6 };
        instr_lookup_table[0xDE] = .{ Op.DEC, Mode.AbsoluteX, 7 };

        instr_lookup_table[0xCA] = .{ Op.DEX, Mode.Implicit, 2 };

        instr_lookup_table[0x88] = .{ Op.DEY, Mode.Implicit, 2 };

        instr_lookup_table[0x49] = .{ Op.EOR, Mode.Immediate, 2 };
        instr_lookup_table[0x45] = .{ Op.EOR, Mode.ZeroPage, 3 };
        instr_lookup_table[0x55] = .{ Op.EOR, Mode.ZeroPageX, 4 };
        instr_lookup_table[0x4D] = .{ Op.EOR, Mode.Absolute, 4 };
        instr_lookup_table[0x5D] = .{ Op.EOR, Mode.AbsoluteX, 4 };
        instr_lookup_table[0x59] = .{ Op.EOR, Mode.AbsoluteY, 4 };
        instr_lookup_table[0x41] = .{ Op.EOR, Mode.IndirectX, 6 };
        instr_lookup_table[0x51] = .{ Op.EOR, Mode.IndirectY, 5 };

        instr_lookup_table[0xE6] = .{ Op.INC, Mode.ZeroPage, 5 };
        instr_lookup_table[0xF6] = .{ Op.INC, Mode.ZeroPageX, 6 };
        instr_lookup_table[0xEE] = .{ Op.INC, Mode.Absolute, 6 };
        instr_lookup_table[0xFE] = .{ Op.INC, Mode.AbsoluteX, 7 };

        instr_lookup_table[0xE8] = .{ Op.INX, Mode.Implicit, 2 };

        instr_lookup_table[0xC8] = .{ Op.INY, Mode.Implicit, 2 };

        instr_lookup_table[0x4C] = .{ Op.JMP, Mode.Absolute, 3 };
        instr_lookup_table[0x6C] = .{ Op.JMP, Mode.Indirect, 5 };

        instr_lookup_table[0x20] = .{ Op.JSR, Mode.Absolute, 6 };

        instr_lookup_table[0xA9] = .{ Op.LDA, Mode.Immediate, 2 };
        instr_lookup_table[0xA5] = .{ Op.LDA, Mode.ZeroPage, 3 };
        instr_lookup_table[0xB5] = .{ Op.LDA, Mode.ZeroPageX, 4 };
        instr_lookup_table[0xAD] = .{ Op.LDA, Mode.Absolute, 4 };
        instr_lookup_table[0xBD] = .{ Op.LDA, Mode.AbsoluteX, 4 };
        instr_lookup_table[0xB9] = .{ Op.LDA, Mode.AbsoluteY, 4 };
        instr_lookup_table[0xA1] = .{ Op.LDA, Mode.IndirectX, 6 };
        instr_lookup_table[0xB1] = .{ Op.LDA, Mode.IndirectY, 5 };

        instr_lookup_table[0xA2] = .{ Op.LDX, Mode.Immediate, 2 };
        instr_lookup_table[0xA6] = .{ Op.LDX, Mode.ZeroPage, 3 };
        instr_lookup_table[0xB6] = .{ Op.LDX, Mode.ZeroPageY, 4 };
        instr_lookup_table[0xAE] = .{ Op.LDX, Mode.Absolute, 4 };
        instr_lookup_table[0xBE] = .{ Op.LDX, Mode.AbsoluteY, 4 };

        instr_lookup_table[0xA0] = .{ Op.LDY, Mode.Immediate, 2 };
        instr_lookup_table[0xA4] = .{ Op.LDY, Mode.ZeroPage, 3 };
        instr_lookup_table[0xB4] = .{ Op.LDY, Mode.ZeroPageX, 4 };
        instr_lookup_table[0xAC] = .{ Op.LDY, Mode.Absolute, 4 };
        instr_lookup_table[0xBC] = .{ Op.LDY, Mode.AbsoluteX, 4 };

        instr_lookup_table[0x4A] = .{ Op.LSR, Mode.Accumulator, 2 };
        instr_lookup_table[0x46] = .{ Op.LSR, Mode.ZeroPage, 5 };
        instr_lookup_table[0x56] = .{ Op.LSR, Mode.ZeroPageX, 6 };
        instr_lookup_table[0x4E] = .{ Op.LSR, Mode.Absolute, 6 };
        instr_lookup_table[0x5E] = .{ Op.LSR, Mode.AbsoluteX, 7 };

        instr_lookup_table[0xEA] = .{ Op.NOP, Mode.Implicit, 2 };

        instr_lookup_table[0x09] = .{ Op.ORA, Mode.Immediate, 2 };
        instr_lookup_table[0x05] = .{ Op.ORA, Mode.ZeroPage, 3 };
        instr_lookup_table[0x15] = .{ Op.ORA, Mode.ZeroPageX, 4 };
        instr_lookup_table[0x0D] = .{ Op.ORA, Mode.Absolute, 4 };
        instr_lookup_table[0x1D] = .{ Op.ORA, Mode.AbsoluteX, 4 };
        instr_lookup_table[0x19] = .{ Op.ORA, Mode.AbsoluteY, 4 };
        instr_lookup_table[0x01] = .{ Op.ORA, Mode.IndirectX, 6 };
        instr_lookup_table[0x11] = .{ Op.ORA, Mode.IndirectY, 5 };

        instr_lookup_table[0x48] = .{ Op.PHA, Mode.Implicit, 3 };

        instr_lookup_table[0x08] = .{ Op.PHP, Mode.Implicit, 3 };

        instr_lookup_table[0x68] = .{ Op.PLA, Mode.Implicit, 4 };

        instr_lookup_table[0x28] = .{ Op.PLP, Mode.Implicit, 4 };

        instr_lookup_table[0x2A] = .{ Op.ROL, Mode.Accumulator, 2 };
        instr_lookup_table[0x26] = .{ Op.ROL, Mode.ZeroPage, 5 };
        instr_lookup_table[0x36] = .{ Op.ROL, Mode.ZeroPageX, 6 };
        instr_lookup_table[0x2E] = .{ Op.ROL, Mode.Absolute, 6 };
        instr_lookup_table[0x3E] = .{ Op.ROL, Mode.AbsoluteX, 7 };

        instr_lookup_table[0x6A] = .{ Op.ROR, Mode.Accumulator, 2 };
        instr_lookup_table[0x66] = .{ Op.ROR, Mode.ZeroPage, 5 };
        instr_lookup_table[0x76] = .{ Op.ROR, Mode.ZeroPageX, 6 };
        instr_lookup_table[0x6E] = .{ Op.ROR, Mode.Absolute, 6 };
        instr_lookup_table[0x7E] = .{ Op.ROR, Mode.AbsoluteX, 7 };

        instr_lookup_table[0x40] = .{ Op.RTI, Mode.Implicit, 6 };

        instr_lookup_table[0x60] = .{ Op.RTS, Mode.Implicit, 6 };

        instr_lookup_table[0xE9] = .{ Op.SBC, Mode.Immediate, 2 };
        instr_lookup_table[0xE5] = .{ Op.SBC, Mode.ZeroPage, 3 };
        instr_lookup_table[0xF5] = .{ Op.SBC, Mode.ZeroPageX, 4 };
        instr_lookup_table[0xED] = .{ Op.SBC, Mode.Absolute, 4 };
        instr_lookup_table[0xFD] = .{ Op.SBC, Mode.AbsoluteX, 4 };
        instr_lookup_table[0xF9] = .{ Op.SBC, Mode.AbsoluteY, 4 };
        instr_lookup_table[0xE1] = .{ Op.SBC, Mode.IndirectX, 6 };
        instr_lookup_table[0xF1] = .{ Op.SBC, Mode.IndirectY, 5 };

        instr_lookup_table[0x38] = .{ Op.SEC, Mode.Implicit, 2 };

        instr_lookup_table[0xF8] = .{ Op.SED, Mode.Implicit, 2 };

        instr_lookup_table[0x78] = .{ Op.SEI, Mode.Implicit, 2 };

        instr_lookup_table[0x85] = .{ Op.STA, Mode.ZeroPage, 3 };
        instr_lookup_table[0x95] = .{ Op.STA, Mode.ZeroPageX, 4 };
        instr_lookup_table[0x8D] = .{ Op.STA, Mode.Absolute, 4 };
        instr_lookup_table[0x9D] = .{ Op.STA, Mode.AbsoluteX, 5 };
        instr_lookup_table[0x99] = .{ Op.STA, Mode.AbsoluteY, 5 };
        instr_lookup_table[0x81] = .{ Op.STA, Mode.IndirectX, 6 };
        instr_lookup_table[0x91] = .{ Op.STA, Mode.IndirectY, 6 };

        instr_lookup_table[0x86] = .{ Op.STX, Mode.ZeroPage, 3 };
        instr_lookup_table[0x96] = .{ Op.STX, Mode.ZeroPageY, 4 };
        instr_lookup_table[0x8E] = .{ Op.STX, Mode.Absolute, 4 };

        instr_lookup_table[0x84] = .{ Op.STY, Mode.ZeroPage, 3 };
        instr_lookup_table[0x94] = .{ Op.STY, Mode.ZeroPageX, 4 };
        instr_lookup_table[0x8C] = .{ Op.STY, Mode.Absolute, 4 };

        instr_lookup_table[0xAA] = .{ Op.TAX, Mode.Implicit, 2 };

        instr_lookup_table[0xA8] = .{ Op.TAY, Mode.Implicit, 2 };

        instr_lookup_table[0xBA] = .{ Op.TSX, Mode.Implicit, 2 };

        instr_lookup_table[0x8A] = .{ Op.TXA, Mode.Implicit, 2 };

        instr_lookup_table[0x9A] = .{ Op.TXS, Mode.Implicit, 2 };

        instr_lookup_table[0x98] = .{ Op.TYA, Mode.Implicit, 2 };
        return instr_lookup_table;
    }
}

pub const BadInstruction: Instruction = .{ Op.Unknown, AddrMode.Invalid, 0 };
const lookup_table = makeLookupTable();

// Decodes an instruction from its opcode.
pub fn decodeInstruction(opcode: u8) *const Instruction {
    return &lookup_table[opcode];
}

comptime {
    std.debug.assert(lookup_table.len == 256);
    std.debug.assert(lookup_table[0xA9][0] == Op.LDA);
}

const T = std.testing;
test "instruction lookup table" {
    const lda_imm = lookup_table[0xA9];
    try T.expectEqual(Op.LDA, lda_imm[0]);
    try T.expectEqual(AddrMode.Immediate, lda_imm[1]);
    try T.expectEqual(@as(u8, 2), lda_imm[2]);
}
