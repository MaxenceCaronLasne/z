const std = @import("std");

pub fn build(b: *std.Build) void {
    var disabled_features = std.Target.Cpu.Feature.Set.empty;
    var enabled_features = std.Target.Cpu.Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.mmx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse2));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx2));
    enabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.soft_float));

    const target_query = std.Target.Query{
        .cpu_arch = std.Target.Cpu.Arch.x86,
        .os_tag = std.Target.Os.Tag.freestanding,
        .abi = std.Target.Abi.none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    };
    const optimize = std.builtin.OptimizeMode.Debug;

    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(target_query),
        .optimize = optimize,
        .code_model = .kernel,
    });

    kernel.setLinkerScript(b.path("src/linker.ld"));
    b.installArtifact(kernel);

    const kernel_step = b.step("kernel", "Build the kernel");
    kernel_step.dependOn(&kernel.step);

    // Run rule - launch QEMU with the kernel
    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-kernel",
        "zig-out/bin/kernel.elf",
        "-serial",
        "stdio",
    });
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the kernel in QEMU");
    run_step.dependOn(&run_cmd.step);

    // Debug rule - launch QEMU in debug mode
    const debug_qemu_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-kernel",
        "zig-out/bin/kernel.elf",
        "-serial",
        "stdio",
        "-s",
        "-S",
        "-display",
        "none",
    });
    debug_qemu_cmd.step.dependOn(b.getInstallStep());

    const debug_step = b.step(
        "debug",
        "Debug the kernel with QEMU (run 'gdb -x gdbinit' in another terminal)",
    );
    debug_step.dependOn(&debug_qemu_cmd.step);

    // GDB rule - launch GDB with initialization script
    const gdb_cmd = b.addSystemCommand(&[_][]const u8{
        "gdb",
        "-x",
        "gdbinit",
        "zig-out/bin/kernel.elf",
    });
    gdb_cmd.step.dependOn(b.getInstallStep());

    const gdb_step = b.step("gdb", "Launch GDB with initialization script");
    gdb_step.dependOn(&gdb_cmd.step);
}
