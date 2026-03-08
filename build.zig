const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "nez",
        .root_module = exe_mod,
    });

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .platform = .glfw,
        // Workaround: raylib 6.0's build.zig config_h_flags parser strips values
        // from defines, so SUPPORT_CUSTOM_FRAME_CONTROL=0 becomes =1, which
        // disables SwapScreenBuffer()/PollInputEvents() in EndDrawing().
        .config = "-DSUPPORT_CUSTOM_FRAME_CONTROL=0",
    });

    const raylib = raylib_dep.artifact("raylib");
    exe_mod.linkLibrary(raylib);

    // On macOS, raylib needs these frameworks linked at the executable level
    // (transitive linking from the static library doesn't cover them all).
    if (target.result.os.tag == .macos) {
        exe_mod.linkFramework("OpenGL", .{});
        exe_mod.linkFramework("Cocoa", .{});
        exe_mod.linkFramework("CoreAudio", .{});
        exe_mod.linkFramework("CoreVideo", .{});
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // Minimal raylib test target
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.linkLibrary(raylib);
    if (target.result.os.tag == .macos) {
        test_mod.linkFramework("OpenGL", .{});
        test_mod.linkFramework("Cocoa", .{});
        test_mod.linkFramework("CoreAudio", .{});
        test_mod.linkFramework("CoreVideo", .{});
    }
    const test_exe = b.addExecutable(.{
        .name = "raylib-test",
        .root_module = test_mod,
    });
    b.installArtifact(test_exe);
    const test_run_cmd = b.addRunArtifact(test_exe);
    test_run_cmd.step.dependOn(b.getInstallStep());
    const test_run_step = b.step("test-raylib", "Run minimal raylib test");
    test_run_step.dependOn(&test_run_cmd.step);
}
