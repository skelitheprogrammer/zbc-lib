const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardOptimizeOption(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_module = b.addModule("zbc", .{
        .root_source_file = b.path("src/calculator.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zbc",
        .root_module = lib_module,
    });

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_module,
    });

    b.addRunArtifact(lib_unit_tests);
}
