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

    /// set the `N` flag if the 8th bit of `value` is 1.
    fn setFlagN(self: *Self, value: u16) void {
        self.StatusRegister.N = value & 0b1000_0000 != 0;
    }

    /// set the `C` flag if `value` is greater than 0xFF (u8 max).
    fn setFlagC(self: *Self, value: u16) void {
        self.StatusRegister.C = value > std.math.maxInt(Byte);
    }

    /// Execute a single instruction.
    pub fn exec(self: *Self, instr: Instruction) !void {
        var op = instr[0];
        switch (op) {
            Op.ADC => {
                var byte: u16 = self.operand(instr);
                var carry: u16 = if (self.StatusRegister.C) 1 else 0;
                var sum: u16 = self.A + byte + carry;

                self.setFlagZ(sum);
                self.setFlagN(sum);
                self.setFlagC(sum);
                // TODO: set flag V, and add extra cycles based on mode.

                // drop the MSBs
                self.A = @truncate(sum);
            },

            Op.AND => {
                var byte = self.operand(instr);
                var result = self.A & byte;
                self.A = result;
                self.setFlagZ(result);
                self.setFlagN(result);
            },

            Op.ASL => {
                var byte: u16 = self.operand(instr);
                var result: u16 = byte << 1;
                self.setFlagZ(result);
                self.setFlagN(result);
                self.setFlagC(result);
                self.A = @truncate(result);
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
                var addr = @addWithOverflow(0x100, @as(u16, self.S))[0];
                self.memWrite(addr, self.A);
                // decrement the stack pointer.
                self.S = @subWithOverflow(self.S, 1)[0];
            },

            else => {
                return NESError.NotImplemented;
            },
        }
    }

    /// Tick the CPU by one clock cycle.
    pub fn step(self: *Self) !void {
        if (self.cycles_to_wait > 0) {
            self.cycles_to_wait -= 1;
            return;
        }

        var op = self.nextOp();
        var instr = opcode.decodeInstruction(op);
        self.cycles_to_wait = instr[2];
        return self.exec(instr);
    }

    /// Executes the program present in the `program` buffer.
    /// The program is loaded onto the first page of the RAM,
    /// and the program counter is set to 0.
    pub fn loadAndRun(self: *Self, program: []const u8) !void {
        var num_instrs = program.len;
        for (0..num_instrs) |i| {
            self.memWrite(@truncate(i), program[i]);
        }
        self.PC = 0;

        while (self.PC < num_instrs) {
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

        try self.step();

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

test "CPU: loadAndRun (LDA #$42)" {
    var tbus = TestBus.new();
    var cpu = CPU.init(T.allocator, &tbus.bus);

    // LDA #$42
    var program = [_]u8{ 0xA9, 0x42 };

    try cpu.loadAndRun(&program);
    try T.expectEqual(@as(u8, 0x42), cpu.A);
    try T.expectEqual(@as(u16, 2), cpu.PC);
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
        try T.expectEqual(expected_byte, received_byte);
    }
}

test "lda (71),Y" {
    var init_ram = [_]CPUState.Cell{
        .{ 9023, 177 },
        .{ 9024, 113 },
        .{ 9025, 139 },
        .{ 113, 169 },
        .{ 114, 89 },
        .{ 22867, 214 },
        .{ 23123, 37 },
    };

    var final_ram = [_]CPUState.Cell{
        .{ 9023, 177 },
        .{ 9024, 113 },
        .{ 9025, 139 },
        .{ 113, 169 },
        .{ 114, 89 },
        .{ 22867, 214 },
        .{ 23123, 37 },
    };

    const name: []const u8 = "lda (71),Y";

    var test_case = InstrTest{
        .name = name,
        .initial = .{ .pc = 9023, .s = 240, .a = 47, .x = 162, .y = 170, .p = 170, .ram = &init_ram },
        .final = .{
            .pc = 9025,
            .s = 240,
            .a = 37,
            .x = 162,
            .y = 170,
            .p = 40,
            .ram = &final_ram,
        },
    };
    try runTestCase(&test_case);
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

test "PHA" {
    try runTestsForInstruction("48");
}
