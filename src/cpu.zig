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
pub const Byte = u8;

pub const StatusRegister = packed struct {
    // Carry Flag
    C: bool = false,
    // Zero Flag
    Z: bool = false,
    // Interrupt Disable
    I: bool = false,
    D: bool = false,
    B: bool = false,
    // This status flag does nothing, and is always set to 1.
    // B-Flag. Not used by the user.
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

    // capacity of the RAM chip attached to the CPU in bytes
    // (called SRAM (S = static), or WRAM(W = work))
    pub const WRamSize = 0x800;
    RAM: [WRamSize]Byte = .{0} ** WRamSize,
    // number of cycles to cycles to wait
    // before executing the next instruction.
    cycles_to_wait: u8 = 0,

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

    allocator: Allocator,

    currentInstr: Instruction = .{ Op.Unknown, AddrMode.Invalid, 0 },

    pub fn init(allocator: Allocator, bus: *Bus) Self {
        return .{ .allocator = allocator, .bus = bus };
    }

    /// Read a byte of data from `addr` in memory.
    pub fn memRead(self: *Self, addr: u16) Byte {
        return self.bus.read(addr);
    }

    /// Write a byte of data to `addr` in memory.
    pub fn memWrite(self: *Self, addr: u16, byte: Byte) void {
        self.bus.write(addr, byte);
    }

    fn resolveAddr(self: *Self, addr: u16) *u8 {
        return self.bus.resolveAddr(addr);
    }

    fn incPC(self: *Self) void {
        self.PC = @addWithOverflow(self.PC, @as(u16, 1))[0];
    }

    // fetch the next byte to execute.
    fn nextOp(self: *Self) Byte {
        var byte = self.memRead(self.PC);
        self.incPC();
        return byte;
    }

    /// Fetch the next two bytes from the program counter,
    /// and stitch them together to get a 16 bit address from memory.
    fn getAddr16(self: *Self) u16 {
        var low: u16 = self.nextOp();
        var high: u16 = self.nextOp();
        return low | (high << 8);
    }

    fn operandPtr(self: *Self, instr: Instruction) *u8 {
        var addr_mode = instr[1];
        switch (addr_mode) {
            .Immediate => {
                var ptr = self.resolveAddr(self.PC);
                self.incPC();
                return ptr;
            },

            .Accumulator => {
                return &self.A;
            },

            .Absolute => {
                var addr = self.getAddr16();
                return self.resolveAddr(addr);
            },

            .AbsoluteX => {
                var addr = self.getAddr16();
                addr = @addWithOverflow(addr, self.X)[0];
                return self.resolveAddr(addr);
            },

            .AbsoluteY => {
                var addr = self.getAddr16();
                addr = @addWithOverflow(addr, self.Y)[0];
                return self.resolveAddr(addr);
            },

            .ZeroPage => {
                var addr = self.nextOp();
                return self.resolveAddr(addr);
            },

            .ZeroPageX => {
                var addr: u16 = self.nextOp();
                addr += self.X;
                // zero page addressed reads cannot
                // cross page boundaries.
                addr = addr % CPU.PageSize;
                return self.resolveAddr(addr);
            },

            .ZeroPageY => {
                var addr: u16 = self.nextOp();
                addr += self.Y;
                // zero page addressed reads cannot
                // cross page boundaries.
                addr = addr % CPU.PageSize;
                return self.resolveAddr(addr);
            },

            .Relative => {
                unreachable;
            },

            .Indirect => {
                var addr = self.getAddr16();
                var low: u16 = self.memRead(addr);
                var high: u16 = self.memRead(addr + 1);
                var final_addr = low | (high << 8);
                return self.resolveAddr(final_addr);
            },

            // TODO: support zero page wrap around.
            .IndirectX => {
                var addr: u8 = @truncate(self.nextOp() + @as(u16, self.X));
                var low: u16 = self.memRead(addr);
                var next_addr = @addWithOverflow(addr, 1)[0];
                var high: u16 = self.memRead(next_addr);
                var final_addr = low | (high << 8);
                return self.resolveAddr(final_addr);
            },

            // TODO: support zero page wrap around.
            .IndirectY => {
                var addr = self.nextOp();
                var low: u16 = self.memRead(addr);
                var high: u16 = self.memRead(@addWithOverflow(addr, 1)[0]);
                var final_addr = @addWithOverflow((low | (high << 8)), self.Y)[0];
                return self.resolveAddr(final_addr);
            },

            .Implicit => unreachable,
            .Invalid => unreachable,
        }
    }

    // TODO: rename to `readByte`?
    /// Depending on the addressing mode of the instruction `instr`,
    /// get a byte of the data from memory.
    fn operand(self: *Self, instr: Instruction) Byte {
        return self.operandPtr(instr).*;
    }

    /// set the Z flag if the lower 8 bits of `value` are all 0.
    fn setFlagZ(self: *Self, value: u16) void {
        self.StatusRegister.Z = value & 0xFF == 0;
    }

    /// set the `N` flag if the MSB of `value` is 1.
    fn setFlagN(self: *Self, value: u16) void {
        self.StatusRegister.N = value & 0b1000_0000 != 0;
    }

    // set the Z and N flags based on the lower 8 bits of `value`.
    fn setZN(self: *Self, value: u16) void {
        self.setFlagZ(value);
        self.setFlagN(value);
    }

    /// set the `C` flag if `value` is greater than 0xFF (u8 max).
    fn setC(self: *Self, value: u16) void {
        self.StatusRegister.C = value > std.math.maxInt(Byte);
    }

    /// Get the address pointed to the by the current stack pointer.
    fn stackAddr(self: *Self) u16 {
        return @addWithOverflow(0x100, @as(u16, self.S))[0];
    }

    /// Push `value` onto the stack, and decrement the stack pointer.
    fn push(self: *Self, value: u8) void {
        var addr = self.stackAddr();
        self.memWrite(addr, value);
        // decrement the stack pointer.
        self.S = @subWithOverflow(self.S, 1)[0];
    }

    /// Pops a value from the stack.
    fn pop(self: *Self) u8 {
        self.S = @addWithOverflow(self.S, 1)[0];
        var addr = self.stackAddr();
        return self.memRead(addr);
    }

    /// Perform a branch if `cond` is true.
    fn branchIf(self: *Self, cond: bool) void {
        // TODO: check for extra cycles when crossing pages.
        // and when branch is successful.
        if (cond) {
            // jump offset can be signed.
            // TODO: can this be refactored?
            var offset: i8 = @bitCast(self.nextOp());
            var old_pc: i32 = self.PC;
            var new_pc: u32 = @bitCast(old_pc + offset);
            self.PC = @truncate(new_pc);
        } else {
            self.incPC();
        }
    }

    /// Perform the `ADC` CPU operation on `arg`.
    fn adc(self: *Self, arg: Byte) void {
        var byte: u16 = arg;
        var carry: u16 = if (self.StatusRegister.C) 1 else 0;
        var sum: u16 = self.A + byte + carry;

        self.setZN(sum);
        self.setC(sum);
        self.StatusRegister.V = ((self.A ^ sum) & (byte ^ sum) & 0b1000_0000) != 0;

        self.A = @truncate(sum);
    }

    /// Execute a single instruction.
    pub fn exec(self: *Self, instr: Instruction) !void {
        var op = instr[0];
        switch (op) {
            Op.ADC => self.adc(self.operand(instr)),

            // SBC is equivalent to ADC(~arg).
            // Ref: http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html
            Op.SBC => self.adc(~self.operand(instr)),

            Op.AND => {
                var byte = self.operand(instr);
                var result = self.A & byte;
                self.A = result;
                self.setFlagZ(result);
                self.setFlagN(result);
            },

            Op.ASL => {
                var dst: *u8 = self.operandPtr(instr);
                var byte: u16 = dst.*;
                var res = byte << 1;
                self.setZN(res);
                self.setC(res);
                dst.* = @truncate(res);
            },

            Op.BIT => {
                var byte = self.operand(instr);
                var result = self.A & byte;
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
                self.push(@truncate(self.PC >> 8)); // high byte
                self.push(@truncate(self.PC)); // low byte

                // There is actual "B" flag in a physical 6502 CPU.
                // It is merely a bit that exists in the *flag byte*
                // that is pushed onto the stack.
                // When flags are restored (following an RTI), the
                // B bit is discarded.
                var flags = self.StatusRegister;
                flags.B = true;
                self.push(@bitCast(flags));

                var lo: u16 = self.memRead(0xFFFE);
                var hi: u16 = self.memRead(0xFFFF);
                self.PC = (hi << 8) | lo;
                self.StatusRegister.I = true;
                self.StatusRegister._ = true;
            },

            Op.CLC => self.StatusRegister.C = false,
            Op.CLD => self.StatusRegister.D = false,
            Op.CLI => self.StatusRegister.I = false,
            Op.CLV => self.StatusRegister.V = false,

            Op.CMP => {
                var byte: u8 = self.operand(instr);
                var result = @subWithOverflow(self.A, byte)[0];
                self.setZN(result);
                self.StatusRegister.C = self.A >= byte;
            },

            Op.CPX => {
                var byte: u8 = self.operand(instr);
                var result = @subWithOverflow(self.X, byte)[0];
                self.setZN(result);
                self.StatusRegister.C = self.X >= byte;
            },

            Op.CPY => {
                var byte: u8 = self.operand(instr);
                var result = @subWithOverflow(self.Y, byte)[0];
                self.setZN(result);
                self.StatusRegister.C = self.Y >= byte;
            },

            Op.DEC => {
                var dst = self.operandPtr(instr);
                var res = @subWithOverflow(dst.*, 1)[0];
                self.setZN(res);
                dst.* = res;
            },

            Op.DEX => {
                var res = @subWithOverflow(self.X, 1)[0];
                self.setZN(res);
                self.X = res;
            },

            Op.DEY => {
                var res = @subWithOverflow(self.Y, 1)[0];
                self.setZN(res);
                self.Y = res;
            },

            Op.EOR => {
                var byte = self.operand(instr);
                self.A = self.A ^ byte;
                self.setZN(self.A);
            },

            Op.INC => {
                var dst = self.operandPtr(instr);
                var res = @addWithOverflow(dst.*, 1)[0];
                self.setZN(res);
                dst.* = res;
            },

            Op.INX => {
                var res = @addWithOverflow(self.X, 1)[0];
                self.setZN(res);
                self.X = res;
            },

            Op.INY => {
                var res = @addWithOverflow(self.Y, 1)[0];
                self.setZN(res);
                self.Y = res;
            },

            Op.JMP => {
                if (instr[1] == AddrMode.Absolute) {
                    self.PC = self.getAddr16();
                } else {
                    assert(instr[1] == AddrMode.Indirect);
                    var addr_addr = self.getAddr16();
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
                var return_addr = @addWithOverflow(self.PC, @as(u16, 1))[0];
                self.push(@truncate(return_addr >> 8)); // high byte
                self.push(@truncate(return_addr)); // low byte
                self.PC = self.getAddr16();
            },

            Op.LDA => {
                var byte = self.operand(instr);
                self.A = byte;
                self.setFlagZ(byte);
                self.setFlagN(byte);
            },

            Op.LDX => {
                var byte = self.operand(instr);
                self.X = byte;
                self.setFlagZ(byte);
                self.setFlagN(byte);
            },

            Op.LDY => {
                var byte = self.operand(instr);
                self.Y = byte;
                self.setFlagZ(byte);
                self.setFlagN(byte);
            },

            Op.LSR => {
                var dst = self.operandPtr(instr);
                self.StatusRegister.C = (dst.* & 0b0000_0001) == 1;
                var res = dst.* >> 1;
                dst.* = res;
                self.setFlagZ(res);
                self.setFlagN(res);
            },

            Op.NOP => {},

            Op.ORA => {
                var byte = self.operand(instr);
                var result = self.A | byte;
                self.A = result;
                self.setFlagZ(result);
                self.setFlagN(result);
            },

            Op.PHA => {
                // the stack starts at 0x100, and grows downwards.
                var addr = @addWithOverflow(0x100, @as(u16, self.S))[0];
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
                self.setFlagZ(self.A);
                self.setFlagN(self.A);
            },

            Op.PLP => {
                self.StatusRegister = @bitCast(self.pop());
                self.StatusRegister._ = true;
                self.StatusRegister.B = false;
            },

            Op.ROL => {
                var dst = self.operandPtr(instr);
                var old_carry: u8 = if (self.StatusRegister.C) 1 else 0;

                var shlResult = @shlWithOverflow(dst.*, @as(u8, 1));

                // set the new bit-0 to the old carry.
                var res = shlResult[0] | old_carry;
                self.setFlagZ(res);
                self.setFlagN(res);

                // the bit that was shifted out when performing a <<
                var shifted_bit = shlResult[1];
                self.StatusRegister.C = shifted_bit == 1;
                dst.* = res;
            },

            Op.ROR => {
                var dst = self.operandPtr(instr);
                var old_carry: u8 = if (self.StatusRegister.C) 1 else 0;

                var old_b0 = dst.* & 0b0000_0001; // old 0th bit
                var res = dst.* >> 1;
                // set the new MSB to the old carry.
                res = res | (old_carry << 7);

                self.setFlagZ(res);
                self.setFlagN(res);

                // the bit that was shifted out when performing a >>
                self.StatusRegister.C = old_b0 == 1;
                dst.* = res;
            },

            Op.RTI => {
                self.StatusRegister = @bitCast(self.pop());
                self.StatusRegister._ = true;
                self.StatusRegister.B = false;
                var lo: u16 = self.pop();
                var hi: u16 = self.pop();
                self.PC = (hi << 8) | lo;
            },

            Op.RTS => {
                var lo: u16 = self.pop();
                var hi: u16 = self.pop();
                self.PC = (hi << 8) | lo;
                self.incPC();
            },

            Op.SEC => self.StatusRegister.C = true,
            Op.SED => self.StatusRegister.D = true,
            Op.SEI => self.StatusRegister.I = true,

            Op.STA => {
                var dst = self.operandPtr(instr);
                dst.* = self.A;
            },

            Op.STX => {
                var dst = self.operandPtr(instr);
                dst.* = self.X;
            },

            Op.STY => {
                var dst = self.operandPtr(instr);
                dst.* = self.Y;
            },

            Op.TAX => {
                self.X = self.A;
                self.setFlagZ(self.X);
                self.setFlagN(self.X);
            },

            Op.TAY => {
                self.Y = self.A;
                self.setFlagZ(self.Y);
                self.setFlagN(self.Y);
            },

            Op.TSX => {
                self.X = self.S;
                self.setFlagZ(self.X);
                self.setFlagN(self.X);
            },

            Op.TXA => {
                self.A = self.X;
                self.setFlagZ(self.A);
                self.setFlagN(self.A);
            },

            Op.TXS => {
                self.S = self.X;
            },

            Op.TYA => {
                self.A = self.Y;
                self.setFlagZ(self.A);
                self.setFlagN(self.A);
            },

            else => {
                return NESError.NotImplemented;
            },
        }
    }

    /// Fetch and decode the next instruction.
    pub fn nextInstruction(self: *Self) Instruction {
        var op = self.nextOp();
        return opcode.decodeInstruction(op);
    }

    /// Tick the CPU by one clock cycle.
    pub fn step(self: *Self) !void {
        if (self.cycles_to_wait > 0) {
            self.cycles_to_wait -= 1;
            return;
        }

        var result = self.exec(self.currentInstr);
        self.currentInstr = self.nextInstruction();

        // subtract one because of CPU cycle
        // used to decode the instruction.
        self.cycles_to_wait = self.currentInstr[2] - 1;
        return result;
    }

    // Run the CPU, assuming that the program counter has been
    // set to the correct location.
    pub fn run(self: *Self) !void {
        self.currentInstr = self.nextInstruction();
        while (true) {
            try self.step();
        }
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
            var addr = entry[0];
            var byte = entry[1];
            self.memWrite(addr, byte);
        }

        try self.exec(self.nextInstruction());

        var final_ram = try self.allocator.alloc(struct { u16, u8 }, initial_state.ram.len);

        for (0..initial_state.ram.len) |i| {
            var entry = &initial_state.ram[i];
            var addr = entry[0];
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
    var op: Byte = 0x42;
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

pub fn runTestsForInstruction(instr_hex: []const u8) !void {
    var instr_file = try std.mem.concat(
        T.allocator,
        u8,
        &[_][]const u8{ instr_hex, ".json" },
    );
    defer T.allocator.free(instr_file);

    var file_path = try std.fs.path.join(
        T.allocator,
        &[_][]const u8{
            "src",
            "tests",
            "nes-6502-tests",
            instr_file,
        },
    );
    defer T.allocator.free(file_path);

    var contents = try std.fs.cwd().readFileAlloc(T.allocator, file_path, std.math.maxInt(usize));
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

pub fn runTestCase(test_case: *const InstrTest) !void {
    var tbus = TestBus.new();
    var cpu = CPU.init(T.allocator, &tbus.bus);
    var received = try cpu.runFromState(&test_case.initial);
    defer T.allocator.free(received.ram);
    var expected = &test_case.final;

    try T.expectEqual(expected.pc, received.pc);
    try T.expectEqual(expected.s, received.s);
    try T.expectEqual(expected.a, received.a);
    try T.expectEqual(expected.x, received.x);
    try T.expectEqual(expected.y, received.y);
    try T.expectEqual(expected.p, received.p);
    for (expected.ram) |*cell| {
        var addr = cell[0];
        var expected_byte = cell[1];
        var received_byte = cpu.memRead(addr);
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
