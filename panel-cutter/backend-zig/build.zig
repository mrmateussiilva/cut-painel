const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "imgcutter",
        .root_module = root_mod,
        .linkage = .dynamic,
    });

    lib.linkLibC();

    // stb (vendored)
    lib.addIncludePath(b.path("vendor/stb"));
    lib.addCSourceFile(.{
        .file = b.path("vendor/stb/stb_impl.c"),
        .flags = &.{"-std=c99"},
    });

    b.installArtifact(lib);
}
