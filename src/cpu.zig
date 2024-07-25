const std = @import("std");
const opcode = @import("opcode.zig");
const cart = @import("cart.zig");
const util = @import("util.zig");
const bus_module = @import("bus.zig");

const Bus = bus_module.Bus;
const TestBus = bus_module.TestBus;

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const AddrMode = opcode.AddrMode;
const Op = opcode.Op;
const Instruction = opcode.Instruction;
const NESError = util.NESError;

pub const Register = u8;

/// The kinds of interrupts that can be serviced by the CPU
pub const InterruptKind = enum {
    /// Non-maskable interrupt
    nmi,
    /// IRQ interrupt
    irq,
    /// No interrupt
    none,
};

pub const StatusRegister = packed struct {
    // Carry Flag
    C: bool = false,
    // Zero Flag
    Z: bool = false,
    // Interrupt Disable
    I: bool = false,
    D: bool = false,
    // B-Flag. Not used by the user.
    B: bool = false,
    // This status flag does nothing, and is always set to 1.
    _: bool = true,
    // Overflow Flag
    V: bool = false,
    // Negative Flag
    N: bool = false,

    const Self = @This();
    comptime {
        assert(@sizeOf(Self) == 1);
        assert(@bitSizeOf(Self) == 8);
    }
};

// State of the CPU used for point-in-time tests.
pub const CPUState = struct {
    const Self = @This();
    const Cell = struct { u16, u8 };
    pc: u16,
    s: u8,
    a: u8,
    x: u8,
    y: u8,
    p: u8,
    ram: []Cell,
};

pub const CPU = struct {
    const Self = @This();
    // each page in the RAM is 256 bytes.
    const PageSize = 256;

    /// The NMI handler's address is located at 0xFFFA/0xFFFB
    const NmiHandlerAddr = 0xFFFA;
    /// The IRQ handler's address is located at 0xFFFE/0xFFFF
    const IrqHandlerAddr = 0xFFFE;

    // capacity of the RAM chip attached to the CPU in bytes
    // (called SRAM (S = static), or WRAM(W = work))
    pub const w_ram_size = 0x800;
    RAM: [w_ram_size]u8 = .{0} ** w_ram_size,
    // number of cycles to cycles to wait
    // before executing the next instruction.
    cycles_to_wait: u16 = 0,

    // registers
    A: Register = 0,

    // Used for addressing modes, and loop counters.
    X: Register = 0,
    Y: Register = 0,

    // can be accessed using interrupts.
    // The stack is located at 0x100 - 0x1FF.
    // The stack grows downwards. i.e, the stack pointer is decremented
    // when somethig is pushed onto the stack.
    S: Register = 0,

    // The program counter is 16 bit, since it holds an address.
    PC: u16 = 0,

    StatusRegister: StatusRegister = .{},

    bus: *Bus,

    interrupt_pending: InterruptKind = .none,

    allocator: Allocator,

    currentInstr: *const Instruction = &opcode.BadInstruction,

    pub fn init(allocator: Allocator, bus: *Bus) Self {
        return .{ .allocator = allocator, .bus = bus };
    }

    /// Read a byte of data from `addr` in memory.
    pub inline fn memRead(self: *Self, addr: u16) u8 {
        return self.bus.read(addr);
    }

    /// Write a byte of data to `addr` in memory.
    pub inline fn memWrite(self: *Self, addr: u16, byte: u8) void {
        self.bus.write(addr, byte);
    }

    inline fn incPC(self: *Self) void {
        self.PC = @addWithOverflow(self.PC, @as(u16, 1))[0];
    }

    // fetch the next byte to execute.
    inline fn nextOp(self: *Self) u8 {
        const byte = self.memRead(self.PC);
        self.incPC();
        return byte;
    }

    /// Fetch the next two bytes from the program counter,
    /// and stitch them together to get a 16 bit address from memory.
    inline fn getAddr16(self: *Self) u16 {
        const low: u16 = self.nextOp();
        const high: u16 = self.nextOp();
        return low | (high << 8);
    }

    /// Get the address pointed to by the operand of the instruction `instr`.
    fn addrOfInstruction(self: *Self, instr: *const Instruction) u16 {
        const mode = instr[1];
        switch (mode) {
            .Immediate => {
                const addr = self.PC;
                self.incPC();
                return addr;
            },

            .Accumulator => unreachable,

            .Absolute => {
                return self.getAddr16();
            },

            .AbsoluteX => {
                var addr = self.getAddr16();
                addr = @addWithOverflow(addr, self.X)[0];
                return addr;
            },

            .AbsoluteY => {
                var addr = self.getAddr16();
                addr = @addWithOverflow(addr, self.Y)[0];
                return addr;
            },

            .ZeroPage => {
                const addr = self.nextOp();
                return addr;
            },

            .ZeroPageX => {
                var addr: u16 = self.nextOp();
                addr += self.X;
                // zero page addressed reads cannot
                // cross page boundaries.
                addr = addr % CPU.PageSize;
                return addr;
            },

            .ZeroPageY => {
                var addr: u16 = self.nextOp();
                addr += self.Y;
                // zero page addressed reads cannot
                // cross page boundaries.
                addr = addr % CPU.PageSize;
                return addr;
            },

            .Relative => {
                unreachable;
            },

            .Indirect => {
                const addr = self.getAddr16();
                const low: u16 = self.memRead(addr);
                const high: u16 = self.memRead(addr + 1);
                const final_addr = low | (high << 8);
                return final_addr;
            },

            // TODO: support zero page wrap around.
            .IndirectX => {
                const addr: u8 = @truncate(self.nextOp() + @as(u16, self.X));
                const low: u16 = self.memRead(addr);
                const next_addr = @addWithOverflow(addr, 1)[0];
                const high: u16 = self.memRead(next_addr);
                const final_addr = low | (high << 8);
                return final_addr;
            },

            // TODO: support zero page wrap around.
            .IndirectY => {
                const addr = self.nextOp();
                const low: u16 = self.memRead(addr);
                const high: u16 = self.memRead(@addWithOverflow(addr, 1)[0]);
                const final_addr = @addWithOverflow((low | (high << 8)), self.Y)[0];
                return final_addr;
            },

            else => unreachable,
        }
    }

    /// Depending on the addressing mode of the instruction `instr`,
    /// get a byte of the data from memory.
    fn operand(self: *Self, instr: *const Instruction) u8 {
        const mode = instr[1];
        if (mode == .Accumulator) return self.A;
        const addr = self.addrOfInstruction(instr);
        return self.memRead(addr);
    }

    /// set the Z flag if the lower 8 bits of `value` are all 0.
    inline fn setFlagZ(self: *Self, value: u16) void {
        self.StatusRegister.Z = value & 0xFF == 0;
    }

    /// set the `N` flag if the MSB of `value` is 1.
    inline fn setFlagN(self: *Self, value: u16) void {
        self.StatusRegister.N = value & 0b1000_0000 != 0;
    }

    // set the Z and N flags based on the lower 8 bits of `value`.
    inline fn setZN(self: *Self, value: u16) void {
        self.setFlagZ(value);
        self.setFlagN(value);
    }

    /// set the `C` flag if `value` is greater than 0xFF (u8 max).
    inline fn setC(self: *Self, value: u16) void {
        self.StatusRegister.C = value > std.math.maxInt(u8);
    }

    /// Get the address pointed to the by the current stack pointer.
    inline fn stackAddr(self: *Self) u16 {
        return @addWithOverflow(0x100, @as(u16, self.S))[0];
    }

    /// Push `value` onto the stack, and decrement the stack pointer.
    fn push(self: *Self, value: u8) void {
        const addr = self.stackAddr();
        self.memWrite(addr, value);
        // decrement the stack pointer.
        self.S = @subWithOverflow(self.S, 1)[0];
    }

    /// Pops a value from the stack.
    fn pop(self: *Self) u8 {
        self.S = @addWithOverflow(self.S, 1)[0];
        const addr = self.stackAddr();
        return self.memRead(addr);
    }

    /// Perform a branch if `cond` is true.
    fn branchIf(self: *Self, cond: bool) void {
        if (cond) {
            self.cycles_to_wait += 1;

            // jump offset is signed.
            const offset: i8 = @bitCast(self.nextOp());
            const old_pc: i32 = self.PC;
            const new_pc: u32 = @bitCast(old_pc + offset);
            self.PC = @truncate(new_pc);
            // if the branch jumps to a new page, add an extra cycle.
            if (old_pc & 0xFF00 != new_pc & 0xFF00) {
                self.cycles_to_wait += 1;
            }
        } else {
            self.incPC();
        }
    }

    /// Perform the `ROL` instruction, using `byte` as the operand,
    /// but do not write the result back to memory.
    inline fn rol(self: *Self, byte: u8) u8 {
        const old_carry: u8 = if (self.StatusRegister.C) 1 else 0;

        const shlResult = @shlWithOverflow(byte, @as(u8, 1));

        // set the new bit-0 to the old carry.
        const res = shlResult[0] | old_carry;
        self.setZN(res);

        // the bit that was shifted out when performing a <<
        const shifted_bit = shlResult[1];
        self.StatusRegister.C = shifted_bit == 1;
        return res;
    }

    /// Perform the `ROR` instruction using `byte` as the operand,
    /// but do not write the result back to memory.
    inline fn ror(self: *Self, byte: u8) u8 {
        const old_carry: u8 = if (self.StatusRegister.C) 1 else 0;

        const old_b0 = byte & 0b0000_0001; // old 0th bit
        var res = byte >> 1;
        // set the new MSB to the old carry.
        res = res | (old_carry << 7);

        self.setZN(res);

        // the bit that was shifted out when performing a >>
        self.StatusRegister.C = old_b0 == 1;
        return res;
    }

    /// Perform the 'ASL' instruction and set appropriate flags, but do
    /// not write the resulting back to memory.
    inline fn asl(self: *Self, byte: u8) u8 {
        const res: u16 = @as(u16, byte) << 1;
        self.setZN(res);
        self.setC(res);
        return @truncate(res);
    }

    /// Perform the `ADC` CPU operation on `arg`.
    inline fn adc(self: *Self, arg: u8) void {
        const byte: u16 = arg;
        const carry: u16 = if (self.StatusRegister.C) 1 else 0;
        const sum: u16 = self.A + byte + carry;

        self.setZN(sum);
        self.setC(sum);
        self.StatusRegister.V = ((self.A ^ sum) & (byte ^ sum) & 0b1000_0000) != 0;

        self.A = @truncate(sum);
    }

    /// Execute a single instruction.
    pub fn exec(self: *Self, instr: *const Instruction) !void {
        const op = instr[0];
        const mode: AddrMode = instr[1];

        if (self.PC == 0xE19B + 1) {
            // const bus: *bus_module.NESBus = @fieldParentPtr("bus", self.bus);
            // std.debug.print("Op: {s}, Mode: {s} (PPU scanline={d})\n", .{ @tagName(op), @tagName(mode), bus.ppu.scanline });
        }

        switch (op) {
            Op.ADC => self.adc(self.operand(instr)),

            // SBC is equivalent to ADC(~arg).
            // Ref: http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html
            Op.SBC => self.adc(~self.operand(instr)),

            Op.AND => {
                const byte = self.operand(instr);
                const result = self.A & byte;
                self.A = result;
                self.setZN(result);
            },

            Op.ASL => {
                if (mode == AddrMode.Accumulator) {
                    self.A = self.asl(self.A);
                } else {
                    const dst = self.addrOfInstruction(instr);
                    const byte = self.memRead(dst);
                    // Peculiar behavior of R-M-W (Read modify write) instructions.
                    // The value is written as-is first, and then the modified value is written.
                    // Emulating this is sometimes important, because the mapper might respond differently to these writes.
                    self.memWrite(dst, byte);
                    self.memWrite(dst, self.asl(byte));
                }
            },

            Op.BIT => {
                const byte = self.operand(instr);
                const result = self.A & byte;
                self.StatusRegister.Z = result == 0;
                self.StatusRegister.N = (byte & 0b1000_0000) != 0;
                self.StatusRegister.V = (byte & 0b0100_0000) != 0;
            },

            Op.BVC => self.branchIf(!self.StatusRegister.V),
            Op.BVS => self.branchIf(self.StatusRegister.V),
            Op.BCC => self.branchIf(!self.StatusRegister.C),
            Op.BCS => self.branchIf(self.StatusRegister.C),
            Op.BEQ => self.branchIf(self.StatusRegister.Z),
            Op.BMI => self.branchIf(self.StatusRegister.N),
            Op.BNE => self.branchIf(!self.StatusRegister.Z),
            Op.BPL => self.branchIf(!self.StatusRegister.N),

            Op.BRK => {
                // Contrary to what most of the online documentations state,
                // the BRK instruction is a TWO byte opcode.
                // The first byte is the opcode itself, and the second byte
                // is a padding byte that is ignored by the CPU.
                // Ref: https://www.nesdev.org/the%20%27B%27%20flag%20&%20BRK%20instruction.txt
                self.incPC();

                self.push(@truncate(self.PC >> 8)); // push PCHigh
                self.push(@truncate(self.PC)); // push PCLow

                // There is no actual "B" flag in the hardware.
                // Its just set before pushing Status register to the stack
                var flags = self.StatusRegister;
                flags.B = true;
                self.push(@bitCast(flags)); // push status

                const handler_lo: u16 = self.memRead(0xFFFE);
                const handler_hi: u16 = self.memRead(0xFFFF);
                self.PC = (handler_hi << 8) | handler_lo;
                self.StatusRegister.I = true;
            },

            Op.CLC => self.StatusRegister.C = false,
            Op.CLD => self.StatusRegister.D = false,
            Op.CLI => self.StatusRegister.I = false,
            Op.CLV => self.StatusRegister.V = false,

            Op.CMP => {
                const byte: u8 = self.operand(instr);
                const result = @subWithOverflow(self.A, byte)[0];
                self.setZN(result);
                self.StatusRegister.C = self.A >= byte;
            },

            Op.CPX => {
                const byte: u8 = self.operand(instr);
                const result = @subWithOverflow(self.X, byte)[0];
                self.setZN(result);
                self.StatusRegister.C = self.X >= byte;
            },

            Op.CPY => {
                const byte: u8 = self.operand(instr);
                const result = @subWithOverflow(self.Y, byte)[0];
                self.setZN(result);
                self.StatusRegister.C = self.Y >= byte;
            },

            Op.DEC => {
                const dst_addr = self.addrOfInstruction(instr);
                const byte = self.memRead(dst_addr);
                const res = @subWithOverflow(byte, 1)[0];
                self.setZN(res);
                // Peculiar behavior of R-M-W instructions.
                // The value is written as-is first, and then the modified value is written.
                self.memWrite(dst_addr, byte);
                self.memWrite(dst_addr, res);
            },

            Op.DEX => {
                const res = @subWithOverflow(self.X, 1)[0];
                self.setZN(res);
                self.X = res;
            },

            Op.DEY => {
                const res = @subWithOverflow(self.Y, 1)[0];
                self.setZN(res);
                self.Y = res;
            },

            Op.EOR => {
                const byte = self.operand(instr);
                self.A = self.A ^ byte;
                self.setZN(self.A);
            },

            Op.INC => {
                const dst = self.addrOfInstruction(instr);
                const byte = self.memRead(dst);
                const res = @addWithOverflow(byte, 1)[0];
                self.setZN(res);
                // Peculiar behavior of R-M-W instructions.
                // The value is written as-is first, and then the modified value is written.
                self.memWrite(dst, byte);
                self.memWrite(dst, res);
            },

            Op.INX => {
                const res = @addWithOverflow(self.X, 1)[0];
                self.setZN(res);
                self.X = res;
            },

            Op.INY => {
                const res = @addWithOverflow(self.Y, 1)[0];
                self.setZN(res);
                self.Y = res;
            },

            Op.JMP => {
                if (instr[1] == AddrMode.Absolute) {
                    self.PC = self.getAddr16();
                } else {
                    assert(instr[1] == AddrMode.Indirect);
                    const addr_addr = self.getAddr16();
                    var lo: u16 = undefined;
                    var hi: u16 = undefined;
                    // If the indirect vector falls on a page boundary
                    // (e.g. $xxFF where xx is any value from $00 to $FF),
                    // then the low byte is fetched from $xxFF as expected,
                    // but the high byte is fetched from $xx00.
                    if (addr_addr & 0xFF == 0xFF) {
                        // Emulate 6502 bug.
                        lo = self.memRead(addr_addr);
                        hi = self.memRead(addr_addr & 0xFF00);
                    } else {
                        lo = self.memRead(addr_addr);
                        hi = self.memRead(addr_addr + 1);
                    }
                    self.PC = (hi << 8) | lo;
                }
            },

            Op.JSR => {
                const return_addr = @addWithOverflow(self.PC, @as(u16, 1))[0];
                self.push(@truncate(return_addr >> 8)); // high byte
                self.push(@truncate(return_addr)); // low byte
                self.PC = self.getAddr16();
            },

            Op.LDA => {
                const byte = self.operand(instr);
                self.A = byte;
                self.setZN(byte);
            },

            Op.LDX => {
                const byte = self.operand(instr);
                self.X = byte;
                self.setZN(byte);
            },

            Op.LDY => {
                const byte = self.operand(instr);
                self.Y = byte;
                self.setZN(byte);
            },

            Op.LSR => {
                if (mode == .Accumulator) {
                    self.StatusRegister.C = (self.A & 0b0000_0001) == 1;
                    const res = self.A >> 1;
                    self.setZN(res);
                    self.A = res;
                } else {
                    const dst = self.addrOfInstruction(instr);
                    const byte = self.memRead(dst);
                    self.StatusRegister.C = (byte & 0b0000_0001) == 1;
                    const res = byte >> 1;
                    self.setZN(res);
                    // Peculiar behavior of R-M-W (Read modify write) instructions.
                    // The value is written as-is first, and then the modified value is written.
                    self.memWrite(dst, byte);
                    self.memWrite(dst, res);
                }
            },

            Op.NOP => {},

            Op.ORA => {
                const byte = self.operand(instr);
                const result = self.A | byte;
                self.A = result;
                self.setZN(result);
            },

            Op.PHA => {
                // the stack starts at 0x100, and grows downwards.
                const addr = @addWithOverflow(0x100, @as(u16, self.S))[0];
                self.memWrite(addr, self.A);
                // decrement the stack pointer.
                self.S = @subWithOverflow(self.S, 1)[0];
            },

            Op.PHP => {
                var status_reg = self.StatusRegister;
                status_reg.B = true; // pushed by non-interrupt instr
                status_reg._ = true; // always pushed as 1 no matter what.
                self.push(@bitCast(status_reg));
            },

            Op.PLA => {
                self.A = self.pop();
                self.setZN(self.A);
            },

            Op.PLP => {
                self.StatusRegister = @bitCast(self.pop());
                self.StatusRegister._ = true;
                self.StatusRegister.B = false;
            },

            Op.ROL => {
                if (mode == .Accumulator) {
                    self.A = self.rol(self.A);
                } else {
                    const dst = self.addrOfInstruction(instr);
                    const byte = self.memRead(dst);
                    const res = self.rol(byte);
                    // Peculiar behavior of R-M-W (Read modify write) instructions.
                    // The value is written as-is first, and then the modified value is written.
                    self.memWrite(dst, byte);
                    self.memWrite(dst, res);
                }
            },

            Op.ROR => {
                if (mode == .Accumulator) {
                    self.A = self.ror(self.A);
                } else {
                    const dst = self.addrOfInstruction(instr);
                    const byte = self.memRead(dst);
                    const res = self.ror(byte);
                    // Peculiar behavior of R-M-W (Read modify write) instructions.
                    // The value is written as-is first, and then the modified value is written.
                    self.memWrite(dst, byte);
                    self.memWrite(dst, res);
                }
            },

            Op.RTI => {
                self.StatusRegister = @bitCast(self.pop());
                self.StatusRegister._ = true;
                self.StatusRegister.B = false;
                const lo: u16 = self.pop();
                const hi: u16 = self.pop();
                self.PC = (hi << 8) | lo;
            },

            Op.RTS => {
                const lo: u16 = self.pop();
                const hi: u16 = self.pop();
                self.PC = (hi << 8) | lo;
                self.incPC();
            },

            Op.SEC => self.StatusRegister.C = true,
            Op.SED => self.StatusRegister.D = true,
            Op.SEI => self.StatusRegister.I = true,

            Op.STA => {
                const dst = self.addrOfInstruction(instr);
                self.memWrite(dst, self.A);
            },

            Op.STX => {
                const dst = self.addrOfInstruction(instr);
                self.memWrite(dst, self.X);
            },

            Op.STY => {
                const dst = self.addrOfInstruction(instr);
                self.memWrite(dst, self.Y);
            },

            Op.TAX => {
                self.X = self.A;
                self.setZN(self.X);
            },

            Op.TAY => {
                self.Y = self.A;
                self.setZN(self.Y);
            },

            Op.TSX => {
                self.X = self.S;
                self.setZN(self.X);
            },

            Op.TXA => {
                self.A = self.X;
                self.setZN(self.A);
            },

            Op.TXS => {
                self.S = self.X;
            },

            Op.TYA => {
                self.A = self.Y;
                self.setZN(self.A);
            },

            else => {
                return NESError.NotImplemented;
            },
        }
    }

    /// Service an interrupt request
    fn triggerInterrupt(self: *Self, handler_addr: u16) void {
        self.push(@truncate(self.PC >> 8)); // push PCHigh
        self.push(@truncate(self.PC)); // push PCLow

        var flags = self.StatusRegister;
        flags.B = false;
        self.push(@bitCast(flags)); // push status

        const handler_lo: u16 = self.memRead(handler_addr);
        const handler_hi: u16 = self.memRead(handler_addr + 1);
        self.PC = (handler_hi << 8) | handler_lo;
        self.StatusRegister.I = true;
    }

    /// Fetch and decode the next instruction.
    pub fn nextInstruction(self: *Self) *const Instruction {
        const op = self.nextOp();
        return opcode.decodeInstruction(op);
    }

    /// Tick the CPU by one clock cycle.
    pub fn tick(self: *Self) !void {
        if (self.cycles_to_wait > 0) {
            self.cycles_to_wait -= 1;
            return;
        }

        try self.exec(self.currentInstr);

        // If there is an NMI waiting to be serviced,
        // handle that first.
        switch (self.interrupt_pending) {
            .nmi => self.triggerInterrupt(NmiHandlerAddr), // 0xfffa/0xfffb
            .irq => self.triggerInterrupt(IrqHandlerAddr), // 0xfffe/0xffff
            else => {},
        }
        self.interrupt_pending = .none;

        self.currentInstr = self.nextInstruction();
        // -1 because of CPU cycle used to decode the instruction.
        self.cycles_to_wait = self.currentInstr[2] - 1;
    }

    // Run the CPU, assuming that the program counter has been
    // set to the correct location, and an instruction has been fetched.
    inline fn run(self: *Self) !void {
        while (true) {
            try self.tick();
        }
    }

    pub fn reset(self: *Self) void {
        const lo: u16 = self.memRead(0xFFFC);
        const hi: u16 = self.memRead(0xFFFD);
        self.PC = (hi << 8) | lo;

        self.StatusRegister._ = true;
        self.StatusRegister.I = true;
        self.cycles_to_wait = 6;
    }

    pub fn powerOn(self: *Self) void {
        // call the reset interrupt handler.
        // set all status flags to 0 (except the _ flag)
        self.StatusRegister = @bitCast(@as(u8, 0));
        self.reset();

        // Fetch the first instruction from the reset IRQ Handler.
        self.currentInstr = self.nextInstruction();
        self.cycles_to_wait += self.currentInstr[2];
    }

    /// Using `initial_state` as the initial state of the CPU, execute exactly one instruction (at PC),
    /// and return the final state of the CPU.
    pub fn runFromState(self: *Self, initial_state: *const CPUState) !CPUState {
        self.PC = initial_state.pc;
        self.S = initial_state.s;
        self.A = initial_state.a;
        self.X = initial_state.x;
        self.Y = initial_state.y;
        self.StatusRegister = @bitCast(initial_state.p);

        for (initial_state.ram) |*entry| {
            const addr = entry[0];
            const byte = entry[1];
            self.memWrite(addr, byte);
        }

        try self.exec(self.nextInstruction());

        var final_ram = try self.allocator.alloc(struct { u16, u8 }, initial_state.ram.len);

        for (0..initial_state.ram.len) |i| {
            const entry = &initial_state.ram[i];
            const addr = entry[0];
            assert(i < final_ram.len);
            final_ram[i] = .{ entry[0], self.memRead(addr) };
        }

        return .{
            .pc = self.PC,
            .s = self.S,
            .a = self.A,
            .x = self.X,
            .y = self.Y,
            .p = @bitCast(self.StatusRegister),
            .ram = final_ram,
        };
    }
};

// Tests For the 6502 CPU

const T = std.testing;

test "Status Register" {
    try T.expectEqual(1, @sizeOf(StatusRegister));
    try T.expectEqual(8, @bitSizeOf(StatusRegister));
}

test "CPU:init" {
    var tbus = TestBus.new();
    var cpu = CPU.init(T.allocator, &tbus.bus);

    for (0..0x800) |byte| {
        try T.expectEqual(@as(u8, 0), cpu.memRead(@truncate(byte)));
    }
}

test "CPU:nextOp" {
    var tbus = TestBus.new();
    var cpu = CPU.init(T.allocator, &tbus.bus);
    const op: u8 = 0x42;
    tbus.mem[0] = op;
    cpu.PC = 0;

    try T.expectEqual(op, cpu.nextOp());
    try T.expectEqual(@as(u16, 1), cpu.PC);
}

// Tests below are taken from: https://github.com/TomHarte/ProcessorTests/tree/main/nes6502
// The files are in `tests/nes-6502-tests/` directory.
const InstrTest = struct {
    name: []const u8,
    initial: CPUState,
    final: CPUState,
};

fn parseCPUTestCase(allocator: Allocator, testcase_str: []const u8) !std.json.Parsed([]InstrTest) {
    const parsed = try std.json.parseFromSlice(
        []InstrTest,
        allocator,
        testcase_str,
        .{ .ignore_unknown_fields = true },
    );
    return parsed;
}

fn runTestsForInstruction(instr_hex: []const u8) !void {
    const instr_file = try std.mem.concat(
        T.allocator,
        u8,
        &[_][]const u8{ instr_hex, ".json" },
    );
    defer T.allocator.free(instr_file);

    const file_path = try std.fs.path.join(
        T.allocator,
        &[_][]const u8{
            "src",
            "tests",
            "nes-6502-tests",
            instr_file,
        },
    );
    defer T.allocator.free(file_path);

    const contents = try std.fs.cwd().readFileAlloc(T.allocator, file_path, std.math.maxInt(usize));
    defer T.allocator.free(contents);

    var parsed = try parseCPUTestCase(T.allocator, contents);
    defer parsed.deinit();

    for (0..parsed.value.len) |i| {
        if (runTestCase(&parsed.value[i])) |_| {} else |err| {
            std.debug.print("Failed to run test case {d} for instruction {s}\n", .{ i, instr_hex });
            return err;
        }
    }
}

fn runTestCase(test_case: *const InstrTest) !void {
    var tbus = TestBus.new();
    var cpu = CPU.init(T.allocator, &tbus.bus);
    const received = try cpu.runFromState(&test_case.initial);
    defer T.allocator.free(received.ram);
    const expected = &test_case.final;

    try T.expectEqual(expected.pc, received.pc);
    try T.expectEqual(expected.s, received.s);
    try T.expectEqual(expected.a, received.a);
    try T.expectEqual(expected.x, received.x);
    try T.expectEqual(expected.y, received.y);
    try T.expectEqual(expected.p, received.p);
    for (expected.ram) |*cell| {
        const addr = cell[0];
        const expected_byte = cell[1];
        const received_byte = cpu.memRead(addr);
        if (expected_byte != received_byte) {
            std.debug.print("Expected: {d}, Received: {d} at address {d}\n", .{ expected_byte, received_byte, addr });
            return error.TestExpectedEqual;
        }
    }
}

test "ADC" {
    try runTestsForInstruction("69");
    try runTestsForInstruction("65");
    try runTestsForInstruction("75");
    try runTestsForInstruction("6d");
    try runTestsForInstruction("7d");
    try runTestsForInstruction("79");
    try runTestsForInstruction("61");
    try runTestsForInstruction("71");
}

test "SBC" {
    try runTestsForInstruction("e9");
    try runTestsForInstruction("e5");
    try runTestsForInstruction("f5");
    try runTestsForInstruction("ed");
    try runTestsForInstruction("fd");
    try runTestsForInstruction("f9");
    try runTestsForInstruction("e1");
    try runTestsForInstruction("f1");
}

test "JMP, JSR" {
    try runTestsForInstruction("4c");
    try runTestsForInstruction("6c");

    try runTestsForInstruction("20");
}

test "BRK" {
    try runTestsForInstruction("00");
}

test "AND" {
    try runTestsForInstruction("29");
    try runTestsForInstruction("25");
    try runTestsForInstruction("35");
    try runTestsForInstruction("2d");
    try runTestsForInstruction("3d");
    try runTestsForInstruction("39");
    try runTestsForInstruction("21");
    try runTestsForInstruction("31");
}

test "ASL" {
    try runTestsForInstruction("0a");
    try runTestsForInstruction("06");
    try runTestsForInstruction("16");
    try runTestsForInstruction("0e");
    try runTestsForInstruction("1e");
}

test "BCC, BCS, BEQ" {
    try runTestsForInstruction("90");
    try runTestsForInstruction("b0");
    try runTestsForInstruction("f0");
}

test "BIT" {
    try runTestsForInstruction("24");
    try runTestsForInstruction("2c");
}

test "BMI, BNE, BPL" {
    try runTestsForInstruction("30");
    try runTestsForInstruction("d0");
    try runTestsForInstruction("10");
}

test "BVC, BVS" {
    try runTestsForInstruction("50");
    try runTestsForInstruction("70");
}

test "CLC, CLD, CLI, CLV" {
    try runTestsForInstruction("18");
    try runTestsForInstruction("d8");
    try runTestsForInstruction("58");
    try runTestsForInstruction("b8");
}

test "CMP" {
    try runTestsForInstruction("c9");
    try runTestsForInstruction("c5");
    try runTestsForInstruction("d5");
    try runTestsForInstruction("cd");
    try runTestsForInstruction("dd");
    try runTestsForInstruction("d9");
    try runTestsForInstruction("c1");
    try runTestsForInstruction("d1");
}

test "CPX" {
    try runTestsForInstruction("e0");
    try runTestsForInstruction("e4");
    try runTestsForInstruction("ec");
}

test "CPY" {
    try runTestsForInstruction("c0");
    try runTestsForInstruction("c4");
    try runTestsForInstruction("cc");
}

test "DEC" {
    try runTestsForInstruction("c6");
    try runTestsForInstruction("d6");
    try runTestsForInstruction("ce");
    try runTestsForInstruction("de");
}

test "DEX, DEY" {
    try runTestsForInstruction("ca");
    try runTestsForInstruction("88");
}

test "EOR" {
    try runTestsForInstruction("49");
    try runTestsForInstruction("45");
    try runTestsForInstruction("55");
    try runTestsForInstruction("4d");
    try runTestsForInstruction("5d");
    try runTestsForInstruction("59");
    try runTestsForInstruction("41");
    try runTestsForInstruction("51");
}

test "INC" {
    try runTestsForInstruction("e6");
    try runTestsForInstruction("f6");
    try runTestsForInstruction("ee");
    try runTestsForInstruction("fe");
}

test "INX, INY" {
    try runTestsForInstruction("e8");
    try runTestsForInstruction("c8");
}

test "RTI, RTS" {
    try runTestsForInstruction("40");
    try runTestsForInstruction("60");
}

test "SEC, SED, SEI" {
    try runTestsForInstruction("38");
    try runTestsForInstruction("f8");
    try runTestsForInstruction("78");
}

test "STA, STX, STY" {
    // STA
    try runTestsForInstruction("85");
    try runTestsForInstruction("95");
    try runTestsForInstruction("8d");
    try runTestsForInstruction("9d");
    try runTestsForInstruction("99");
    try runTestsForInstruction("81");
    try runTestsForInstruction("91");

    // STX
    try runTestsForInstruction("86");
    try runTestsForInstruction("96");
    try runTestsForInstruction("8e");

    // STY
    try runTestsForInstruction("84");
    try runTestsForInstruction("94");
    try runTestsForInstruction("8c");
}

test "TAX, TAY, TSX, TXA, TXS, TYA" {
    try runTestsForInstruction("aa");
    try runTestsForInstruction("a8");
    try runTestsForInstruction("ba");
    try runTestsForInstruction("8a");
    try runTestsForInstruction("9a");
    try runTestsForInstruction("98");
}

test "ROL, ROR" {
    // ROL
    try runTestsForInstruction("2a");
    try runTestsForInstruction("26");
    try runTestsForInstruction("36");
    try runTestsForInstruction("2e");
    try runTestsForInstruction("3e");

    // ROR
    try runTestsForInstruction("6a");
    try runTestsForInstruction("66");
    try runTestsForInstruction("76");
    try runTestsForInstruction("6e");
    try runTestsForInstruction("7e");
}

test "LDA" {
    // LDA
    try runTestsForInstruction("a9");
    try runTestsForInstruction("a5");
    try runTestsForInstruction("b5");
    try runTestsForInstruction("ad");
    try runTestsForInstruction("bd");
    try runTestsForInstruction("b9");
    try runTestsForInstruction("a1");
    try runTestsForInstruction("b1");
}

test "LDX" {
    try runTestsForInstruction("a2");
    try runTestsForInstruction("a6");
    try runTestsForInstruction("b6");
    try runTestsForInstruction("ae");
    try runTestsForInstruction("be");
}

test "LDY" {
    try runTestsForInstruction("a0");
    try runTestsForInstruction("a4");
    try runTestsForInstruction("b4");
    try runTestsForInstruction("ac");
    try runTestsForInstruction("bc");
}

test "LSR" {
    try runTestsForInstruction("4a");
    try runTestsForInstruction("46");
    try runTestsForInstruction("56");
    try runTestsForInstruction("4e");
    try runTestsForInstruction("5e");
}

test "ORA" {
    try runTestsForInstruction("09");
    try runTestsForInstruction("05");
    try runTestsForInstruction("15");
    try runTestsForInstruction("0d");
    try runTestsForInstruction("19");
    try runTestsForInstruction("01");
    try runTestsForInstruction("1d");
    try runTestsForInstruction("19");
    try runTestsForInstruction("01");
    try runTestsForInstruction("11");
}

test "Stack instructions" {
    try runTestsForInstruction("48");
    try runTestsForInstruction("08");
    try runTestsForInstruction("68");
    try runTestsForInstruction("28");
}
