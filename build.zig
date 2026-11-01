//! Zilisp のビルド定義。
//!
//!   zig build                 実行ファイルを zig-out/bin/ に出力する
//!   zig build run -- ARGS     実行する
//!   zig build test            単体テストを実行する
//!   zig build bench           ベンチマークを ReleaseFast で実行する（詳細設計 §13.2）
//!
//! 2段階ビルド（標準ライブラリのネイティブ化。詳細設計 §11.3）は Phase 12 で追加する。

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zilisp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run zilisp");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // ベンチマークは常に ReleaseFast でビルドする（速度最優先。基本設計 §17）
    const bench_exe = b.addExecutable(.{
        .name = "zilisp-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/bench/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.addPassthruArgs();
    const bench_step = b.step("bench", "Run benchmarks (ReleaseFast)");
    bench_step.dependOn(&run_bench.step);
}
