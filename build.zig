const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("md4zig", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = !isFreestandingWasm(target),
    });
    attachMd4c(b, mod, target);

    const tests = b.addTest(.{ .name = "md4zig-tests", .root_module = mod });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    addWasmCheck(b);
}

fn isFreestandingWasm(target: std.Build.ResolvedTarget) bool {
    return target.result.cpu.arch.isWasm() and target.result.os.tag == .freestanding;
}

/// Compiles md4c into `mod`. Modules carry their own C sources and include
/// paths, so a consumer only has to `addImport` the module.
///
/// Freestanding wasm ships no libc at all — not even headers — so md4c's
/// `#include <stdlib.h>` fails before any symbol resolution happens.
/// `include/freestanding` declares the handful of functions it actually uses and
/// `src/libc.zig` defines them. Every other target links a real libc.
fn attachMd4c(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    mod.addIncludePath(b.path("vendor/md4c"));
    if (isFreestandingWasm(target)) mod.addIncludePath(b.path("include/freestanding"));
    // md4c's headers, translated once into a module of their own (`c`): Zig 0.17 removed
    // `@cImport`.
    const tc = b.addTranslateC(.{
        .root_source_file = b.path("include/md4zig_c.h"),
        .target = target,
        .optimize = mod.optimize orelse .debug,
        .link_libc = !isFreestandingWasm(target),
    });
    tc.addIncludePath(b.path("vendor/md4c"));
    if (isFreestandingWasm(target)) tc.addIncludePath(b.path("include/freestanding"));
    mod.addImport("c", tc.createModule());
    mod.addCSourceFiles(.{
        .root = b.path("vendor/md4c"),
        // entity.c is md4c's HTML5 entity table. md4c itself does not use it —
        // it reports entities verbatim — but every consumer that renders text
        // needs to resolve them, so `entity.zig` wraps it here rather than
        // making each one vendor the table again.
        .files = &.{ "md4c.c", "entity.c" },
        .flags = &.{"-std=c99"},
    });
}

/// `zig build check-wasm` — compile *and link* for wasm32-freestanding. The
/// regular `-Dtarget=` build only ever produces a module, so it cannot catch an
/// unresolved libc symbol; this can.
fn addWasmCheck(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const mod = b.createModule(.{
        .root_source_file = b.path("src/wasm_check.zig"),
        .target = target,
        .optimize = .small,
        .link_libc = false,
        .single_threaded = true,
    });
    attachMd4c(b, mod, target);

    const exe = b.addExecutable(.{ .name = "md4zig-wasm-check", .root_module = mod });
    exe.entry = .disabled;
    exe.root_module.export_symbol_names = &.{"md4zig_wasm_check"};

    b.step("check-wasm", "Compile and link for wasm32-freestanding").dependOn(&exe.step);
}
