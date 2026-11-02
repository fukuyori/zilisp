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
    try expectValue(&e, "(defun (setf p10-x) (v) v)", "(SETF P10-X)");
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

/// Phase 15：backquote・defmacro・分解束縛・標準マクロ（SBCL 2.6.7 の結果）
const macro_cases = [_][2][]const u8{
    .{ "`(a b ,(+ 1 2))", "(A B 3)" },
    .{ "`(a ,@(list 1 2) c)", "(A 1 2 C)" },
    .{ "`(a . ,(+ 1 1))", "(A . 2)" },
    .{ "`(1 ,@nil 2)", "(1 2)" },
    .{ "`#(1 ,(+ 1 1))", "#(1 2)" },
    .{ "`,(+ 1 2)", "3" },
    .{ "`(,@'(1 2) . 3)", "(1 2 . 3)" },
    .{ "`(a ,@(list 1) ,@(list 2 3))", "(A 1 2 3)" },
    .{ "`(x (y ,(+ 1 1)) z)", "(X (Y 2) Z)" },
    .{ "`(1 ,.(list 2 3) 4)", "(1 2 3 4)" },
    .{ "(let ((x '(b c))) `(a ,@x d))", "(A B C D)" },
    .{ "`abc", "ABC" },
    .{ "`(a)", "(A)" },
    .{ "(progn (defmacro p15-inc (x) `(+ ,x 1)) (p15-inc 5))", "6" },
    .{ "(defmacro p15-inc (x) `(+ ,x 1))", "P15-INC" },
    .{ "(progn (defmacro p15-when (test &body body) `(if ,test (progn ,@body))) (list (p15-when t 1 2) (p15-when nil 1)))", "(2 NIL)" },
    .{ "(progn (defmacro p15-swap (a b) (let ((tmp (gensym))) `(let ((,tmp ,a)) (setq ,a ,b) (setq ,b ,tmp)))) (let ((x 1) (y 2)) (p15-swap x y) (list x y)))", "(2 1)" },
    .{ "(progn (defmacro p15-opt (a &optional (b 10)) `(list ,a ,b)) (list (p15-opt 1) (p15-opt 1 2)))", "((1 10) (1 2))" },
    .{ "(progn (defmacro p15-kw (&key (x 1) y) `(list ,x ,y)) (list (p15-kw :y 2) (p15-kw :x 5 :y 6) (p15-kw)))", "((1 2) (5 6) (1 NIL))" },
    .{ "(progn (defmacro p15-wh (&whole w a) (declare (ignore a)) `(quote ,w)) (p15-wh 1))", "(P15-WH 1)" },
    .{ "(progn (defmacro p15-dm ((a b) c) `(list ,a ,b ,c)) (p15-dm (1 2) 3))", "(1 2 3)" },
    .{ "(progn (defmacro p15-inc (x) `(+ ,x 1)) (macroexpand-1 '(p15-inc 5)))", "(+ 5 1)" },
    .{ "(progn (defmacro p15-inc (x) `(+ ,x 1)) (defmacro p15-m2 (x) `(p15-inc ,x)) (list (p15-m2 1) (macroexpand-1 '(p15-m2 1)) (macroexpand '(p15-m2 1))))", "(2 (P15-INC 1) (+ 1 1))" },
    .{ "(macroexpand-1 '(car x))", "(CAR X)" },
    .{ "(destructuring-bind (a (b c) &rest d) '(1 (2 3) 4 5) (list a b c d))", "(1 2 3 (4 5))" },
    .{ "(destructuring-bind (a &optional (b 2 b-p) &key (c 3)) '(1) (list a b b-p c))", "(1 2 NIL 3)" },
    .{ "(destructuring-bind (a &optional (b 2 b-p) &key (c 3)) '(1 5 :c 7) (list a b b-p c))", "(1 5 T 7)" },
    .{ "(destructuring-bind (a . b) '(1 2 3) (list a b))", "(1 (2 3))" },
    .{ "(destructuring-bind (&rest all) '(1 2) all)", "(1 2)" },
    .{ "(when t 1 2)", "2" },
    .{ "(when nil 1)", "NIL" },
    .{ "(unless nil 1 2)", "2" },
    .{ "(unless t 1)", "NIL" },
    .{ "(cond)", "NIL" },
    .{ "(cond (1))", "1" },
    .{ "(cond ((= 1 2) 'a) (t 'b))", "B" },
    .{ "(cond ((= 1 1) 'a 'c) (t 'b))", "C" },
    .{ "(cond (nil 1) ((+ 1 2)))", "3" },
    .{ "(and)", "T" },
    .{ "(or)", "NIL" },
    .{ "(and 1 2)", "2" },
    .{ "(and 1 nil 2)", "NIL" },
    .{ "(or nil 3)", "3" },
    .{ "(or nil nil)", "NIL" },
    .{ "(case 2 (1 'one) ((2 3) 'two-three) (otherwise 'other))", "TWO-THREE" },
    .{ "(case 'z (a 1) (t 2))", "2" },
    .{ "(case 5 (1 'one))", "NIL" },
    .{ "(case 'nil ((nil) 'is-nil) (t 'other))", "IS-NIL" },
    .{ "(prog1 1 2 3)", "1" },
    .{ "(prog2 1 2 3)", "2" },
    .{ "(let ((x 1)) (incf x) (incf x 10) x)", "12" },
    .{ "(let ((x 10)) (decf x) (decf x 3) x)", "6" },
    .{ "(let ((l nil)) (push 1 l) (push 2 l) (list (pop l) l))", "(2 (1))" },
    .{ "(let ((l '(1 2))) (list (pop l) (pop l) (pop l) l))", "(1 2 NIL NIL)" },
    .{ "(not (null (macro-function 'when)))", "T" },
    .{ "(macro-function 'car)", "NIL" },
    .{ "(progn (defmacro p15-lm (x) `(* ,x 2)) (flet ((p15-lm (x) (+ x 100))) (p15-lm 1)))", "101" },
};

test "macros and backquote like SBCL 2.6.7 (Phase 15)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for (macro_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = true;
    for (macro_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = false;
    // SBCL 2.6.7 でエラーになるもの
    try expectError(&e, "(funcall 'when t 1)", .undefined_function);
    try expectError(&e, "(defmacro car (x) x)", .package_error);
    try expectError(&e, "(destructuring-bind (a b) '(1) (list a b))", .program_error);
    try expectError(&e, "(destructuring-bind (a) '(1 2) a)", .program_error);
    try expectError(&e, "(progn (defmacro p15-two (a b) `(list ,a ,b)) (p15-two 1))", .program_error);
    try expectError(&e, "(flet ((when (x) x)) 1)", .program_error);
    try expectError(&e, "(destructuring-bind (&key a) '(:b 1) a)", .program_error);
    try expectError(&e, "(destructuring-bind (&key a) '(:a) a)", .program_error);
    try expectValue(&e, "(destructuring-bind (&key a &allow-other-keys) '(:b 1 :a 2) a)", "2");
    try expectValue(&e, "(destructuring-bind (&key a) '(:b 1 :allow-other-keys t) a)", "NIL");
    // 一般の場所（Phase 16 から）
    try expectValue(&e, "(let ((l (list 1))) (incf (car l)) l)", "(2)");
    // マクロの展開の中のエラーは、そのフォームのエラーとして報告する
    try expectError(&e, "(progn (defmacro p15-bad () (car 1)) (p15-bad))", .type_error);
    // マクロ関数の印字
    try expectValue(&e, "(progn (defmacro p15-pm () 1) (not (null (macro-function 'p15-pm))))", "T");
}

/// Phase 16：setf と場所・ハッシュ表・配列（SBCL 2.6.7 の結果）
const setf_cases = [_][2][]const u8{
    .{ "(let ((x 1)) (setf x 2) x)", "2" },
    .{ "(let ((a 1) (b 2)) (setf a 10 b 20) (list a b))", "(10 20)" },
    .{ "(setf)", "NIL" },
    .{ "(let ((l (list 1 2 3))) (setf (car l) 'a) (setf (cdr (cdr l)) '(z)) l)", "(A 2 Z)" },
    .{ "(let ((l (list 1 2 3))) (list (setf (second l) 'b) l))", "(B (1 B 3))" },
    .{ "(let ((l (list 1 2 3 4))) (setf (nth 2 l) 'c) (setf (cadr l) 'b) (setf (fourth l) 'd) l)", "(1 B C D)" },
    .{ "(let ((l (list (list 1 2) 3))) (setf (caar l) 'x) (setf (cdar l) '(y)) l)", "((X Y) 3)" },
    .{ "(let ((v (make-array 3 :initial-element 0))) (setf (aref v 1) 'x) v)", "#(0 X 0)" },
    .{ "(let ((v (make-array 3 :initial-contents '(a b c)))) (setf (svref v 0) 'z) (list v (length v) (aref v 2)))", "(#(Z B C) 3 C)" },
    .{ "(make-array 2)", "#(0 0)" },
    .{ "(let ((s (make-array 3 :element-type 'character :initial-element #\\a))) (setf (char s 1) #\\b) s)", "\"aba\"" },
    .{ "(let ((s (copy-seq \"hello\"))) (setf (aref s 0) #\\j) s)", "\"jello\"" },
    .{ "(let ((h (make-hash-table))) (setf (gethash 'a h) 1) (setf (gethash 'b h) 2) (list (gethash 'a h) (gethash 'b h) (gethash 'c h) (hash-table-count h)))", "(1 2 NIL 2)" },
    .{ "(let ((h (make-hash-table :test 'equal))) (setf (gethash \"key\" h) 'v) (setf (gethash '(1 2) h) 'w) (list (gethash \"key\" h) (gethash (list 1 2) h)))", "(V W)" },
    .{ "(let ((h (make-hash-table :test #'equal))) (setf (gethash \"a\" h) 1) (gethash \"a\" h))", "1" },
    .{ "(let ((h (make-hash-table))) (setf (gethash \"a\" h) 1) (gethash \"a\" h))", "NIL" },
    .{ "(let ((h (make-hash-table))) (setf (gethash 1.5d0 h) 'd) (gethash 1.5d0 h))", "D" },
    .{ "(let ((h (make-hash-table))) (gethash 'x h 'default))", "DEFAULT" },
    .{ "(let ((h (make-hash-table))) (setf (gethash 'a h) 1) (list (remhash 'a h) (remhash 'a h) (hash-table-count h)))", "(T NIL 0)" },
    .{ "(let ((h (make-hash-table))) (setf (gethash 'a h) 1) (clrhash h) (hash-table-count h))", "0" },
    .{ "(let ((h (make-hash-table)) (sum 0)) (setf (gethash 'a h) 1 (gethash 'b h) 2) (maphash (lambda (k v) (declare (ignore k)) (setq sum (+ sum v))) h) sum)", "3" },
    .{ "(let ((h (make-hash-table))) (incf (gethash 'n h 0)) (incf (gethash 'n h 0) 5) (gethash 'n h))", "6" },
    .{ "(let ((h (make-hash-table))) (push 'x (gethash 'k h)) (push 'y (gethash 'k h)) (gethash 'k h))", "(Y X)" },
    .{ "(hash-table-p (make-hash-table))", "T" },
    .{ "(hash-table-p 1)", "NIL" },
    .{ "(let ((l (list 1 2 3))) (incf (car l) 10) (decf (cadr l)) l)", "(11 1 3)" },
    .{ "(let ((l (list nil))) (push 1 (car l)) (push 2 (car l)) (list (pop (car l)) l))", "(2 ((1)))" },
    .{ "(let ((p (list :a 1 :b 2))) (list (getf p :a) (getf p :b) (getf p :c) (getf p :c 'd)))", "(1 2 NIL D)" },
    .{ "(let ((p (list :a 1))) (setf (getf p :a) 10) (setf (getf p :b) 20) p)", "(:B 20 :A 10)" },
    .{ "(let ((p nil)) (incf (getf p :count 0)) (incf (getf p :count 0)) p)", "(:COUNT 2)" },
    .{ "(progn (setf (get 'p16-sym 'color) 'red) (list (get 'p16-sym 'color) (get 'p16-sym 'size) (get 'p16-sym 'size 'none)))", "(RED NIL NONE)" },
    .{ "(progn (defvar *p16-v* 1) (setf (symbol-value '*p16-v*) 5) *p16-v*)", "5" },
    .{ "(progn (setf (symbol-function 'p16-f) (lambda (x) (* x 3))) (p16-f 4))", "12" },
    .{ "(progn (setf (fdefinition 'p16-g) (lambda () 'g)) (p16-g))", "G" },
    .{ "(progn (defun (setf p16-first) (new l) (setf (car l) new)) (let ((l (list 1 2))) (setf (p16-first l) 'x) l))", "(X 2)" },
    .{ "(progn (defun (setf p16-first) (new l) (setf (car l) new)) (funcall #'(setf p16-first) 'y (list 1)))", "Y" },
    .{ "(progn (defun p16-mid (v) (aref v 1)) (defsetf p16-mid p16-set-mid) (defun p16-set-mid (v x) (setf (aref v 1) x) x) (let ((v (vector 1 2 3))) (setf (p16-mid v) 'm) v))", "#(1 M 3)" },
    .{ "(progn (defun p16-acc (l) (car l)) (defsetf p16-acc (l) (new) `(progn (rplaca ,l ,new) ,new)) (let ((l (list 1))) (list (setf (p16-acc l) 9) l)))", "(9 (9))" },
    .{ "(let ((l (list 1 2 3))) (setf (car l) 'a (cadr l) 'b) l)", "(A B 3)" },
    .{ "(equal '(1 (2 \"a\")) (list 1 (list 2 \"a\")))", "T" },
    .{ "(equal \"abc\" \"ABC\")", "NIL" },
    .{ "(equal 1.0 1.0)", "T" },
    .{ "(equal #(1) #(1))", "NIL" },
    .{ "(let ((x (list 1 2))) (rplaca x 'a) (rplacd x '(b)) x)", "(A B)" },
    .{ "(list (nth 0 '(a b)) (nth 5 '(a b)) (nthcdr 1 '(a b c)) (caddr '(1 2 3)) (cddr '(1 2 3)) (third '(1 2 3)) (tenth '(1 2 3 4 5 6 7 8 9 10)))", "(A NIL (B C) 3 (3) 3 10)" },
    .{ "(list (length '(1 2 3)) (length #(1 2)) (length \"abcd\") (length nil))", "(3 2 4 0)" },
    .{ "(list (vectorp #(1)) (vectorp \"s\") (vectorp '(1)) (arrayp #(1)) (simple-vector-p #(1)) (simple-vector-p \"s\"))", "(T T NIL T T NIL)" },
    .{ "(let ((x 1)) (incf x) (incf x 10) x)", "12" },
};

test "setf, places, hash tables and arrays like SBCL 2.6.7 (Phase 16)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for (setf_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = true;
    for (setf_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = false;
    // 1000 個の項目（作り直しを含む）。SBCL 2.6.7：(1000 998001 250000)
    try expectValue(&e,
        \\(let ((h (make-hash-table)))
        \\  (labels ((fill-table (i) (if (< i 1000) (progn (setf (gethash i h) (* i i)) (fill-table (+ i 1))) nil)))
        \\    (fill-table 0))
        \\  (list (hash-table-count h) (gethash 999 h) (gethash 500 h)))
    , "(1000 998001 250000)");
    // 削除と追加を繰り返しても、表は正しい（削除した枠の作り直し）
    try expectValue(&e,
        \\(let ((h (make-hash-table :test 'equal)))
        \\  (labels ((churn (i) (if (< i 2000) (progn (setf (gethash (list i) h) i) (remhash (list (- i 1)) h) (churn (+ i 1))) nil)))
        \\    (churn 0))
        \\  (list (hash-table-count h) (gethash (list 1999) h) (gethash (list 5) h)))
    , "(1 1999 NIL)");
    // SBCL 2.6.7 でエラーになるもの
    try expectError(&e, "(setf (car 1) 2)", .type_error);
    try expectError(&e, "(let ((v (vector 1 2))) (setf (aref v 5) 0))", .type_error);
    try expectError(&e, "(gethash 1 2)", .type_error);
    try expectError(&e, "(make-hash-table :test 'foo)", .simple_error);
    try expectError(&e, "(setf x)", .program_error);
    try expectError(&e, "(let ((x (list 1))) (setf (p16-undefined-place x) 1))", .undefined_function);
    // 未実装（Phase 21）
    try expectError(&e, "(make-hash-table :test 'equalp)", .unimplemented);
    try expectError(&e, "(make-array '(2 3))", .unimplemented);
    try expectError(&e, "(make-array 3 :fill-pointer 0)", .unimplemented);
    // CL の関数の setf 関数は定義できない
    try expectError(&e, "(defun (setf car) (v x) v)", .package_error);
}

/// Phase 17：多値と &optional・&rest・&key（SBCL 2.6.7 の結果）
const mv_cases = [_][2][]const u8{
    .{ "(multiple-value-list (values 1 2 3))", "(1 2 3)" },
    .{ "(multiple-value-list (values))", "NIL" },
    .{ "(multiple-value-list 1)", "(1)" },
    .{ "(multiple-value-list (car '(1)))", "(1)" },
    .{ "(multiple-value-list (gethash 'x (make-hash-table)))", "(NIL NIL)" },
    .{ "(multiple-value-list (if t (values 1 2) 3))", "(1 2)" },
    .{ "(multiple-value-list (if nil (values 1 2) 3))", "(3)" },
    .{ "(multiple-value-list (progn 1 (values 2 3)))", "(2 3)" },
    .{ "(multiple-value-list (let ((x 1)) (values x 2)))", "(1 2)" },
    .{ "(progn (defun p17-two () (values 1 2)) (multiple-value-list (p17-two)))", "(1 2)" },
    .{ "(progn (defun p17-two () (values 1 2)) (defun p17-pass () (p17-two)) (multiple-value-list (p17-pass)))", "(1 2)" },
    .{ "(progn (defun p17-two () (values 1 2)) (defun p17-notail () (let ((r (p17-two))) r)) (multiple-value-list (p17-notail)))", "(1)" },
    .{ "(progn (defun p17-two () (values 1 2)) (list (multiple-value-list (funcall #'p17-two)) (multiple-value-list (apply #'p17-two nil))))", "((1 2) (1 2))" },
    .{ "(multiple-value-bind (a b c) (values 1 2) (list a b c))", "(1 2 NIL)" },
    .{ "(multiple-value-bind (a) (values 1 2) a)", "1" },
    .{ "(multiple-value-bind () (values 1 2) 'none)", "NONE" },
    .{ "(progn (defvar *p17-s* 0) (defun p17-gs () *p17-s*) (multiple-value-bind (*p17-s* b) (values 5 6) (list (p17-gs) b)))", "(5 6)" },
    .{ "(multiple-value-list (multiple-value-prog1 (values 1 2) 3))", "(1 2)" },
    .{ "(multiple-value-prog1 1 2)", "1" },
    .{ "(multiple-value-call #'list (values 1 2) 3 (values))", "(1 2 3)" },
    .{ "(multiple-value-call #'+ (values 1 2) (values 3 4))", "10" },
    .{ "(nth-value 1 (values 'a 'b))", "B" },
    .{ "(nth-value 5 (values 'a 'b))", "NIL" },
    .{ "(let ((x 0) (y 0)) (list (multiple-value-setq (x y) (values 1 2)) x y))", "(1 1 2)" },
    .{ "(multiple-value-list (values-list '(1 2 3)))", "(1 2 3)" },
    .{ "(multiple-value-list (values-list nil))", "NIL" },
    .{ "(+ (values 1 2) 3)", "4" },
    .{ "(list (values 1 2) (values))", "(1 NIL)" },
    .{ "(let ((x 0)) (multiple-value-list (setq x (values 1 2))))", "(1)" },
    .{ "(flet ((f () (values 'a 'b))) (multiple-value-list (f)))", "(A B)" },
    .{ "(labels ((f (n) (if (= n 0) (values 'done n) (f (- n 1))))) (multiple-value-list (f 3)))", "(DONE 0)" },
    .{ "(multiple-value-list (funcall (lambda () (values 1 2 3))))", "(1 2 3)" },
    .{ "(length (multiple-value-list (get-setf-expansion 'x)))", "5" },
    .{ "(multiple-value-bind (temps vals stores store access) (get-setf-expansion '(car x)) (list (length temps) vals (length stores) (consp store) (consp access)))", "(1 (X) 1 T T)" },
    .{ "(progn (define-setf-expander p17-hd (x) (let ((tmp (gensym)) (s (gensym))) (values (list tmp) (list x) (list s) `(progn (rplaca ,tmp ,s) ,s) `(car ,tmp)))) (let ((l (list 1 2))) (setf (p17-hd l) 'z) l))", "(Z 2)" },
    .{ "(progn (defun p17-f (a &optional b (c 3) (d 4 d-p)) (list a b c d d-p)) (list (p17-f 1) (p17-f 1 2 30 40)))", "((1 NIL 3 4 NIL) (1 2 30 40 T))" },
    .{ "(progn (defun p17-g (a &rest r) (list a r)) (list (p17-g 1) (p17-g 1 2 3)))", "((1 NIL) (1 (2 3)))" },
    .{ "(progn (defun p17-h (&key a (b 2) ((:cee c) 3) (d nil d-p)) (list a b c d d-p)) (list (p17-h) (p17-h :a 1 :cee 5 :d nil)))", "((NIL 2 3 NIL NIL) (1 2 5 NIL T))" },
    .{ "(progn (defun p17-k (&key a &allow-other-keys) a) (p17-k :b 1 :a 2))", "2" },
    .{ "(progn (defun p17-h2 (&key a) a) (p17-h2 :allow-other-keys t :zz 1))", "NIL" },
    .{ "(progn (defun p17-rk (&rest all &key a) (list all a)) (p17-rk :a 1))", "((:A 1) 1)" },
    .{ "(progn (defun p17-ax (a &aux (b (* a 2))) b) (p17-ax 5))", "10" },
    .{ "(progn (defun p17-od (a &optional (b (+ a 1))) b) (list (p17-od 1) (p17-od 1 10)))", "(2 10)" },
    .{ "((lambda (&optional (x 5)) x))", "5" },
    .{ "(progn (defun p17-h3 (&key a (b 2)) (list a b)) (apply #'p17-h3 '(:a 9)))", "(9 2)" },
    .{ "(flet ((sum (&rest xs) (apply #'+ xs))) (sum 1 2 3))", "6" },
    .{ "(progn (defvar *p17-ov* 'global) (defun p17-get-ov () *p17-ov*) (defun p17-op (&optional (*p17-ov* 'bound)) (p17-get-ov)) (list (p17-op) (p17-op 'given) *p17-ov*))", "(BOUND GIVEN GLOBAL)" },
    .{ "(progn (defun p17-kk (&key (x 1 x-p)) (list x x-p)) (list (p17-kk) (p17-kk :x 1)))", "((1 NIL) (1 T))" },
    .{ "(progn (defun p17-dup (&key a) a) (p17-dup :a 1 :a 2))", "1" },
    .{ "(multiple-value-bind (q r) (values 7 1) (+ q r))", "8" },
};

test "multiple values and lambda list keywords like SBCL 2.6.7 (Phase 17)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for (mv_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = true;
    for (mv_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = false;
    // SBCL 2.6.7 で program-error になるもの
    for ([_][]const u8{
        "(progn (defun p17-f2 (a &optional b) (list a b)) (p17-f2))",
        "(p17-f2 1 2 3)",
        "(progn (defun p17-g2 (a &rest r) (list a r)) (p17-g2))",
        "(progn (defun p17-h4 (&key a) a) (p17-h4 :z 1))",
        "(p17-h4 :a)",
        "(progn (defun p17-sq (x) (* x x)) (p17-sq 1 2))",
        "(lambda (a &whole w) a)",
    }) |t| try expectError(&e, t, .program_error);
    // 値の個数は呼び出しをまたいで伝わり、使い終わった多値は残らない
    try expectValue(&e, "(progn (defun p17-v3 () (values 1 2 3)) (multiple-value-list (let ((x (p17-v3))) x)))", "(1)");
    try expectValue(&e, "(multiple-value-list (maphash (lambda (k v) (values k v)) (let ((h (make-hash-table))) (setf (gethash 1 h) 2) h)))", "(NIL)");
    // 引数の多い呼び出し（&rest に 1000 個）
}

/// Phase 18：block・return-from・catch・throw・unwind-protect（SBCL 2.6.7 の結果）
const exit_cases = [_][2][]const u8{
    .{ "(block b 1 2)", "2" },
    .{ "(block b 1 (return-from b 10) 2)", "10" },
    .{ "(block nil (return 5) 6)", "5" },
    .{ "(block b (return-from b))", "NIL" },
    .{ "(multiple-value-list (block b (return-from b (values 1 2)) 3))", "(1 2)" },
    .{ "(multiple-value-list (block b (values 3 4)))", "(3 4)" },
    .{ "(block outer (block inner (return-from outer 'o)) 'after)", "O" },
    .{ "(block b (let ((x 1)) (if (= x 1) (return-from b 'one) 'other)))", "ONE" },
    .{ "(+ 1 (block b (+ 10 (return-from b 100))))", "101" },
    .{ "(progn (defun p18-find (x l) (if (null l) nil (if (eql (car l) x) (return-from p18-find 'found) (p18-find x (cdr l))))) (list (p18-find 2 '(1 2 3)) (p18-find 9 '(1 2 3))))", "(FOUND NIL)" },
    .{ "(progn (defun p18-first-neg (l) (mapcar-dummy)) 1)", "1" },
    .{ "(block b (funcall (lambda () (return-from b 'from-closure))) 'not-here)", "FROM-CLOSURE" },
    .{ "(progn (defun p18-call (f) (funcall f)) (block b (p18-call (lambda () (return-from b 'deep))) 'nope))", "DEEP" },
    .{ "(flet ((f (x) (if x (return-from f 'early) 'late))) (list (f t) (f nil)))", "(EARLY LATE)" },
    .{ "(labels ((f (n) (if (= n 0) (return-from f 'zero) (f (- n 1))))) (f 5))", "ZERO" },
    .{ "(catch 'tag (throw 'tag 1) 2)", "1" },
    .{ "(catch 'tag 1 2)", "2" },
    .{ "(multiple-value-list (catch 'tag (throw 'tag (values 1 2))))", "(1 2)" },
    .{ "(progn (defun p18-thrower () (throw 'done 'thrown)) (catch 'done (p18-thrower) 'not))", "THROWN" },
    .{ "(catch 'outer (catch 'inner (throw 'outer 'o)) 'after)", "O" },
    .{ "(catch 'a (catch 'b (throw 'a 1)) 2)", "1" },
    .{ "(let ((tag (list 'x))) (catch tag (throw tag 'dynamic-tag)))", "DYNAMIC-TAG" },
    .{ "(let ((log nil)) (list (unwind-protect 1 (setq log 'cleaned)) log))", "(1 CLEANED)" },
    .{ "(let ((log nil)) (list (block b (unwind-protect (return-from b 'exit) (setq log 'cleaned))) log))", "(EXIT CLEANED)" },
    .{ "(let ((log nil)) (list (catch 'c (unwind-protect (throw 'c 'thrown) (push 'cleanup log))) log))", "(THROWN (CLEANUP))" },
    .{ "(let ((log nil)) (catch 'c (unwind-protect (unwind-protect (throw 'c 1) (push 'inner log)) (push 'outer log))) log)", "(OUTER INNER)" },
    .{ "(multiple-value-list (unwind-protect (values 1 2) 'cleanup))", "(1 2)" },
    .{ "(let ((log nil)) (block b (unwind-protect (return-from b 1) (push 'x log) (values 9 9))) log)", "(X)" },
    .{ "(progn (defvar *p18-v* 'global) (list (block b (let ((*p18-v* 'bound)) (return-from b *p18-v*))) *p18-v*))", "(BOUND GLOBAL)" },
    .{ "(progn (defvar *p18-v* 'global) (list (catch 'c (let ((*p18-v* 'bound)) (throw 'c *p18-v*))) *p18-v*))", "(BOUND GLOBAL)" },
    .{ "(progn (defvar *p18-v* 'global) (let ((seen nil)) (catch 'c (let ((*p18-v* 'bound)) (unwind-protect (throw 'c 1) (setq seen *p18-v*)))) (list seen *p18-v*)))", "(BOUND GLOBAL)" },
    .{ "(let ((log nil)) (catch 'outer (unwind-protect (catch 'inner (unwind-protect (throw 'outer 1) (push 'a log))) (push 'b log))) log)", "(B A)" },
    .{ "(let ((x 0)) (catch 'c (unwind-protect (throw 'c 1) (catch 'c2 (throw 'c2 2)) (setq x 'ran))) x)", "RAN" },
    .{ "(block b (unwind-protect (return-from b 'first) (return-from b 'second)))", "SECOND" },
    .{ "(block nil (let ((i 0)) (labels ((lp () (if (= i 3) (return i) (progn (setq i (+ i 1)) (lp))))) (lp))))", "3" },
    .{ "(block a (block b (funcall (lambda () (return-from b 1))) (return-from a 2)))", "1" },
    .{ "(multiple-value-list (block b (funcall (lambda () (return-from b (values 1 2 3))))))", "(1 2 3)" },
    .{ "(multiple-value-list (unwind-protect (values 1 2) (values 3 4 5)))", "(1 2)" },
    .{ "(block b (apply (lambda () (return-from b 'x)) nil))", "X" },
    .{ "(catch 'c (apply (lambda (x y) (throw 'c (+ x y))) '(1 2)))", "3" },
    .{ "(progn (defvar *p18-z* 0) (let ((seen nil)) (catch 'c (let ((*p18-z* 1)) (unwind-protect (let ((*p18-z* 2)) (throw 'c 0)) (setq seen *p18-z*)))) (list seen *p18-z*)))", "(1 0)" },
    .{ "(progn (defun p18-deep (n) (if (= n 0) (throw 'p18-bottom 'hit) (p18-deep (- n 1)))) (catch 'p18-bottom (p18-deep 10000)))", "HIT" },
    .{ "(let ((n 0) (flag nil)) (labels ((f (i) (if (< i 1000) (progn (block x (catch 'y (unwind-protect (if (setq flag (not flag)) (return-from x) (throw 'y 1)) (setq n (+ n 1))))) (f (+ i 1)))))) (f 0)) n)", "1000" },
    .{ "(let ((x (block b (unwind-protect 1 (return-from b 2))))) x)", "2" },
    .{ "(catch 'a (catch 'b (unwind-protect (throw 'a 1) (throw 'b 2))) 3)", "3" },
    .{ "(let ((log nil)) (block b (unwind-protect (unwind-protect (return-from b 1) (push 1 log)) (push 2 log))) log)", "(2 1)" },
    .{ "(multiple-value-list (catch 'c (unwind-protect (throw 'c (values 1 2)) (values 7 8 9))))", "(1 2)" },
    .{ "(funcall (block b (lambda () 1)))", "1" },
    .{ "(block b (flet ((f () (return-from b 'out))) (f) 'no))", "OUT" },
    .{ "(progn (defun p18-r (x) (return-from p18-r (* x 2)) 0) (p18-r 21))", "42" },
    .{ "(progn (defun p18-opt (&optional (y 5)) (if (> y 3) (return-from p18-opt 'big)) 'small) (list (p18-opt) (p18-opt 1)))", "(BIG SMALL)" },
    .{ "(progn (defun (setf p18-place) (v x) (return-from p18-place (list v x))) (setf (p18-place 1) 2))", "(2 1)" },
    .{ "(block nil (return (values 1 2)))", "1" },
    .{ "(multiple-value-list (block nil (return (values 1 2))))", "(1 2)" },
    .{ "(block b (let ((f (lambda (x) (return-from b x)))) (+ 1 (funcall f 10))))", "10" },
    .{ "(catch 'c (catch 'c (throw 'c 1)) 2)", "2" },
    .{ "(let ((i 0)) (block b (labels ((lp () (setq i (+ i 1)) (if (> i 5) (return-from b i)) (lp))) (lp))))", "6" },
    .{ "(progn (defvar *p18-q* 'top) (block b (let ((*p18-q* 'mid)) (funcall (lambda () (let ((*p18-q* 'in)) (return-from b *p18-q*)))))))", "IN" },
    .{ "(progn (defvar *p18-q* 'top) (block b (let ((*p18-q* 'mid)) (funcall (lambda () (let ((*p18-q* 'in)) (return-from b *p18-q*)))))) *p18-q*)", "TOP" },
    .{ "(unwind-protect 'a)", "A" },
    .{ "(catch 'c)", "NIL" },
    .{ "(block b)", "NIL" },
    .{ "(+ (catch 'c (throw 'c 1)) (catch 'c 2))", "3" },
};

/// 脱出の後で、制御スタック・処理途中の脱出・動的束縛が、トップレベルの深さに戻っていること
fn expectClean(e: *Env, text: []const u8) !void {
    testing.expect(e.th.control_depth == 0 and e.th.unwind_depth == 0 and e.th.binding_depth == 0) catch |err| {
        std.debug.print("input: {s}\ncontrol {d} unwinds {d} bindings {d}\n", .{ text, e.th.control_depth, e.th.unwind_depth, e.th.binding_depth });
        return err;
    };
}

test "block, return-from, catch, throw and unwind-protect like SBCL 2.6.7 (Phase 18)" {
    var e: Env = undefined;
    try e.init();
    defer e.deinit();
    for (exit_cases) |c| {
        try expectValue(&e, c[0], c[1]);
        try expectClean(&e, c[0]);
    }
    e.rt.heap.stress = true;
    for (exit_cases) |c| try expectValue(&e, c[0], c[1]);
    e.rt.heap.stress = false;
    // ジャンプで抜ける return-from が、横切るエントリ（catch、エントリのある block）を取り除く
    try expectValue(&e, "(block a (block b (if nil (funcall (lambda () (return-from b 1)))) (return-from a 2)))", "2");
    try expectClean(&e, "crossing block");
    try expectValue(&e, "(block a (catch 'c (catch 'd (return-from a 'out))))", "OUT");
    try expectClean(&e, "crossing catch");
    try expectError(&e, "(progn (block b (catch 'c (return-from b 1))) (throw 'c 2))", .control_error);
    // SBCL 2.6.7 でエラーになるもの
    try expectError(&e, "(progn (defun p18-mk2 () (block b (lambda () (return-from b 1)))) (funcall (p18-mk2)))", .control_error);
    try expectError(&e, "(throw 'p18-nosuch 1)", .control_error);
    try expectError(&e, "(return-from p18-nosuch 1)", .program_error);
    try expectError(&e, "(block b (return-from b 1 2))", .program_error);
    try expectError(&e, "(catch)", .program_error);
    try expectError(&e, "(throw 'a)", .program_error);
    try expectError(&e, "(block 1)", .program_error);
    try expectError(&e, "(unwind-protect)", .program_error);
    try expectError(&e, "(return 1 2)", .program_error);
    // エラーで抜けるときも cleanup を実行する（cleanup の動的環境は unwind-protect に入った時点のもの）
    try expectError(&e, "(progn (defvar *p18-cl* nil) (defvar *p18-env* 'outer) (let ((*p18-env* 'mid)) (unwind-protect (let ((*p18-env* 'inner)) (car 1)) (setq *p18-cl* *p18-env*))))", .type_error);
    try expectValue(&e, "(list *p18-cl* *p18-env*)", "(MID OUTER)");
    // cleanup の中の catch で受け止める脱出は、進行中のエラーを取り消さない
    try expectError(&e, "(unwind-protect (car 1) (catch 'x (throw 'x 1)) (setq *p18-cl* 'after))", .type_error);
    try expectValue(&e, "*p18-cl*", "AFTER");
    // cleanup の外へ出る脱出は、進行中のエラーを取り消す
    try expectValue(&e, "(block b (unwind-protect (car 1) (return-from b 'replaced)))", "REPLACED");
    try expectClean(&e, "replaced error");
    try expectValue(&e, "(catch 'c (unwind-protect (car 1) (throw 'c 'thrown)))", "THROWN");
    try expectClean(&e, "replaced error by throw");
    // 深い再帰の途中からの脱出と、何度も繰り返す脱出で、エントリが残らない
    try expectValue(&e, "(progn (defun p18-down (n) (if (= n 0) (throw 'p18-done n) (unwind-protect (p18-down (- n 1)) (setq *p18-cl* n)))) (list (catch 'p18-done (p18-down 500)) *p18-cl*))", "(0 500)");
    try expectClean(&e, "deep");
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
        .{ "(loop)", .unimplemented },
        .{ "(quote)", .program_error },
        .{ "(if)", .program_error },
        .{ "(let ((t 1)) t)", .program_error },
        .{ "(let ((x 1) (x 2)) x)", .program_error },
        .{ "(setq t 1)", .program_error },
        .{ "(setq :k 1)", .program_error },
        .{ "(setq x)", .program_error },
        .{ "(progv '(1) '(2) 3)", .type_error },
        .{ "(defvar)", .program_error },
        .{ "((lambda (&optional) 1) 2)", .program_error },
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
