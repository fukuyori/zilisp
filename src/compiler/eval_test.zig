//! eval（Resolver・コード生成・VM・プリミティブ）の試験。
//! 期待する値は SBCL 2.6.7 で同じ式を評価して印字したもの（D:\tmp の生成用スクリプトで作った表）。

const std = @import("std");
const testing = std.testing;
const Value = @import("../values/value.zig").Value;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const thread_mod = @import("../runtime/thread.zig");
const Thread = thread_mod.Thread;
const ErrorKind = thread_mod.ErrorKind;
const eval_mod = @import("eval.zig");
const reader = @import("../reader/reader.zig");
const vb = @import("../reader/value_builder.zig");
const printer = @import("../printer/printer.zig");

const Env = struct {
    rt: *Runtime,
    th: *Thread,
    out: std.Io.Writer.Allocating,

    fn init(e: *Env) !void {
        e.rt = try Runtime.create(testing.allocator);
        errdefer e.rt.destroy();
        e.out = .init(testing.allocator);
        e.th = try Thread.create(e.rt, &e.out.writer, .{});
    }
    fn deinit(e: *Env) void {
        e.th.destroy();
        e.rt.destroy();
        e.out.deinit();
    }
};

/// テキストのフォームを順に評価し、最後の値を返す（エラーなら Value.unwind）
fn evalText(e: *Env, text: []const u8) !Value {
    var src = reader.Source.init(text, 0);
    var b: vb.ValueBuilder = .{ .rt = e.rt };
    var r = reader.Reader(vb.ValueBuilder).init(testing.allocator, &src, &b, .{});
    defer r.deinit();
    var last = Value.nil;
    while (try r.read()) |form| {
        last = eval_mod.eval(e.th, form);
        if (last == Value.unwind) return last;
    }
    return last;
}

fn expectValue(e: *Env, text: []const u8, expected: []const u8) !void {
    const v = try evalText(e, text);
    if (v == Value.unwind) {
        var buf: std.Io.Writer.Allocating = .init(testing.allocator);
        defer buf.deinit();
        try e.th.writeError(&buf.writer);
        std.debug.print("input: {s}\nerror: {s}\n", .{ text, buf.written() });
        return error.TestUnexpectedError;
    }
    var buf: std.Io.Writer.Allocating = .init(testing.allocator);
    defer buf.deinit();
    try printer.prin1(e.rt, &buf.writer, v);
    testing.expectEqualStrings(expected, buf.written()) catch |err| {
        std.debug.print("input: {s}\n", .{text});
        return err;
    };
}

fn expectError(e: *Env, text: []const u8, kind: ErrorKind) !void {
    const v = try evalText(e, text);
    if (v != Value.unwind) {
        std.debug.print("input: {s}\nエラーにならなかった\n", .{text});
        return error.TestExpectedError;
    }
    testing.expectEqual(kind, e.th.err.kind) catch |err| {
        std.debug.print("input: {s}\n", .{text});
        return err;
    };
    e.th.clearError();
    // エラーの後も VM の状態は元に戻っている
    try testing.expectEqual(@as(usize, 0), e.th.vm.fp);
    try testing.expectEqual(@as(usize, 0), e.th.vm.sp);
}

const value_cases = [_][2][]const u8{
    .{ "(+ 1 2)", "3" },
    .{ "(+)", "0" },
    .{ "(*)", "1" },
    .{ "(- 5)", "-5" },
    .{ "(- 10 1 2)", "7" },
    .{ "(* 2 3 4)", "24" },
    .{ "(/ 12 4)", "3" },
    .{ "(/ 12 4 3)", "1" },
    .{ "(+ 1 2.5)", "3.5" },
    .{ "(+ 1 2.5d0)", "3.5d0" },
    .{ "(* 1.5 2)", "3.0" },
    .{ "(- 0.0)", "-0.0" },
    .{ "(- 0.0d0)", "-0.0d0" },
    .{ "(/ 1.0 4)", "0.25" },
    .{ "(/ 2.0)", "0.5" },
    .{ "(1+ 41)", "42" },
    .{ "(1- 0)", "-1" },
    .{ "(1+ 1.5)", "2.5" },
    .{ "(= 1 1.0)", "T" },
    .{ "(< 1 2 3)", "T" },
    .{ "(< 1 3 2)", "NIL" },
    .{ "(>= 3 3 1)", "T" },
    .{ "(/= 1 2 3)", "T" },
    .{ "(/= 1 2 1)", "NIL" },
    .{ "(= 1 1 1)", "T" },
    .{ "(<= 1 1.5d0 2)", "T" },
    .{ "(+ 1.5 2.5d0)", "4.0d0" },
    .{ "(- -2305843009213693951 1)", "-2305843009213693952" },
    .{ "(+ 2305843009213693950 1)", "2305843009213693951" },
    .{ "(> 2 1.5)", "T" },
    .{ "(= 0.0 -0.0)", "T" },
    .{ "(< 16777217 16777216.0)", "NIL" },
    .{ "(= 16777217 16777216.0)", "NIL" },
    .{ "(* -1 0.0)", "-0.0" },
    .{ "(list 1 2 3)", "(1 2 3)" },
    .{ "(list)", "NIL" },
    .{ "(cons 1 2)", "(1 . 2)" },
    .{ "(car '(a b))", "A" },
    .{ "(cdr '(a b))", "(B)" },
    .{ "(car nil)", "NIL" },
    .{ "(cdr nil)", "NIL" },
    .{ "(list* 1 2 '(3))", "(1 2 3)" },
    .{ "(list* 1)", "1" },
    .{ "(first '(1 2))", "1" },
    .{ "(rest '(1 2))", "(2)" },
    .{ "(null nil)", "T" },
    .{ "(null 1)", "NIL" },
    .{ "(not 1)", "NIL" },
    .{ "(atom 'a)", "T" },
    .{ "(atom '(1))", "NIL" },
    .{ "(consp '(1))", "T" },
    .{ "(listp nil)", "T" },
    .{ "(listp 1)", "NIL" },
    .{ "(symbolp nil)", "T" },
    .{ "(symbolp 'a)", "T" },
    .{ "(symbolp 1)", "NIL" },
    .{ "(numberp 1.5)", "T" },
    .{ "(numberp 'a)", "NIL" },
    .{ "(functionp #'car)", "T" },
    .{ "(functionp 'car)", "NIL" },
    .{ "(eq 'a 'a)", "T" },
    .{ "(eql 1.0 1.0)", "T" },
    .{ "(eql 1.0d0 1.0d0)", "T" },
    .{ "(eql 0.0 -0.0)", "NIL" },
    .{ "(eql 1 1.0)", "NIL" },
    .{ "(eq nil '())", "T" },
    .{ "(if nil 1 2)", "2" },
    .{ "(if 1 2)", "2" },
    .{ "(if nil 1)", "NIL" },
    .{ "(progn 1 2 3)", "3" },
    .{ "(progn)", "NIL" },
    .{ "(let ((x 1) (y 2)) (+ x y))", "3" },
    .{ "(let ((x 1)) (let ((x 2) (y x)) y))", "1" },
    .{ "(let (x (y)) (list x y))", "(NIL NIL)" },
    .{ "(let ((x 1)) (setq x 5) x)", "5" },
    .{ "(setq)", "NIL" },
    .{ "(quote (a . b))", "(A . B)" },
    .{ "(let () 5)", "5" },
    .{ "(let ((x 1)) (declare (ignorable x)) 7)", "7" },
    .{ "((lambda (x y) (+ x y)) 1 2)", "3" },
    .{ "(funcall (lambda (x) (* x x)) 5)", "25" },
    .{ "(funcall #'+ 1 2 3)", "6" },
    .{ "(apply #'+ 1 2 '(3 4))", "10" },
    .{ "(apply #'list '())", "NIL" },
    .{ "(funcall 'list 1 2)", "(1 2)" },
    .{ "(apply 'cons '(1 2))", "(1 . 2)" },
    .{ "((lambda () \"doc\" 1))", "1" },
    .{ "((lambda ()))", "NIL" },
    .{ "(let ((n 0)) (let ((inc (lambda () (setq n (+ n 1))))) (funcall inc) (funcall inc) n))", "2" },
    .{ "(let ((counter (let ((n 0)) (lambda () (setq n (1+ n)))))) (funcall counter) (funcall counter) (funcall counter))", "3" },
    .{ "(let ((add (lambda (n) (lambda (x) (+ x n))))) (funcall (funcall add 10) 5))", "15" },
    .{ "(let ((n 0)) (let ((get (lambda () n)) (put (lambda (v) (setq n v)))) (funcall put 42) (funcall get)))", "42" },
    .{ "(let ((a 1)) (funcall (lambda () (funcall (lambda () (setq a (+ a 10)))))) a)", "11" },
    .{ "(funcall (lambda (x) (funcall (lambda () (setq x (* x 2)))) x) 21)", "42" },
    .{ "(let ((fs (list (let ((i 1)) (lambda () i)) (let ((i 2)) (lambda () i))))) (list (funcall (car fs)) (funcall (car (cdr fs)))))", "(1 2)" },
    .{ "(let ((x 1)) (list (let ((x 2)) x) x))", "(2 1)" },
    .{ "(let ((x 'outer)) (let ((f (lambda () x))) (let ((x 'inner)) (funcall f))))", "OUTER" },
    .{ "(funcall (funcall (funcall (lambda (a) (lambda (b) (lambda (c) (list a b c)))) 1) 2) 3)", "(1 2 3)" },
    .{ "\"abc\"", "\"abc\"" },
    .{ "#\\a", "#\\a" },
    .{ "#(1 2)", "#(1 2)" },
    .{ ":key", ":KEY" },
    .{ "t", "T" },
    .{ "nil", "NIL" },
    .{ "1.5d0", "1.5d0" },
};

/// Phase 09：let・let* の束縛と shadowing（SBCL 2.6.7 の結果）
const let_cases = [_][2][]const u8{
    .{ "(let* ((x 1) (y (+ x 1))) (list x y))", "(1 2)" },
    .{ "(let* () 5)", "5" },
    .{ "(let* (x (y)) (list x y))", "(NIL NIL)" },
    .{ "(let* ((x 1) (x (+ x 10))) x)", "11" },
    .{ "(let ((x 1)) (let* ((x (+ x 1)) (y x)) (list x y)))", "(2 2)" },
    .{ "(let ((x 1)) (let ((x (+ x 1)) (y x)) (list x y)))", "(2 1)" },
    .{ "(let ((x 1)) (list (let ((x 2)) (let ((x 3)) x)) x))", "(3 1)" },
    .{ "(let ((x 1)) (let ((x 2)) (setq x 20)) x)", "1" },
    .{ "(let ((x 1)) (let ((y 2)) (setq x 10)) x)", "10" },
    .{ "(let* ((x 1) (f (lambda () x)) (x 2)) (list (funcall f) x))", "(1 2)" },
    .{ "(let ((fs (list))) (let ((x 1)) (setq fs (cons (lambda () x) fs))) (let ((x 2)) (setq fs (cons (lambda () x) fs))) (list (funcall (car fs)) (funcall (car (cdr fs)))))", "(2 1)" },
    .{ "(let ((a 1)) (let ((b 2)) (let ((a 3) (c a)) (list a b c))))", "(3 2 1)" },
    .{ "(funcall (lambda (x) (let ((x (* x 2))) x)) 5)", "10" },
    .{ "(funcall (lambda (x) (let* ((y x) (x 100)) (list x y))) 5)", "(100 5)" },
    .{ "(let* ((x 1) (g (lambda () (setq x (+ x 1)) x))) (funcall g) (funcall g) x)", "3" },
    .{ "(let ((x 'a)) (declare (ignorable x)) (let* ((x 'b) (y x)) (declare (ignore y)) x))", "B" },
    .{ "(let* ((n 3) (f (lambda (k) (* n k)))) (setq n 4) (funcall f 10))", "40" },
    .{ "(let* ((x 1) (y (let ((x 10)) (+ x 1))) (z x)) (list x y z))", "(1 11 1)" },
    .{ "(let ((x 1) (y 2)) (let ((x y) (y x)) (list x y)))", "(2 1)" },
    .{ "(let* ((x 1) (y 2)) (let* ((x y) (y x)) (list x y)))", "(2 2)" },
    .{ "(let* ((x)) x)", "NIL" },
};

test "let and let* bind and shadow like SBCL 2.6.7 (Phase 09)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for (let_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = true;
    for (let_cases) |c| try expectValue(&e, c[0], c[1]);
    // SBCL 2.6.7 で program-error になるもの
    for ([_][]const u8{ "(let* ((t 1)) t)", "(let* ((x 1 2)) x)", "(let* (1) 1)", "(let* x 1)", "(let*)" }) |t| {
        try expectError(&e, t, .program_error);
    }
}

/// Phase 10：defun・関数の呼び出し・再帰（SBCL 2.6.7 の結果）
const defun_cases = [_][2][]const u8{
    .{ "(defun p10-sq (x) (* x x))", "P10-SQ" },
    .{ "(progn (defun p10-sq (x) (* x x)) (p10-sq 7))", "49" },
    .{ "(progn (defun p10-fact (n) (if (<= n 1) 1 (* n (p10-fact (- n 1))))) (p10-fact 10))", "3628800" },
    .{ "(progn (defun p10-fib (n) (if (< n 2) n (+ (p10-fib (- n 1)) (p10-fib (- n 2))))) (p10-fib 20))", "6765" },
    .{ "(progn (defun p10-ev (n) (if (= n 0) t (p10-od (- n 1)))) (defun p10-od (n) (if (= n 0) nil (p10-ev (- n 1)))) (list (p10-ev 10) (p10-od 7) (p10-ev 7)))", "(T T NIL)" },
    .{ "(progn (defun p10-f () 1) (defun p10-f () 2) (p10-f))", "2" },
    .{ "(progn (defun p10-g (x) x) (list (funcall #'p10-g 1) (funcall 'p10-g 2) (apply #'p10-g '(3))))", "(1 2 3)" },
    .{ "(progn (defun p10-doc (x) \"doc\" (declare (ignorable x)) (+ x 1)) (p10-doc 1))", "2" },
    .{ "(progn (defun p10-none ()) (p10-none))", "NIL" },
    .{ "(progn (defun p10-str () \"only\") (p10-str))", "\"only\"" },
    .{ "(progn (let ((count 0)) (defun p10-counter () (setq count (+ count 1)))) (p10-counter) (p10-counter))", "2" },
    .{ "(progn (defun p10-compose (f g) (lambda (x) (funcall f (funcall g x)))) (funcall (p10-compose #'1+ #'p10-sq) 3))", "10" },
    .{ "(progn (defun p10-twice (f x) (funcall f (funcall f x))) (p10-twice (lambda (y) (* y 3)) 2))", "18" },
    .{ "(progn (defun p10-k (x) (+ x 1)) (funcall (symbol-function 'p10-k) 1))", "2" },
    .{ "(progn (defun p10-sum (n) (if (= n 0) 0 (+ n (p10-sum (- n 1))))) (p10-sum 10000))", "50005000" },
    .{ "(progn (defun p10-loc (x) (let ((x (+ x 1))) (let* ((y (* x 2))) (list x y)))) (p10-loc 1))", "(2 4)" },
};

test "defun, function calls and recursion like SBCL 2.6.7 (Phase 10)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for (defun_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = true;
    for (defun_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = false;
    // fboundp：関数なら関数そのもの、マクロ・特殊演算子なら真、なければ NIL
    try expectValue(&e, "(progn (defun p10-h (x) x) (list (eq (fboundp 'p10-h) #'p10-h) (fboundp 'p10-undefined-xyz) (eq (fboundp 'car) #'car) (fboundp 'if) (fboundp 'defun)))", "(T NIL T T T)");
    try expectValue(&e, "(progn (defun p10-sq (x) (* x x)) #'p10-sq)", "#<FUNCTION P10-SQ>");
    // SBCL 2.6.7 でエラーになるもの
    try expectError(&e, "(p10-sq)", .program_error);
    try expectError(&e, "(p10-sq 1 2)", .program_error);
    try expectError(&e, "(defun car (x) x)", .package_error);
    try expectError(&e, "(defun 1 () 1)", .program_error);
    try expectError(&e, "(defun p10-bad)", .program_error);
    try expectError(&e, "(symbol-function 'p10-undefined-xyz)", .undefined_function);
    try expectError(&e, "(defun (setf p10-x) (v) v)", .unimplemented);
    try expectError(&e, "(funcall 'defun 'a nil)", .undefined_function);
    // CL の関数の定義は変わっていない
    try expectValue(&e, "(car '(1 2))", "1");
    // 再定義はすぐに反映される（呼び出しのたびに関数セルを参照する）
    try expectValue(&e, "(progn (defun p10-a () 1) (defun p10-b () (p10-a)) (defun p10-a () 2) (p10-b))", "2");
    // 深い再帰（10 万段）
    try expectValue(&e, "(progn (defun p10-depth (n) (if (= n 0) 0 (+ 1 (p10-depth (- n 1))))) (p10-depth 100000))", "100000");
}

/// Phase 11：flet・labels とクロージャ（SBCL 2.6.7 の結果）
const local_fn_cases = [_][2][]const u8{
    .{ "(flet ((f (x) (* x 2))) (f 5))", "10" },
    .{ "(flet ((f (x) (* x 2)) (g (y) (+ y 1))) (list (f 5) (g 5)))", "(10 6)" },
    .{ "(flet () 1)", "1" },
    .{ "(flet ((f () 1)) (flet ((f () (+ 1 (f)))) (f)))", "2" },
    .{ "(progn (defun p11-f () 'global) (flet ((p11-f () 'local) (g () (p11-f))) (list (p11-f) (g))))", "(LOCAL GLOBAL)" },
    .{ "(progn (defun p11-f () 'global) (labels ((p11-f () 'local) (g () (p11-f))) (list (p11-f) (g))))", "(LOCAL LOCAL)" },
    .{ "(labels ((fact (n) (if (<= n 1) 1 (* n (fact (- n 1)))))) (fact 10))", "3628800" },
    .{ "(labels ((ev (n) (if (= n 0) t (od (- n 1)))) (od (n) (if (= n 0) nil (ev (- n 1))))) (list (ev 10) (od 7)))", "(T T)" },
    .{ "(flet ((f (x) x)) (funcall #'f 3))", "3" },
    .{ "(let ((n 10)) (flet ((add (x) (+ x n))) (setq n 20) (add 1)))", "21" },
    .{ "(let ((fs (labels ((mk (i) (lambda () i))) (list (mk 1) (mk 2) (mk 3))))) (list (funcall (car fs)) (funcall (car (cdr fs))) (funcall (car (cdr (cdr fs))))))", "(1 2 3)" },
    .{ "(flet ((f (x) \"doc\" (declare (ignore x)) 1)) (f 2))", "1" },
    .{ "(flet ((f (x) x)) (declare (notinline f)) (f 4))", "4" },
    .{ "(labels ((sum (l) (if (null l) 0 (+ (car l) (sum (cdr l)))))) (sum '(1 2 3 4)))", "10" },
    .{ "(progn (defun p11-make-counter () (let ((c 0)) (list (lambda () (setq c (+ c 1))) (lambda () c)))) (let* ((p (p11-make-counter)) (inc (car p)) (get (car (cdr p)))) (funcall inc) (funcall inc) (funcall get)))", "2" },
    .{ "(progn (defun p11-make-counter () (let ((c 0)) (list (lambda () (setq c (+ c 1))) (lambda () c)))) (let* ((p1 (p11-make-counter)) (p2 (p11-make-counter))) (funcall (car p1)) (funcall (car p1)) (funcall (car p2)) (list (funcall (car (cdr p1))) (funcall (car (cdr p2))))))", "(2 1)" },
    .{ "(flet ((f (x) (labels ((g (y) (if (= y 0) x (g (- y 1))))) (g 3)))) (f 'done))", "DONE" },
    .{ "(labels ((f (n acc) (if (= n 0) acc (f (- n 1) (+ acc n))))) (f 10000 0))", "50005000" },
    .{ "(flet ((f (x) x) (f (y) y)) (f 1))", "1" },
    .{ "(labels ((f (x) x) (f (y) y)) (f 1))", "1" },
};

test "flet and labels like SBCL 2.6.7 (Phase 11)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for (local_fn_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = true;
    for (local_fn_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = false;
    // flet の関数は自分自身を見ない（本体の中の f は大域の関数 f）。labels は見る
    try expectError(&e, "(flet ((p11-self (n) (if (= n 0) 0 (p11-self (- n 1))))) (p11-self 3))", .undefined_function);
    try expectValue(&e, "(labels ((p11-self (n) (if (= n 0) 0 (p11-self (- n 1))))) (p11-self 3))", "0");
    // SBCL 2.6.7 で program-error になるもの
    for ([_][]const u8{
        "(flet ((car (x) x)) (car 1))",
        "(flet ((if (x) x)) (if 1))",
        "(labels ((get () 1)) (get))",
        "(flet ((f (x) x)) (f))",
        "(flet (f) 1)",
        "(flet ((1 () 1)) 1)",
        "(flet ((f)) 1)",
        "(flet)",
    }) |t| try expectError(&e, t, .program_error);
    try expectError(&e, "(flet (((setf f) (v) v)) 1)", .unimplemented);
    // 印字：#<FUNCTION (FLET FOO) {アドレス}>（SBCL 2.6.7 は (FLET FOO :IN ファイル) と書く）
    for ([_][2][]const u8{
        .{ "(flet ((foo () 1)) #'foo)", "#<FUNCTION (FLET FOO) {" },
        .{ "(labels ((foo () 1)) #'foo)", "#<FUNCTION (LABELS FOO) {" },
    }) |c| {
        const v = try evalText(&e, c[0]);
        var buf: std.Io.Writer.Allocating = .init(testing.allocator);
        defer buf.deinit();
        try printer.prin1(e.rt, &buf.writer, v);
        try testing.expect(std.mem.startsWith(u8, buf.written(), c[1]));
    }
}

test "closures outlive their creators and survive collections (Phase 11)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    // 1000 個の closure を作り、それぞれが別の束縛を捕捉する。作った関数から戻った後も、GC の後も値が正しい
    _ = try evalText(&e,
        \\(setq p11-keep
        \\  (labels ((mk (i) (if (= i 0) nil (cons (let ((x i)) (lambda () x)) (mk (- i 1))))))
        \\    (mk 1000)))
    );
    e.rt.collect();
    e.rt.collect();
    try expectValue(&e, "(labels ((sum (l) (if (null l) 0 (+ (funcall (car l)) (sum (cdr l)))))) (sum p11-keep))", "500500");
    // 2 つの closure が共有する変数（value_cell）も、GC の後で共有されたまま
    _ = try evalText(&e,
        \\(defun p11-account (balance)
        \\  (list (lambda (x) (setq balance (+ balance x))) (lambda () balance)))
        \\(setq p11-acc (p11-account 100))
    );
    e.rt.collect();
    try expectValue(&e, "(progn (funcall (car p11-acc) 50) (funcall (car (cdr p11-acc))))", "150");
    e.rt.collect();
    try expectValue(&e, "(progn (funcall (car p11-acc) -30) (funcall (car (cdr p11-acc))))", "120");
    // 再帰の各段で作った closure は、その段の束縛を捕捉する
    try expectValue(&e,
        \\(labels ((collect (n) (if (= n 0) nil (cons (lambda () n) (collect (- n 1))))))
        \\  (let ((fs (collect 3))) (list (funcall (car fs)) (funcall (car (cdr fs))) (funcall (car (cdr (cdr fs)))))))
    , "(3 2 1)");
}

/// Phase 14：動的束縛・special 宣言・defvar・defparameter・progv（SBCL 2.6.7 の結果）
const special_cases = [_][2][]const u8{
    .{ "(defvar *p14-a* 1)", "*P14-A*" },
    .{ "(progn (defvar *p14-a* 1) (defvar *p14-a* 2) *p14-a*)", "1" },
    .{ "(progn (defparameter *p14-b* 1) (defparameter *p14-b* 2) *p14-b*)", "2" },
    .{ "(defparameter *p14-c* 3 \"doc\")", "*P14-C*" },
    .{ "(progn (defvar *p14-x* 10) (defun p14-get-x () *p14-x*) (list (let ((*p14-x* 20)) (p14-get-x)) (p14-get-x)))", "(20 10)" },
    .{ "(progn (defvar *p14-x* 10) (defun p14-get-x () *p14-x*) (list (let ((*p14-x* 20)) (setq *p14-x* 30) (p14-get-x)) *p14-x*))", "(30 10)" },
    .{ "(progn (defvar *p14-x* 10) (funcall (let ((*p14-x* 5)) (lambda () *p14-x*))))", "10" },
    .{ "(progn (defun p14-read-y () (declare (special p14-y)) p14-y) (let ((p14-y 7)) (declare (special p14-y)) (p14-read-y)))", "7" },
    .{ "(let ((p14-z 1)) (let ((p14-z 2)) (declare (special p14-z)) (funcall (lambda () (declare (special p14-z)) p14-z))))", "2" },
    .{ "(let ((p14-w 'lex)) (let ((p14-w 'dyn)) (declare (special p14-w)) (list p14-w (funcall (lambda () p14-w)))))", "(DYN DYN)" },
    .{ "(progn (defvar *p14-u*) (list (let ((*p14-u* 1)) *p14-u*) (boundp '*p14-u*)))", "(1 NIL)" },
    .{ "(list (progv '(*p14-p1*) '(5) (symbol-value '*p14-p1*)) (boundp '*p14-p1*))", "(5 NIL)" },
    .{ "(progv '(*p14-p2* *p14-p3*) '(1) (list (symbol-value '*p14-p2*) (boundp '*p14-p3*)))", "(1 NIL)" },
    .{ "(progn (defvar *p14-depth* 0) (defun p14-g () *p14-depth*) (defun p14-f (*p14-depth*) (p14-g)) (list (p14-f 5) *p14-depth*))", "(5 0)" },
    .{ "(progn (defvar *p14-x* 10) (let* ((*p14-x* 1) (y *p14-x*)) (list y *p14-x*)))", "(1 1)" },
    .{ "(progn (defvar *p14-s* 0) (set '*p14-s* 3) (list *p14-s* (symbol-value '*p14-s*)))", "(3 3)" },
    .{ "(progn (defvar *p14-x* 10) (let ((*p14-x* 1)) (let ((*p14-x* 2)) (setq *p14-x* 3)) *p14-x*))", "1" },
    .{ "(progn (defvar *p14-n* 0) (defun p14-count (n) (if (= n 0) *p14-n* (let ((*p14-n* (+ *p14-n* 1))) (p14-count (- n 1))))) (list (p14-count 100) *p14-n*))", "(100 0)" },
    .{ "(progn (defvar *p14-x* 10) (flet ((show () *p14-x*)) (let ((*p14-x* 42)) (show))))", "42" },
    .{ "(boundp 'p14-never)", "NIL" },
    .{ "(progn (defvar *p14-x* 10) (let ((*p14-x* 1) (y *p14-x*)) y))", "10" },
    .{ "(let ((x 1)) (declare (special x)) (setq x 2) x)", "2" },
};

test "dynamic binding like SBCL 2.6.7 (Phase 14)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for (special_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = true;
    for (special_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = false;
    try testing.expectEqual(@as(usize, 0), e.th.binding_depth);
    // エラーで抜けると、その間の動的束縛は元に戻る
    try expectValue(&e, "(defvar *p14-e* 10)", "*P14-E*");
    try expectError(&e, "(let ((*p14-e* 99)) (car 1))", .type_error);
    try testing.expectEqual(@as(usize, 0), e.th.binding_depth);
    try expectValue(&e, "*p14-e*", "10");
    // apply（Zig の関数）を挟んだ中のエラーでも戻る
    try expectError(&e, "(let ((*p14-e* 1)) (apply (lambda () (let ((*p14-e* 2)) (car 1))) nil))", .type_error);
    try expectValue(&e, "*p14-e*", "10");
    // 未束縛の特殊変数を束縛して抜けると、未束縛に戻る
    try expectValue(&e, "(progn (defvar *p14-unb*) (let ((*p14-unb* 1)) (list *p14-unb* (boundp '*p14-unb*))))", "(1 T)");
    try expectValue(&e, "(boundp '*p14-unb*)", "NIL");
    try expectError(&e, "*p14-unb*", .unbound_variable);
    // 深い動的束縛（再帰の各段で束縛する）
    try expectValue(&e, "(progn (defvar *p14-k* 0) (defun p14-deep (n) (if (= n 0) *p14-k* (let ((*p14-k* (+ *p14-k* 1))) (p14-deep (- n 1))))) (p14-deep 10000))", "10000");
    // 束縛のスタックが溢れるとエラーになり、元に戻る
    try expectError(&e, "(p14-deep 100000)", .storage_condition);
    try testing.expectEqual(@as(usize, 0), e.th.binding_depth);
    try expectValue(&e, "*p14-k*", "0");
}

test "Codex review of Phase 14: progv slots, defvar outside the toplevel" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    // progv の深さの局所変数が、シンボル・値の式の中の let と重ならない（#1）
    try expectValue(&e, "(progn (defparameter *rv-pv* 0) (progv (let ((a 5)) a '(*rv-pv*)) (let ((b 1)) b '(1)) *rv-pv*))", "1");
    try expectValue(&e, "*rv-pv*", "0");
    try testing.expectEqual(@as(usize, 0), e.th.binding_depth);
    // 実行されない defvar は宣言しない（#3。SBCL 2.6.7：(1 NIL)）
    try expectValue(&e, "(if nil (defvar rv-x) nil)", "NIL");
    try expectValue(&e, "(let ((rv-x 1)) (list rv-x (boundp 'rv-x)))", "(1 NIL)");
    // トップレベルの progn の中の defvar は、コンパイルの時点で宣言する（SBCL 2.6.7：T）
    try expectValue(&e, "(progn (defvar *rv-top*) (let ((*rv-top* 1)) (boundp '*rv-top*)))", "T");
    // 関数の中の defvar は、実行した時点で宣言する。その後でコンパイルしたフォームの束縛は動的束縛になる
    // （load の意味。SBCL 2.6.7 の --script でも (1 T 1)。compile-file でまとめてコンパイルすると (1 T 5) になる）
    try expectValue(&e, "(defun rv-define () (defvar rv-late 5))", "RV-DEFINE");
    try expectValue(&e, "(rv-define)", "RV-LATE");
    try expectValue(&e, "(let ((rv-late 1)) (list rv-late (boundp 'rv-late) (symbol-value 'rv-late)))", "(1 T 1)");
}

test "eval matches SBCL 2.6.7" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for (value_cases) |c| try expectValue(&e, c[0], c[1]);
}

test "eval under gc stress" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    e.rt.heap.stress = true;
    for (value_cases) |c| try expectValue(&e, c[0], c[1]);
    try testing.expect(e.rt.heap.stats.collections > 100);
}

test "global variables and functions as values" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    try expectValue(&e, "(setq x 10) (setq y (+ x 5)) (list x y)", "(10 15)");
    try expectValue(&e, "(setq fact (lambda (n) (if (<= n 1) 1 (* n (funcall fact (- n 1)))))) (funcall fact 10)", "3628800");
    try expectValue(&e, "(setq fib (lambda (n) (if (< n 2) n (+ (funcall fib (- n 1)) (funcall fib (- n 2)))))) (funcall fib 20)", "6765");
    // fixnum の範囲を超える結果は、bignum が未実装なのでエラー（20! は 2^61 を超える）
    try expectError(&e, "(funcall fact 20)", .unimplemented);
    try expectValue(&e, "(funcall fact 19)", "121645100408832000");
}

test "errors" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    const cases = [_]struct { []const u8, ErrorKind }{
        .{ "(car 1)", .type_error },
        .{ "(cdr 'a)", .type_error },
        .{ "undefined-x", .unbound_variable },
        .{ "(undefined-fn 1)", .undefined_function },
        .{ "#'undefined-fn", .undefined_function },
        .{ "((lambda (x) x))", .program_error },
        .{ "(funcall #'car 1 2)", .program_error },
        .{ "(funcall (lambda (x) x) 1 2)", .program_error },
        .{ "(/ 1 0)", .division_by_zero },
        .{ "(/ 1.0 0)", .division_by_zero },
        .{ "(/ 1 2)", .unimplemented },
        .{ "(+ 'a 1)", .type_error },
        .{ "(< 1 'a)", .type_error },
        .{ "(* 2305843009213693951 2)", .unimplemented },
        .{ "(+ 2305843009213693951 1)", .unimplemented },
        .{ "(1+ 2305843009213693951)", .unimplemented },
        .{ "(- -2305843009213693952)", .unimplemented },
        .{ "(* 1e30 1e30)", .floating_point_overflow },
        .{ "(+ 1d308 1d308)", .floating_point_overflow },
        .{ "(defmacro m ())", .unimplemented },
        .{ "(block nil)", .unimplemented },
        .{ "(quote)", .program_error },
        .{ "(if)", .program_error },
        .{ "(let ((t 1)) t)", .program_error },
        .{ "(let ((x 1) (x 2)) x)", .program_error },
        .{ "(setq t 1)", .program_error },
        .{ "(setq :k 1)", .program_error },
        .{ "(setq x)", .program_error },
        .{ "(progv '(1) '(2) 3)", .type_error },
        .{ "(defvar)", .program_error },
        .{ "(lambda (&optional x) x)", .unimplemented },
        .{ "(lambda (x x) x)", .program_error },
        .{ "(funcall 1)", .type_error },
        .{ "(apply #'+ 1 2)", .type_error },
        .{ "(1 2)", .program_error },
        .{ "(defvar t 1)", .program_error },
        .{ "(symbol-value 'p14-never-bound)", .unbound_variable },
        .{ "(funcall 'quote 1)", .undefined_function },
        .{ "(car 1 2)", .program_error },
    };
    for (cases) |c| try expectError(&e, c[0], c[1]);
    // エラーの後も評価を続けられる
    try expectValue(&e, "(+ 1 2)", "3");
}

test "deep recursion reports stack overflow and recovers" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    try expectError(&e, "(setq f (lambda (n) (funcall f (+ n 1)))) (funcall f 0)", .storage_condition);
    // apply（Zig の関数）を挟んだ再帰でも、ネイティブのスタックを溢れさせずにエラーになる
    try expectError(&e, "(setq g (lambda (n) (apply g (list (+ n 1))))) (funcall g 0)", .storage_condition);
    try expectValue(&e, "(+ 1 2)", "3");
}

test "functions print like SBCL 2.6.7" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    try expectValue(&e, "#'car", "#<FUNCTION CAR>");
    for ([_][2][]const u8{
        .{ "(lambda (x) x)", "#<FUNCTION (LAMBDA (X)) {" },
        .{ "(lambda () 1)", "#<FUNCTION (LAMBDA ()) {" },
    }) |c| {
        const v = try evalText(&e, c[0]);
        var buf: std.Io.Writer.Allocating = .init(testing.allocator);
        defer buf.deinit();
        try printer.prin1(e.rt, &buf.writer, v);
        try testing.expect(std.mem.startsWith(u8, buf.written(), c[1]));
        try testing.expect(std.mem.endsWith(u8, buf.written(), "}>"));
    }
}

test "print writes to the thread's output" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    try expectValue(&e, "(print 1) (prin1 \"a\") (terpri) (print '(x . y))", "(X . Y)");
    try testing.expectEqualStrings("\n1 \"a\"\n\n(X . Y) ", e.out.written());
}

/// (f 1 1 ... 1) を n 個の引数で作る
fn callWithArgs(n: usize, f: []const u8) ![]u8 {
    var buf: std.Io.Writer.Allocating = .init(testing.allocator);
    errdefer buf.deinit();
    try buf.writer.print("({s}", .{f});
    for (0..n) |_| try buf.writer.writeAll(" 1");
    try buf.writer.writeByte(')');
    return buf.toOwnedSlice();
}

test "argument counts at the encoding boundaries (WIDE) and call-arguments-limit" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for ([_]usize{ 255, 256, 65535 }) |n| {
        const text = try callWithArgs(n, "+");
        defer testing.allocator.free(text);
        var expected: [16]u8 = undefined;
        try expectValue(&e, text, try std.fmt.bufPrint(&expected, "{d}", .{n}));
    }
    // call-arguments-limit（65536）は上限を含まないので、65536 個以上はエラー
    for ([_]usize{ 65536, 65537 }) |n| {
        const text = try callWithArgs(n, "+");
        defer testing.allocator.free(text);
        try expectError(&e, text, .program_error);
    }
    // closure にも 256 個の引数を渡せる（ラムダリストを作る）
    var lam: std.Io.Writer.Allocating = .init(testing.allocator);
    defer lam.deinit();
    try lam.writer.writeAll("(funcall (lambda (");
    for (0..256) |i| try lam.writer.print(" a{d}", .{i});
    try lam.writer.writeAll(") (+ a0 a255))");
    for (0..256) |i| try lam.writer.print(" {d}", .{i});
    try lam.writer.writeByte(')');
    try expectValue(&e, lam.written(), "255");
}

test "many constants and locals use WIDE operands" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    // 定数表が 65536 個を超える関数（大きな整数は定数表に入る）
    var buf: std.Io.Writer.Allocating = .init(testing.allocator);
    defer buf.deinit();
    // 1000 個ずつ 70 組のリストにする（1 回の呼び出しの引数は call-arguments-limit 未満）
    try buf.writer.writeAll("(car (car (cdr (list");
    for (0..70) |g| {
        try buf.writer.writeAll(" (list");
        for (0..1000) |i| try buf.writer.print(" {d}", .{100000 + g * 1000 + i});
        try buf.writer.writeAll(")");
    }
    try buf.writer.writeAll("))))");
    try expectValue(&e, buf.written(), "101000");
}

test "native call chains without the VM (apply of apply) stop at the depth limit" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    // Codex のレビューの例：(apply 'apply (list 'apply ...)) の連鎖は VM を挟まない
    try expectError(&e,
        \\(setq f (lambda (n args) (if (= n 0) (apply 'apply args) (funcall f (1- n) (list 'apply args)))))
        \\(funcall f 1100 (list '+ '(1 2)))
    , .storage_condition);
    try testing.expectEqual(@as(u32, 0), e.th.native_depth);
    // 上限より浅ければ動く
    try expectValue(&e, "(funcall f 100 (list '+ '(1 2)))", "3");
}

test "documentation strings and declarations in bodies (CLHS 3.4.11)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    // 期待値は SBCL 2.6.7 の結果
    try expectValue(&e, "((lambda () \"doc\" 42))", "42");
    try expectValue(&e, "((lambda () (declare) \"doc\" 42))", "42");
    try expectValue(&e, "((lambda () \"doc\" (declare) 42))", "42");
    try expectValue(&e, "((lambda () \"a\" \"b\"))", "\"b\"");
    try expectValue(&e, "((lambda () \"a\"))", "\"a\"");
    // 2 つ目の文字列は本体のフォームなので、その後の declare は宣言の位置ではない
    try expectError(&e, "((lambda () \"doc\" \"body\" (declare (ignore x)) 42))", .program_error);
    // let の本体には説明文字列を書けない
    try expectError(&e, "(let () \"s\" (declare) 1)", .program_error);
}

/// フォームをコンパイルし、トップレベルの関数のバイトコードに命令 op があるか
fn compiledHas(e: *Env, text: []const u8, op: @import("../vm/opcodes.zig").Op) !bool {
    var src = reader.Source.init(text, 0);
    var b: vb.ValueBuilder = .{ .rt = e.rt };
    var r = reader.Reader(vb.ValueBuilder).init(testing.allocator, &src, &b, .{});
    defer r.deinit();
    const form = (try r.read()).?;
    const closure = eval_mod.compile(e.th, form);
    try testing.expect(closure != Value.unwind);
    const function = @import("../runtime/function.zig");
    const code = function.closurePtr(closure).codePtr();
    // 命令の境界をたどって調べる
    const ops = @import("../vm/opcodes.zig");
    const bc = code.code();
    var at: usize = 0;
    var wide = false;
    while (at < bc.len) {
        const o: ops.Op = @fromBackingInt(bc[at]);
        if (o == op) return true;
        at += ops.length(o, wide);
        wide = o == .wide;
    }
    return false;
}

test "notinline declarations disable the fast path instructions (§5.3)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    try testing.expect(try compiledHas(&e, "(let ((x '(1))) (car x))", .car));
    try testing.expect(!try compiledHas(&e, "(let ((x '(1))) (declare (notinline car)) (car x))", .car));
    try testing.expect(try compiledHas(&e, "(let ((x '(1))) (declare (notinline car)) (car x))", .call_global));
    // 内側で inline と宣言し直すと、高速経路に戻る
    try testing.expect(try compiledHas(&e, "(let () (declare (notinline car)) (let () (declare (inline car)) (car '(1))))", .car));
    // funcall の notinline は、関数 FUNCALL を呼ぶ
    try testing.expect(!try compiledHas(&e, "(let () (declare (notinline funcall)) (funcall #'car '(1)))", .call));
    // 意味は同じ
    try expectValue(&e, "(let ((x '(1))) (declare (notinline car + funcall)) (funcall #'list (car x) (+ 1 2)))", "(1 3)");
}

/// 100 個の cons のリストを作って値スタックの枠 slot に置き、先頭のアドレスを反転して返す
/// （このアドレスを保守的な走査が見つけないよう、反転して持つ。gc.zig の試験と同じ方法）
noinline fn putListInVmSlot(th: *Thread, slot: usize) !usize {
    var list = Value.nil;
    for (0..100) |i| list = try th.rt.cons(Value.fromFixnum(@intCast(i)), list);
    th.vm.stack[slot] = list;
    return ~@intFromPtr(list.pointer());
}

noinline fn presentHidden(rt: *Runtime, hidden: usize) bool {
    return rt.heap.findObject(~hidden) != null;
}

noinline fn clobberStack() void {
    var buf: [16 * 1024]u8 = undefined;
    @memset(&buf, 0);
    std.mem.doNotOptimizeAway(&buf);
}

fn vmSlotBody(rt: *Runtime) !void {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    const th = try Thread.create(rt, &out.writer, .{ .stack_size = 64, .frame_count = 4 });
    defer th.destroy();
    // sp より上の枠（使い終わった枠）にある値はルートではない
    th.vm.sp = 3;
    const dead = try putListInVmSlot(th, 10);
    clobberStack();
    rt.collect();
    rt.heap.finishSweep();
    try testing.expect(!presentHidden(rt, dead));
    // sp より下の枠にある値はルート
    const live = try putListInVmSlot(th, 2);
    clobberStack();
    rt.collect();
    rt.heap.finishSweep();
    try testing.expect(presentHidden(rt, live));
    th.vm.sp = 0;
}

test "values left in VM stack slots above sp are not GC roots" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    // 走査の上端はこの関数のフレーム。値を扱う本体は inline 展開しない別の関数（gc.zig の withRuntime と同じ）
    rt.stack_top = @frameAddress();
    try @call(.never_inline, vmSlotBody, .{rt});
}
