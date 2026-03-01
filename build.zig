const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });

    const appMod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
    appMod.addSystemIncludePath(raylib_dep.path("include"));
    appMod.linkLibrary(raylib_dep.artifact("raylib"));

    const appExe = b.addExecutable(.{
        .name = "ZigParticleDemo",
        .root_module = appMod,
//        .use_llvm = true,
    });

    const app_install_step = &b.addInstallArtifact(appExe, .{}).step;  
    b.default_step.dependOn(app_install_step);

    const app_run_cmd = &b.addRunArtifact(appExe).step;
    app_run_cmd.dependOn(app_install_step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(app_run_cmd);
}
