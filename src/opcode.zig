// Useful reference: https://www.masswerk.at/6502/6502_instruction_set.html
pub const Op = enum {
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

// Decodes an instruction from its opcode.
pub fn decodeInstruction(opcode: u8) !Instruction {
    // This instruction set table is referenced from:
    // https://www.nesdev.org/obelisk-6502-guide/reference.html
    return switch (opcode) {
        0x69 => .{ Op.ADC, AddrMode.Immediate, 2 },
        0x65 => .{ Op.ADC, AddrMode.ZeroPage, 3 },
        0x75 => .{ Op.ADC, AddrMode.ZeroPageX, 4 },
        0x6D => .{ Op.ADC, AddrMode.Absolute, 4 },
        0x7D => .{ Op.ADC, AddrMode.AbsoluteX, 4 },
        0x79 => .{ Op.ADC, AddrMode.AbsoluteY, 4 },
        0x61 => .{ Op.ADC, AddrMode.IndirectX, 6 },
        0x71 => .{ Op.ADC, AddrMode.IndirectY, 5 },

        0x29 => .{ Op.AND, AddrMode.Immediate, 2 },
        0x25 => .{ Op.AND, AddrMode.ZeroPage, 3 },
        0x35 => .{ Op.AND, AddrMode.ZeroPageX, 4 },
        0x2D => .{ Op.AND, AddrMode.Absolute, 4 },
        0x3D => .{ Op.AND, AddrMode.AbsoluteX, 4 },
        0x39 => .{ Op.AND, AddrMode.AbsoluteY, 4 },
        0x21 => .{ Op.AND, AddrMode.IndirectX, 6 },
        0x31 => .{ Op.AND, AddrMode.IndirectY, 5 },

        0x0A => .{ Op.ASL, AddrMode.Accumulator, 2 },
        0x06 => .{ Op.ASL, AddrMode.ZeroPage, 5 },
        0x16 => .{ Op.ASL, AddrMode.ZeroPageX, 6 },
        0x0E => .{ Op.ASL, AddrMode.Absolute, 6 },
        0x1E => .{ Op.ASL, AddrMode.AbsoluteX, 7 },

        0x90 => .{ Op.BCC, AddrMode.Relative, 2 },

        0xB0 => .{ Op.BCS, AddrMode.Relative, 2 },

        0xF0 => .{ Op.BEQ, AddrMode.Relative, 2 },

        0x24 => .{ Op.BIT, AddrMode.ZeroPage, 3 },
        0x2C => .{ Op.BIT, AddrMode.Absolute, 4 },

        0x30 => .{ Op.BMI, AddrMode.Relative, 2 },

        0xD0 => .{ Op.BNE, AddrMode.Relative, 2 },

        0x10 => .{ Op.BPL, AddrMode.Relative, 2 },

        0x00 => .{ Op.BRK, AddrMode.Implicit, 7 },

        0x50 => .{ Op.BVC, AddrMode.Relative, 2 },

        0x70 => .{ Op.BVS, AddrMode.Relative, 2 },

        0x18 => .{ Op.CLC, AddrMode.Implicit, 2 },

        0xD8 => .{ Op.CLD, AddrMode.Implicit, 2 },

        0x58 => .{ Op.CLI, AddrMode.Implicit, 2 },

        0xB8 => .{ Op.CLV, AddrMode.Implicit, 2 },

        0xC9 => .{ Op.CMP, AddrMode.Immediate, 2 },
        0xC5 => .{ Op.CMP, AddrMode.ZeroPage, 3 },
        0xD5 => .{ Op.CMP, AddrMode.ZeroPageX, 4 },
        0xCD => .{ Op.CMP, AddrMode.Absolute, 4 },
        0xDD => .{ Op.CMP, AddrMode.AbsoluteX, 4 },
        0xD9 => .{ Op.CMP, AddrMode.AbsoluteY, 4 },
        0xC1 => .{ Op.CMP, AddrMode.IndirectX, 6 },
        0xD1 => .{ Op.CMP, AddrMode.IndirectY, 5 },

        0xE0 => .{ Op.CPX, AddrMode.Immediate, 2 },
        0xE4 => .{ Op.CPX, AddrMode.ZeroPage, 3 },
        0xEC => .{ Op.CPX, AddrMode.Absolute, 4 },

        0xC0 => .{ Op.CPY, AddrMode.Immediate, 2 },
        0xC4 => .{ Op.CPY, AddrMode.ZeroPage, 3 },
        0xCC => .{ Op.CPY, AddrMode.Absolute, 4 },

        0xC6 => .{ Op.DEC, AddrMode.ZeroPage, 5 },
        0xD6 => .{ Op.DEC, AddrMode.ZeroPageX, 6 },
        0xCE => .{ Op.DEC, AddrMode.Absolute, 6 },
        0xDE => .{ Op.DEC, AddrMode.AbsoluteX, 7 },

        0xCA => .{ Op.DEX, AddrMode.Implicit, 2 },

        0x88 => .{ Op.DEY, AddrMode.Implicit, 2 },

        0x49 => .{ Op.EOR, AddrMode.Immediate, 2 },
        0x45 => .{ Op.EOR, AddrMode.ZeroPage, 3 },
        0x55 => .{ Op.EOR, AddrMode.ZeroPageX, 4 },
        0x4D => .{ Op.EOR, AddrMode.Absolute, 4 },
        0x5D => .{ Op.EOR, AddrMode.AbsoluteX, 4 },
        0x59 => .{ Op.EOR, AddrMode.AbsoluteY, 4 },
        0x41 => .{ Op.EOR, AddrMode.IndirectX, 6 },
        0x51 => .{ Op.EOR, AddrMode.IndirectY, 5 },

        0xE6 => .{ Op.INC, AddrMode.ZeroPage, 5 },
        0xF6 => .{ Op.INC, AddrMode.ZeroPageX, 6 },
        0xEE => .{ Op.INC, AddrMode.Absolute, 6 },
        0xFE => .{ Op.INC, AddrMode.AbsoluteX, 7 },

        0xE8 => .{ Op.INX, AddrMode.Implicit, 2 },

        0xC8 => .{ Op.INY, AddrMode.Implicit, 2 },

        0x4C => .{ Op.JMP, AddrMode.Absolute, 3 },
        0x6C => .{ Op.JMP, AddrMode.Indirect, 5 },

        0x20 => .{ Op.JSR, AddrMode.Absolute, 6 },

        0xA9 => .{ Op.LDA, AddrMode.Immediate, 2 },
        0xA5 => .{ Op.LDA, AddrMode.ZeroPage, 3 },
        0xB5 => .{ Op.LDA, AddrMode.ZeroPageX, 4 },
        0xAD => .{ Op.LDA, AddrMode.Absolute, 4 },
        0xBD => .{ Op.LDA, AddrMode.AbsoluteX, 4 },
        0xB9 => .{ Op.LDA, AddrMode.AbsoluteY, 4 },
        0xA1 => .{ Op.LDA, AddrMode.IndirectX, 6 },
        0xB1 => .{ Op.LDA, AddrMode.IndirectY, 5 },

        0xA2 => .{ Op.LDX, AddrMode.Immediate, 2 },
        0xA6 => .{ Op.LDX, AddrMode.ZeroPage, 3 },
        0xB6 => .{ Op.LDX, AddrMode.ZeroPageY, 4 },
        0xAE => .{ Op.LDX, AddrMode.Absolute, 4 },
        0xBE => .{ Op.LDX, AddrMode.AbsoluteY, 4 },

        0xA0 => .{ Op.LDY, AddrMode.Immediate, 2 },
        0xA4 => .{ Op.LDY, AddrMode.ZeroPage, 3 },
        0xB4 => .{ Op.LDY, AddrMode.ZeroPageX, 4 },
        0xAC => .{ Op.LDY, AddrMode.Absolute, 4 },
        0xBC => .{ Op.LDY, AddrMode.AbsoluteX, 4 },

        0x4A => .{ Op.LSR, AddrMode.Accumulator, 2 },
        0x46 => .{ Op.LSR, AddrMode.ZeroPage, 5 },
        0x56 => .{ Op.LSR, AddrMode.ZeroPageX, 6 },
        0x4E => .{ Op.LSR, AddrMode.Absolute, 6 },
        0x5E => .{ Op.LSR, AddrMode.AbsoluteX, 7 },

        0xEA => .{ Op.NOP, AddrMode.Implicit, 2 },

        0x09 => .{ Op.ORA, AddrMode.Immediate, 2 },
        0x05 => .{ Op.ORA, AddrMode.ZeroPage, 3 },
        0x15 => .{ Op.ORA, AddrMode.ZeroPageX, 4 },
        0x0D => .{ Op.ORA, AddrMode.Absolute, 4 },
        0x1D => .{ Op.ORA, AddrMode.AbsoluteX, 4 },
        0x19 => .{ Op.ORA, AddrMode.AbsoluteY, 4 },
        0x01 => .{ Op.ORA, AddrMode.IndirectX, 6 },
        0x11 => .{ Op.ORA, AddrMode.IndirectY, 5 },

        0x48 => .{ Op.PHA, AddrMode.Implicit, 3 },

        0x08 => .{ Op.PHP, AddrMode.Implicit, 3 },

        0x68 => .{ Op.PLA, AddrMode.Implicit, 4 },

        0x28 => .{ Op.PLP, AddrMode.Implicit, 4 },

        0x2A => .{ Op.ROL, AddrMode.Accumulator, 2 },
        0x26 => .{ Op.ROL, AddrMode.ZeroPage, 5 },
        0x36 => .{ Op.ROL, AddrMode.ZeroPageX, 6 },
        0x2E => .{ Op.ROL, AddrMode.Absolute, 6 },
        0x3E => .{ Op.ROL, AddrMode.AbsoluteX, 7 },

        0x6A => .{ Op.ROR, AddrMode.Accumulator, 2 },
        0x66 => .{ Op.ROR, AddrMode.ZeroPage, 5 },
        0x76 => .{ Op.ROR, AddrMode.ZeroPageX, 6 },
        0x6E => .{ Op.ROR, AddrMode.Absolute, 6 },
        0x7E => .{ Op.ROR, AddrMode.AbsoluteX, 7 },

        0x40 => .{ Op.RTI, AddrMode.Implicit, 6 },

        0x60 => .{ Op.RTS, AddrMode.Implicit, 6 },

        0xE9 => .{ Op.SBC, AddrMode.Immediate, 2 },
        0xE5 => .{ Op.SBC, AddrMode.ZeroPage, 3 },
        0xF5 => .{ Op.SBC, AddrMode.ZeroPageX, 4 },
        0xED => .{ Op.SBC, AddrMode.Absolute, 4 },
        0xFD => .{ Op.SBC, AddrMode.AbsoluteX, 4 },
        0xF9 => .{ Op.SBC, AddrMode.AbsoluteY, 4 },
        0xE1 => .{ Op.SBC, AddrMode.IndirectX, 6 },
        0xF1 => .{ Op.SBC, AddrMode.IndirectY, 5 },

        0x38 => .{ Op.SEC, AddrMode.Implicit, 2 },

        0xF8 => .{ Op.SED, AddrMode.Implicit, 2 },

        0x78 => .{ Op.SEI, AddrMode.Implicit, 2 },

        0x85 => .{ Op.STA, AddrMode.ZeroPage, 3 },
        0x95 => .{ Op.STA, AddrMode.ZeroPageX, 4 },
        0x8D => .{ Op.STA, AddrMode.Absolute, 4 },
        0x9D => .{ Op.STA, AddrMode.AbsoluteX, 5 },
        0x99 => .{ Op.STA, AddrMode.AbsoluteY, 5 },
        0x81 => .{ Op.STA, AddrMode.IndirectX, 6 },
        0x91 => .{ Op.STA, AddrMode.IndirectY, 6 },

        0x86 => .{ Op.STX, AddrMode.ZeroPage, 3 },
        0x96 => .{ Op.STX, AddrMode.ZeroPageY, 4 },
        0x8E => .{ Op.STX, AddrMode.Absolute, 4 },

        0x84 => .{ Op.STY, AddrMode.ZeroPage, 3 },
        0x94 => .{ Op.STY, AddrMode.ZeroPageX, 4 },
        0x8C => .{ Op.STY, AddrMode.Absolute, 4 },

        0xAA => .{ Op.TAX, AddrMode.Implicit, 2 },

        0xA8 => .{ Op.TAY, AddrMode.Implicit, 2 },

        0xBA => .{ Op.TSX, AddrMode.Implicit, 2 },

        0x8A => .{ Op.TXA, AddrMode.Implicit, 2 },

        0x9A => .{ Op.TXS, AddrMode.Implicit, 2 },

        0x98 => .{ Op.TYA, AddrMode.Implicit, 2 },
        _ => "Unknown opcode",
    };
}
