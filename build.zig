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

    // 言語試験：tests/language/*.lisp を zilisp で実行し、*.expected と比べる
    const lang_test_exe = b.addExecutable(.{
        .name = "zilisp-lang-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/lang_test/main.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const run_lang_test = b.addRunArtifact(lang_test_exe);
    run_lang_test.addArtifactArg(exe);
    run_lang_test.addArg("tests/language");
    run_lang_test.has_side_effects = true;
    const lang_test_step = b.step("lang-test", "Run language tests (tests/language)");
    lang_test_step.dependOn(&run_lang_test.step);

    // 教材のコードブロックの抽出（詳細設計 §12）：zig build extract-samples -- <教材> <出力先>
    const extract_exe = b.addExecutable(.{
        .name = "zilisp-extract-samples",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/extract_samples/main.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const run_extract = b.addRunArtifact(extract_exe);
    run_extract.addPassthruArgs();
    run_extract.has_side_effects = true;
    const extract_step = b.step("extract-samples", "Extract Lisp code blocks from the curriculum Markdown");
    extract_step.dependOn(&run_extract.step);

    // 教材のブロックを Reader で読み、SBCL の結果と比べる：zig build reader-check -- .work/samples
    const reader_mod = b.createModule(.{
        .root_source_file = b.path("src/reader/reader.zig"),
        .target = b.graph.host,
    });
    const reader_check_exe = b.addExecutable(.{
        .name = "zilisp-reader-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/reader_check/main.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
            .imports = &.{.{ .name = "reader", .module = reader_mod }},
        }),
    });
    const run_reader_check = b.addRunArtifact(reader_check_exe);
    run_reader_check.addPassthruArgs();
    run_reader_check.has_side_effects = true;
    const reader_check_step = b.step("reader-check", "Read curriculum blocks with the Zilisp reader and compare with SBCL");
    reader_check_step.dependOn(&run_reader_check.step);

    // 道具の単体テストも test に含める
    for ([_][]const u8{ "tools/extract_samples/main.zig", "tools/lang_test/main.zig", "tests/bench/main.zig" }) |path| {
        const t = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = b.graph.host,
        }) });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
