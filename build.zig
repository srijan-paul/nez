const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "nez",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    if (target.result.isDarwin() and !target.query.isNative()) {
        if (b.sysroot == null) {
            @panic(" Pass --sysroot <path/to/macOS/SDK>");
        }
        exe.addSystemIncludePath(.{ .path = b.pathJoin(&.{ b.sysroot.?, "/usr/include" }) });
        exe.addLibraryPath(.{ .path = b.pathJoin(&.{ b.sysroot.?, "/usr/lib" }) });
        exe.addFrameworkPath(.{ .path = b.pathJoin(&.{ b.sysroot.?, "/System/Library/Frameworks" }) });
    }

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.strip = b.option(
        bool,
        "strip",
        "Strip debug info to reduce binary size, defaults to false",
    ) orelse false;
    exe.linkLibrary(raylib_dep.artifact("raylib"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
