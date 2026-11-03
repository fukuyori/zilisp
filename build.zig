//! Zilisp のビルド定義。
//!
//!   zig build                 実行ファイルを zig-out/bin/ に出力する
//!   zig build run -- ARGS     実行する
//!   zig build test            単体テストを実行する
//!   zig build bench           ベンチマークを ReleaseFast で実行する（詳細設計 §13.2）
//!   zig build lang-test       言語試験（VM）
//!   zig build eval-check      教材のブロックを VM と SBCL で実行して比べる（-Dsbcl=SBCL のパス）
//!   zig build native-test     言語試験をネイティブバックエンドで実行し、VM と同じ結果かを確かめる（-Doptimize で最適化を指定）
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
    const zilisp_lib_fast = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const bench_exe = b.addExecutable(.{
        .name = "zilisp-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/bench/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "zilisp", .module = zilisp_lib_fast }},
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

    // ネイティブバックエンドの試験（Phase 12。詳細設計 §5.1「意味論の一致は、全言語試験を VM とネイティブの両方で
    // 実行して確認する」）：tests/language/eval/*.lisp を zilisp --emit-zig で Zig のソースにし、ランタイムと一緒に
    // コンパイルして実行する。標準出力を *.expected（VM の言語試験と同じ期待値）と、終了コードを *.exit と比べる。
    // ディレクトリは実行器が実行時に読む（build.zig の構成はキャッシュされ、ファイルを足しても作り直されないため）
    const native_test_exe = b.addExecutable(.{
        .name = "zilisp-native-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/native_test/main.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const run_native_test = b.addRunArtifact(native_test_exe);
    run_native_test.addArtifactArg(exe);
    run_native_test.addArg(b.graph.zig_exe);
    run_native_test.addArg("tests/language/eval");
    run_native_test.addArg("src/lib.zig");
    run_native_test.addArg(".zig-cache/native-test");
    run_native_test.addArg(@tagName(optimize));
    run_native_test.has_side_effects = true;
    const native_step = b.step("native-test", "Compile tests/language/eval with the native backend and compare with the VM results");
    native_step.dependOn(&run_native_test.step);

    // 教材のブロックを VM で実行し、SBCL の結果と比べる（Phase 13。詳細設計 §13.1）：
    //   zig build eval-check [-Dsbcl=SBCL のパス]   結果は compatibility/eval-status.md と eval-check.tsv
    const sbcl_path = b.option([]const u8, "sbcl", "Path to the SBCL executable (eval-check)") orelse "sbcl";
    const eval_check_exe = b.addExecutable(.{
        .name = "zilisp-eval-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/eval_check/main.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const run_eval_check = b.addRunArtifact(eval_check_exe);
    run_eval_check.addArtifactArg(exe);
    run_eval_check.addArg(sbcl_path);
    run_eval_check.addArg(".work/samples");
    run_eval_check.addArg(".zig-cache/eval-check");
    run_eval_check.addArg("compatibility/eval-status.md");
    run_eval_check.has_side_effects = true;
    const eval_check_step = b.step("eval-check", "Run curriculum blocks with the Zilisp VM and compare with SBCL");
    eval_check_step.dependOn(&run_eval_check.step);

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

    // 処理系の本体を道具から使うためのモジュール（src/ を根にする。Reader は src/unicode/ の表も使う）
    const zilisp_lib_host = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = b.graph.host,
    });

    // 教材のブロックを Reader で読み、SBCL の結果と比べる：zig build reader-check -- .work/samples
    const reader_check_exe = b.addExecutable(.{
        .name = "zilisp-reader-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/reader_check/main.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
            .imports = &.{.{ .name = "zilisp", .module = zilisp_lib_host }},
        }),
    });
    const run_reader_check = b.addRunArtifact(reader_check_exe);
    run_reader_check.addPassthruArgs();
    run_reader_check.has_side_effects = true;
    const reader_check_step = b.step("reader-check", "Read curriculum blocks with the Zilisp reader and compare with SBCL");
    reader_check_step.dependOn(&run_reader_check.step);

    // Unicode の文字の表（Phase 21.5。詳細設計 §11.2）：data/unicode/ の UCD から src/unicode/tables.zig を作る。
    // 表はコミットしておく（ネイティブバックエンドが src/lib.zig を直接コンパイルするため、ビルドの途中で作る表は使えない）。
    //   zig build gen-unicode    作り直す
    //   zig build test           表が UCD から作ったものと同じかを確かめる（--check）
    const gen_unicode_exe = b.addExecutable(.{
        .name = "zilisp-gen-unicode",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/gen_unicode/main.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    const ucd_args = [_][]const u8{ "data/unicode/UnicodeData.txt", "data/unicode/SpecialCasing.txt", "src/unicode/tables.zig" };
    const run_gen_unicode = b.addRunArtifact(gen_unicode_exe);
    run_gen_unicode.addArgs(&ucd_args);
    run_gen_unicode.has_side_effects = true;
    const gen_unicode_step = b.step("gen-unicode", "Generate src/unicode/tables.zig from the UCD in data/unicode");
    gen_unicode_step.dependOn(&run_gen_unicode.step);
    const check_unicode = b.addRunArtifact(gen_unicode_exe);
    check_unicode.addArgs(&ucd_args);
    check_unicode.addArg("--check");
    check_unicode.has_side_effects = true;
    test_step.dependOn(&check_unicode.step);

    // 道具の単体テストも test に含める
    for ([_][]const u8{ "tools/extract_samples/main.zig", "tools/lang_test/main.zig", "tools/native_test/main.zig", "tools/eval_check/main.zig", "tools/gen_unicode/main.zig", "tests/bench/main.zig" }) |path| {
        const t = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = b.graph.host,
            .imports = &.{.{ .name = "zilisp", .module = zilisp_lib_host }},
        }) });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
