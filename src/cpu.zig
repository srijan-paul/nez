const std = @import("std");
const opcode = @import("opcode.zig");
const cart = @import("cart.zig");
const util = @import("util.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const AddrMode = opcode.AddrMode;
const Op = opcode.Op;
const Instruction = opcode.Instruction;
const NESError = util.NESError;

pub const Register = u8;
pub const Byte = u8;

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

// State of the CPU used for point-in-time tests.
pub const CPUState = struct {
    pc: u16,
    s: u8,
    a: u8,
    x: u8,
    y: u8,
    p: u8,
    ram: []struct { u16, u8 },
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

    P: Register = 0,

    // The program counter is 16 bit, since it holds an address.
    PC: u16 = 0,

    StatusRegister: StatusRegister = .{},

    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    fn read(self: *Self, addr: u16) !Byte {
        // RAM is mirrored every 0x800 bytes.
        // ref: https://www.nesdev.org/wiki/CPU_memory_map
        if (addr <= 0x1FFF) {
            var index = addr % CPU.WRamSize;
            return self.RAM[index];
        }

        // TODO: PPU: doesn't exist yet :)
        if (addr >= 0x2000 and addr <= 0x3FFF) {
            return NESError.NotImplemented;
        }

        // TODO: APU and I/O registers.
        if (addr >= 0x4000 and addr <= 0x4017) {
            return NESError.NotImplemented;
        }

        // These addresses are unused by most carts.
        if (addr >= 0x4018 and addr <= 0x401F) {
            return NESError.NotImplemented;
        }

        assert(addr >= 0x4020);

        // All addresses above 0x4020 are mapped to cartridge space.
    }

    pub fn memRead(self: *Self, addr: u16) Byte {
        // TODO: implement the whole memory map: https://www.nesdev.org/wiki/CPU_memory_map
        return self.RAM[addr];
    }

    // fetch the next byte to execute.
    fn nextOp(self: *Self) Byte {
        var byte = self.read(self.PC);
        self.PC += 1;
        return byte;
    }

    /// Fetch the next two bytes from the program counter,
    /// and stitch them together to get a 16 bit address from memory.
    fn getAddr16(self: *Self) u16 {
        var low: u16 = self.nextOp();
        var high: u16 = self.nextOp();
        return low | (high << 8);
    }

    /// Depending on the addressing mode of the instruction `instr`,
    /// get a byte of the data from memory.
    fn readInstrOperand(self: *Self, instr: Instruction) Byte {
        var addr_mode = instr[1];
        switch (addr_mode) {
            .Immediate => {
                return self.nextOp();
            },

            .Accumulator => {
                return self.A;
            },

            .Absolute => {
                var addr = self.getAddr16();
                return self.memRead(addr);
            },

            .AbsoluteX => {
                var addr = self.getAddr16();
                addr += self.X;
                return self.memRead(addr);
            },

            .AbsoluteY => {
                var addr = self.getAddr16();
                addr += self.Y;
                return self.memRead(addr);
            },

            .ZeroPage => {
                var addr = self.nextOp();
                return self.memRead(addr);
            },

            .ZeroPageX => {
                var addr: u16 = self.nextOp();
                addr += self.X;
                // zero page addressed reads cannot
                // cross page boundaries.
                addr = addr % CPU.PageSize;
                return self.memRead(addr);
            },

            .ZeroPageY => {
                var addr: u16 = self.nextOp();
                addr += self.Y;
                // zero page addressed reads cannot
                // cross page boundaries.
                addr = addr % CPU.PageSize;
                return self.memRead(addr);
            },

            .Relative => {
                var byte = self.nextOp();
                return byte;
            },

            .Indirect => {
                var addr = self.getAddr16();
                var low: u16 = self.memRead(addr);
                var high: u16 = self.memRead(addr + 1);
                var final_addr = low | (high << 8);
                return self.memRead(final_addr);
            },

            // TODO: support zero page wrap around.
            .IndirectX => {
                var addr = self.nextOp() + self.X;
                var low: u16 = self.memRead(addr);
                var high: u16 = self.memRead(addr + 1);
                var final_addr = low | (high << 8);
                return self.memRead(final_addr);
            },

            // TODO: support zero page wrap around.
            .IndirectY => {
                var addr = self.nextOp();
                var low: u16 = self.memRead(addr);
                var high: u16 = self.memRead(addr + 1);
                var final_addr = (low | (high << 8)) + self.Y;
                return self.memRead(final_addr);
            },

            .Implicit => unreachable,
            .Invalid => unreachable,
        }
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
                var byte: u16 = self.readInstrOperand(instr);
                var carry: u16 = self.StatusRegister.C;
                var sum: u16 = self.A + byte + carry;

                self.setFlagZ(sum);
                self.setFlagN(sum);
                self.setFlagC(sum);
                // TODO: set flag V, and add extra cycles based on mode.

                // drop the MSBs
                self.A = @truncate(sum);
            },

            Op.AND => {
                var byte = self.readInstrOperand(instr);
                var result = self.A & byte;
                self.A = result;
                self.setFlagZ(result);
                self.setFlagN(result);
            },

            Op.ASL => {
                var byte: u16 = self.readInstrOperand(instr);
                var result: u16 = byte << 1;
                self.setFlagZ(result);
                self.setFlagN(result);
                self.setFlagC(result);
                self.A = @truncate(result);
            },

            Op.LDA => {
                var byte = self.readInstrOperand(instr);
                self.A = byte;
                self.setFlagZ(byte);
                self.setFlagN(byte);
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
    pub fn load_and_run(self: *Self, program: []const u8) !void {
        var num_instrs = @min(program.len, self.RAM.len);
        for (0..num_instrs) |i| {
            self.RAM[i] = program[i];
        }
        self.PC = 0;

        while (self.PC < num_instrs) {
            try self.step();
        }
    }

    /// Using `initial_state` as the initial state of the CPU, execute exactly one instruction (at PC),
    /// and return the final state of the CPU.
    pub fn runFromState(self: *Self, initial_state: *CPUState) CPUState {
        self.PC = initial_state.pc;
        self.S = initial_state.s;
        self.A = initial_state.a;
        self.X = initial_state.x;
        self.Y = initial_state.y;
        self.P = initial_state.p;
        self.StatusRegister = @bitCast(initial_state.p);

        for (initial_state.ram) |*entry| {
            var addr = entry[0];
            var byte = entry[1];
            self.RAM[addr] = byte;
        }

        try self.step();

        var final_ram = self.allocator.alloc(struct { u16, u8 }, self.RAM.len);
        defer self.allocator.free(final_ram);

        for (0..initial_state.ram.len) |i| {
            var entry = &initial_state.ram[i];
            final_ram[i] = .{ entry[0], self.RAM[i] };
        }

        return .{
            .pc = self.PC,
            .s = self.S,
            .a = self.A,
            .x = self.X,
            .y = self.Y,
            .p = self.P,
            // This is only ever used for testing,
            // so I don't mind this copy.
            .ram = *final_ram,
        };
    }
};

const T = std.testing;

test "Status Register" {
    try T.expectEqual(1, @sizeOf(StatusRegister));
    try T.expectEqual(8, @bitSizeOf(StatusRegister));
}

test "CPU:init" {
    var cpu = CPU.init(T.allocator);
    try T.expectEqual(cpu.RAM.len, 2048);

    for (cpu.RAM) |byte| {
        try T.expectEqual(@as(Byte, 0), byte);
    }
}

test "CPU:nextOp" {
    var cpu = CPU.init(T.allocator);
    var op: Byte = 0x42;
    cpu.RAM[0] = op;
    cpu.PC = 0;

    try T.expectEqual(op, cpu.nextOp());
    try T.expectEqual(@as(u16, 1), cpu.PC);
}

test "CPU: load_and_run (LDA #$42)" {
    var cpu = CPU.init(T.allocator);

    // LDA #$42
    var program = [_]u8{ 0xA9, 0x42 };

    try cpu.load_and_run(&program);
    try T.expectEqual(@as(u8, 0x42), cpu.A);
    try T.expectEqual(@as(u16, 2), cpu.PC);
}

// Tests below are taken from: https://github.com/TomHarte/ProcessorTests/tree/main/nes6502
// The files are in `tests/nes-6502-tests/` directory.
const InstrTest = struct {
    name: []u8,
    initial: CPUState,
    final: CPUState,
};

pub fn run_test(test_case: *InstrTest) !void {
    var cpu = CPU.init(T.allocator);
    var final = cpu.runFromState(&test_case.initial);
    try T.expectEqualDeep(test_case.final, final);
}

test "lda (71),Y" {
    var instr_test = .InstrTest{
        .name = "b1 71 8b",
        .initial = .{
            .pc = 9023,
            .s = 240,
            .a = 47,
            .x = 162,
            .y = 170,
            .p = 170,
            .ram = .{
                .{ 9023, 177 },
                .{ 9024, 113 },
                .{ 9025, 139 },
                .{ 113, 169 },
                .{ 114, 89 },
                .{ 22867, 214 },
                .{ 23123, 3 },
            },
        },
        .final = .{
            .pc = 9025,
            .s = 240,
            .a = 37,
            .x = 162,
            .y = 170,
            .p = 40,
            .ram = .{
                .{ 9023, 177 },
                .{ 9024, 113 },
                .{ 9025, 139 },
                .{ 113, 169 },
                .{ 114, 89 },
                .{ 22867, 214 },
                .{ 23123, 3 },
            },
        },
    };
    run_test(&instr_test);
}

fn parseCPUTestCase(testcase_str: []const u8, allocator: Allocator) !std.json.Parsed([]InstrTest) {
    const parsed = try std.json.parseFromSlice(
        []InstrTest,
        allocator,
        testcase_str,
        .{ .ignore_unknown_fields = true },
    );
    return parsed;
}
