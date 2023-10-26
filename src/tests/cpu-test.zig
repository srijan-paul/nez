const std = @import("std");
const cpu = @import("../cpu.zig");

const json = std.json;
const testing = std.testing;

const Allocator = std.mem.Allocator;

const CPUState = cpu.CPUState;

// A test case for a single instruction
const InstrTest = struct {
    name: []u8,
    initial: CPUState,
    final: CPUState,
};

const CPUTestCase = []InstrTest;

pub fn parseCPUTestCase(testcase_str: []const u8, allocator: Allocator) !json.Parsed([]InstrTest) {
    const parsed = try json.parseFromSlice(
        CPUTestCase,
        allocator,
        testcase_str,
        .{ .ignore_unknown_fields = true },
    );
    return parsed;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var dir = std.fs.cwd();
    var fd = try dir.openFile("src/tests/nes-6502-tests/a9.json", .{});

    var contents = try fd.readToEndAlloc(allocator, std.math.maxInt(usize));

    var testcases = try parseCPUTestCase(contents, allocator);
    defer testcases.deinit();
    std.debug.print("{d}\n", .{testcases.value.len});
}
