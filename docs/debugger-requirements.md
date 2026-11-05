# Zilisp debugger requirements

[日本語](debugger-requirements.ja.md)

| Item | Content |
|---|---|
| Version | 1.1 (2026-11-05; applies the 17 points of the Codex review of 1.0) |
| tque | #351 (D1 survey, D2 constraints, D3 comparison, D4 decisions; D5 applies them to the design and implements stage 1) |
| Parent documents | `docs/Zilisp_企画・基本設計書_v0.3.md` §9, `docs/Zilisp_Detailed_Design_v0.2.md` §9.4 |

## 1. Goals

1. Learners can debug at the REPL with the same flow as SBCL (operations as described in Levels 13 and 14 of the curriculum).
2. External debugging tools, including GUI tools, can debug Zilisp programs.
3. Agents (Claude Code, Codex and the like) can debug Zilisp programs.
4. Goals 1 to 3 are built on one mechanism (the debugger core). What each front end can do is given in the table of §3.8.

**Priorities** (decided by Lemon on 2026-11-05): goals 2 and 3 come first with equal weight; goal 1 comes later. The agent side (goal 3), which is easier to build, comes first (§5).

## 2. Assumptions and constraints

- Handlers and `invoke-debugger` run before unwinding, at the point of the error (Phase 25). The debugger can run there too, without unwinding.
- However, errors found in Zig (such as the type error of `car`) that no handler takes do not go through `invoke-debugger` (`zl-sys::%signal-zig-error` calls `*debugger-hook*` directly, and if nothing takes the error, the Zig side returns to the top level). C1 makes one entry point into the debugger.
- The VM's `run` runs cleanups and restores frames and bindings when it receives `Value.unwind`. To keep a stopped state, requests must be handled at the point before unwinding (C15).
- There is no place in the middle of VM instruction execution to receive requests or check time (C16 adds them).
- VM frames hold the closure, ip and base, and the values of the required arguments can be read. `Frame.ip` is the "next instruction" while the frame is calling another function, not necessarily the current position. There are no names, scopes or storage (local slot, captured slot, cell) of local variables and no mapping from ip to source position (the compiler adds them; C4).
- `eval` takes no frame environment (C5 adds it).
- Native code does not record frames. Zig has no equivalent of C's `#line` (proposal ziglang/zig#1833 was closed as not planned on 2026-04-21).
- Single-threaded. No sockets yet (Phase 31). No CLOS yet (Phases 27-29).
- The standard streams `*query-io*`, `*debug-io*` and `*terminal-io*` are currently connected to standard input and output (C17 separates them from the communication channel).
- Startup time is 12.72 ms (2026-11-05, the contents of `5214e36`; the two-stage build is brought forward if it exceeds 20 ms; detailed design §11.2).

## 3. Functional requirements

### 3.1 Debugger core (used by every front end)

| No. | Requirement |
|---|---|
| C1 | **Triggers and entry point**: the debugger stops only in these cases: (a) errors no handler takes (`error`, `cerror`, errors found in Zig), (b) direct calls of `invoke-debugger`, (c) `break`, (d) before signaling a condition that matches `*break-on-signals*`, (e) breakpoints, (f) stepping. An unhandled `signal` returns NIL without stopping, and `warn` writes the warning and continues (CLHS). All of (a)-(f) go through one entry point of the core, separate from the user's `*debugger-hook*`. For (a) and (b), `*debugger-hook*` is called first (with it bound to NIL; CLHS `invoke-debugger`). For (c), `break` binds `*debugger-hook*` to NIL before calling the entry point (CLHS `break`). During startup (while loading the standard library) and on stack exhaustion (`th.stackExhausted`) the debugger does not stop; control returns to the top level as now |
| C2 | **Information when stopped**: the reason (one of (a)-(f) of C1), the condition (type, report), available restarts (number, name, report), the stop location |
| C3 | **Frame list**: function name, argument values, source position (file, line, column, when known). Internal frames of the standard library can be hidden. The position of the top frame is the instruction where it stopped; those of lower frames are their call instructions |
| C4 | **Frame variables**: names and values of arguments and local variables. For each variable the compiler keeps its name, scope (ip range) and storage (local slot, captured slot, cell). Variables with the same name are told apart by scope. Values can be inspected. Values that cannot be obtained (low debug, out of scope, removed by optimization) are shown as unavailable |
| C5 | **Evaluation in a frame**: evaluating forms that use the frame's local variables. The dynamic environment (special variables, `*package*`) is the one at the stop. `setq` of a local variable takes effect in the original frame (it writes the local slot or cell). Multiple values are returned. An error during the evaluation becomes a nested stop (C7). Whether local functions (`flet`, `labels`) are visible is decided per debug level and documented |
| C6 | **Choosing restarts** by number or name. Arguments can be given in the request. For a restart with `:interactive` and no arguments given, the REPL asks interactively, and the communication front ends (MCP, DAP, batch) refuse with "arguments required" (they do not read input on their own). If the restart function returns normally (without a non-local exit), its values are returned as the result and the session stays stopped (CLHS `invoke-restart`) |
| C7 | **Leaving and nesting**: up one level (abort), back to the top level, nested stops (showing the depth). Leaving runs each `unwind-protect` cleanup exactly once |
| C8 | **Stepping**: into, over, out, continue, stop. Only code compiled for debugging (as in SBCL and Allegro; CLHS leaves the scope of step implementation-defined) |
| C9 | **Breakpoints**: function entry, source line. Conditional (optional; the condition is a Lisp form, so it needs the evaluation permission; P2) |
| C10 | **Returning a value from a frame** (return), **restarting a frame** (restart-frame). Optional |
| C11 | `trace` and `untrace` (CLHS) |
| C12 | `describe`, `inspect`, `apropos`, `documentation` (CLHS; curriculum Level 14 §2). `describe-object` after CLOS |
| C13 | **Display limits**: displays made by the debugger (printed values, reports, lists) have limits on depth, number of items, string length, total response bytes and the time to make a report. Default values are decided at implementation time, documented, and can be changed per request. Omitted items are shown with their count when it is known, otherwise as "omitted" |
| C14 | **Amount of debug information**: `(declare (optimize (debug n)))` and `declaim`. For each debug level, what is kept (what C3-C5, C8 and C9 can use) is defined and documented |
| C15 | **Stopped state**: a session is "running", "stopped" or "terminated". When it stops, it does not unwind; it waits for the next request at the stop point (inside the core's entry point; nested request handling). The requests accepted while stopped (information, evaluation, restarts, leaving, resuming) and those that are not are defined. The "response" to an evaluation request and the "completion" of the evaluation are distinct: if the evaluation stops partway, the response says "stopped" with the stop information, and the evaluation stays suspended |
| C16 | **Interrupting a running program**: at safe points of the VM (function calls and backward branches of loops), an interrupt flag and the time limit are checked. The communication front ends check their input without blocking at safe points (at a reduced rate). An interrupt (pause) and exceeding the time limit "stop" the program (C15; it can be resumed). A cancellation ends the request with abort. While a Zig primitive runs, while waiting for input, during GC and during a cleanup, it is delayed to the next safe point (an estimate of the maximum delay is documented) |
| C17 | **Separating input and output**: when a communication front end (MCP, DAP, batch) is used, the communication uses standard input and output and is kept separate from the Lisp program's input and output. The program's `*standard-input*` is empty (or contains what a request supplies); `*standard-output*`, `*error-output*`, `*trace-output*`, `*terminal-io*`, `*query-io*` and `*debug-io*` are captured and returned with the request results. The program never reads the communication input |
| C18 | **Identifiers and lifetimes**: sessions, stops (a generation number per stop), frames, restarts and inspected objects have identifiers. Frame and restart identifiers are valid only during their stop. Inspected objects are protected from GC until the stop ends or they are released explicitly. Old identifiers and identifiers of other stops are refused with a reason. If the communication is cut, the stopped evaluation is aborted (running cleanups) and the session ends |

### 3.2 REPL debugger (goal 1)

- R1: Based on SBCL 2.6.7's form (the entry message, prompts like `0]` with nesting, restart numbers and names, `UP`, `DOWN`, `FRAME`, `BACKTRACE`, `LIST-LOCALS`, `PRINT`, `SOURCE`, `STEP`, `NEXT`, `OUT`, `RETURN`, `TOPLEVEL`, `HELP`, and anything else is evaluated). The keyword forms common in other implementations (`:b`, `:c n`, `:a` and the like) are also accepted as aliases. The final command list is decided when this front end is built. The available commands depend on the stage of the core (§5).
- R2: Input comes from `*debug-io*` (sharing standard input with the REPL).
- R3: The interactive debugger is for VM execution only (native programs get error reports only, as N1; §6.5). By default, `--script` and running a file stay non-interactive as now (they write the report, the list of restarts and the call history, and exit with code 1, as SBCL's `--script` does). An option enters the debugger instead (the same idea as CLISP's `-on-error debug`; the option name is decided when this front end is built).

### 3.3 Non-interactive runs and machine-readable output (goal 3)

- B1: An option (provisionally `--error-format=json`) that writes conditions no handler takes as JSON: the reason, type, report, the list of restarts and the call history (function, arguments, position; local variables from stage 2, "unavailable" in stage 1), one JSON object per line (the same form as rustc's `--error-format=json`). It is a one-way report and has no interactive operations.
- B2: A batch debugger (provisionally `zilisp debug --batch`): when stopped, it runs the given commands in order and writes the results as JSON Lines (the same idea as gdb's `-batch`, lldb's `--batch` and pdb's `-c`).
- B3: Displays made by the debugger are the same every time for the same stopped state (no addresses or times; output written by the program itself is not covered). The limits are C13. Errors say which commands can be used next.

### 3.4 Debug Adapter Protocol (goal 2; GUI editors)

- D1: A DAP adapter over standard input and output (provisionally `zilisp --dap`). Target clients: VS Code, Visual Studio, Zed, Eclipse, Emacs, Neovim, IntelliJ (LSP4IJ). The clients actually tested are recorded separately (P4).
- D2: Initialization order: `initialize` (returning capabilities) → `launch` → `initialized` event → `setBreakpoints`, `setFunctionBreakpoints`, `setExceptionBreakpoints` → `configurationDone`. The capabilities correctly state what is supported (`supportsConfigurationDoneRequest`, `supportsExceptionInfoRequest`, `supportsFunctionBreakpoints`, exception filters and so on). `attach` is decided when this front end is built.
- D3: Minimum requests and events: the initialization requests above, `disconnect`, `threads` (one), `stackTrace`, `scopes`, `variables`, `continue`, `next`, `stepIn`, `stepOut`, `pause`, `evaluate`, `exceptionInfo`; events `initialized`, `stopped`, `output`, `terminated`, `exited`. Breakpoints report whether they could be set (verified). Lines and columns start at 1, and paths are absolute.
- D4: Conditions are reported with `stopped` (reason `exception`) and `exceptionInfo`. Choosing restarts is not part of standard DAP, so a Zilisp extension request is defined (using `evaluate` instead would need the evaluation permission, so the extension request is the primary way).
- D5: A launch configuration (extension) for VS Code and the like is needed separately. Where it is built is decided when this front end is built.

### 3.5 Swank (goal 2; SLIME; curriculum Level 14 §8)

- S1: A Swank backend for SLIME (the equivalent of `swank/zilisp.lisp`) with communication style `nil` (single-threaded; interrupts from SLIME cannot be received while an evaluation runs).
- S2: Prerequisites: TCP sockets (Phase 31), CLOS (Phases 27-29), Gray streams (built separately on CLOS), `:include` of `defstruct` (Phase 26), and C4, C5 and C8 of the core (stages 2 and 3).
- S3: The operations of SLIME's debugger (sldb) — backtrace, frame variables, evaluation in a frame, restarts, stepping — work on the core.
- S4: SLY (Slynk) and Lem (micros) use servers separate from Swank, so they are separate requirements decided later.

### 3.6 MCP server (goal 3)

- M1: An MCP server over standard input and output (provisionally `zilisp --mcp`) that can be registered with Claude Code (`claude mcp add`) and Codex (`config.toml`).
- M2: Tools (by stage):
  - M2a (stage 1): starting and ending a session, loading files and evaluating forms, the information when stopped (C2), the call history (functions and arguments), listing and choosing restarts (with arguments), abort and back to the top level, pause, getting output, `trace` and `untrace`
  - M2b (stage 2): frame variables, evaluation in a frame, inspect, macroexpand
  - M2c (stage 3): breakpoints, stepping
  - Operations that stop return the reason, the position, the top of the stack and (from stage 2) the variables in one response.
- M3: Results are returned as `structuredContent` and the same content as text. The limits are C13 (the default is well below Claude Code's default limit of 25,000 tokens). A call is stopped by a time limit shorter than Codex's default of 60 seconds (C16) and answered as "stopped". Cancellation is as in C16.
- M4: Input and output are as in C17 (standard output carries only MCP messages).
- M5: It uses the same internal API and the same JSON shapes as 3.3.

### 3.7 Native code

- N1: Error reports show the Lisp function names and positions (by recording frames or by a mapping table). The interactive debugger is not covered (§6.5).
- N2: Seeing Lisp source positions in gdb, lldb or Visual Studio is out of scope for now (if needed, it would use a table from generated Zig lines to Lisp positions and a relaying DAP adapter).

### 3.8 Core and front ends

○: a dedicated operation, △: partly (in parentheses), ×: none (out of scope), ―: does not apply to that front end. Stages are in §5.

| Core | REPL (R) | JSON output (B1) | Batch (B2) | MCP (M) | DAP (D) | Swank (S) |
|---|---|---|---|---|---|---|
| C1 triggers | ○ | △ (errors no handler takes only) | ○ | ○ | ○ | ○ |
| C2 information when stopped | ○ | ○ | ○ | ○ | ○ (exceptionInfo) | ○ |
| C3 frame list | ○ | ○ | ○ | ○ | ○ | ○ |
| C4 frame variables | ○ | ○ (stage 2) | ○ | ○ (M2b) | ○ | ○ |
| C5 evaluation in a frame | ○ | ― | ○ | ○ (M2b) | ○ (evaluate) | ○ |
| C6 restarts | ○ | △ (list only) | ○ | ○ | ○ (extension request) | ○ |
| C7 leaving and nesting | ○ | ― | ○ | ○ | △ (disconnect, extension) | ○ |
| C8 stepping | ○ | ― | ○ | ○ (M2c) | ○ | ○ |
| C9 breakpoints | ○ | ― | ○ | ○ (M2c) | ○ | ○ |
| C10 return, restart-frame | ○ | ― | ○ | × | △ (restartFrame) | ○ |
| C11 trace | ○ | ― | ○ | ○ | × | ○ |
| C12 describe, inspect | ○ | ― | ○ | ○ (M2b) | △ (expanding variables) | ○ |
| C16 interrupts | ○ (keyboard interrupt; to be considered) | ― | △ (time limit) | ○ | ○ (pause) | × (S1) |

## 4. Non-functional requirements

- P1: **Speed and startup time**: when the debugger is not used (the default), compared with the baseline commit (the commit just before a stage starts), startup time (ReleaseFast, x86_64-windows, median of 31 runs of `zilisp --eval nil`, the same method as the full verification script) grows by at most 0.5 ms, and each item of `zig build bench` slows by at most 3% (these tolerances are estimates, reviewed when a stage starts). This includes the cost of the safe-point checks of C16. If the Lisp part of the debugger is loaded only when needed, the time to the first stop and the behavior when loading fails are also measured and recorded. The startup time of MCP and DAP is recorded too.
- P2: **Safety** (when used by agents and external tools):
  - Permission levels: "read only", "execution control", "evaluation". A table of the permission each operation needs is written at implementation time. Every operation that runs Lisp code needs the "evaluation" permission: evaluating forms, evaluation in a frame, loading files, macroexpand (it runs macro functions), conditional breakpoints, restarts with `:interactive`, and conditions of `trace`.
  - Permissions are checked before reading (the reader) and macroexpansion. Reading with the "read only" permission sets `*read-eval*` to false and does not use user reader macros.
  - Displays with the "read only" permission use a safe form that does not call user code (condition reports, printing functions): the type and the slot values.
  - The evaluation permission is available only with an explicit startup flag (e.g. `--allow-eval`). The evaluation permission is not a restriction of OS resources (files, processes, network); the absence of such a restriction is documented.
  - The paths of files that can be loaded can be restricted.
  - Limits on time, allocation and output for each evaluation, and interruption (C16).
  - An audit log of the operations performed and summaries of their results. Values that look secret (environment variables and the like) are hidden by default.
  - When HTTP or TCP is added later, listen on 127.0.0.1 only and check a token and the Origin.
- P3: **Standards**: `invoke-debugger`, `*debugger-hook*`, `break`, `*break-on-signals*`, `step`, `trace`, `untrace`, `describe` and `inspect` follow CLHS. Implementation-defined parts (commands, display, the scope of step, the debug levels) are documented.
- P4: **Tests and acceptance** (per stage, within that stage's scope):
  - Correctness: stopping for each trigger of C1 (including cases that must not stop), evaluation at the stop point, choosing restarts (with arguments, with `:interactive`, restarts that return normally), nested stops, `unwind-protect` cleanups run exactly once, abort and back to the top level.
  - Stopped state: other requests while stopped, old identifiers and identifiers of other stops, invalid requests, the communication being cut.
  - Interrupts: pause and time limits on infinite loops and input waits, and the session still being usable afterwards.
  - Input and output: no Lisp output mixed into the communication, and the program never reading the communication input.
  - Safety: without the evaluation permission, no Lisp code runs through loading, macroexpand, `#.`, conditional breakpoints or `:interactive`.
  - Variables (from stage 2): captured variables, variables with the same name, multiple values, unavailable values, inspect after GC.
  - Agreement between front ends: for the same stop, each front end (within the table of §3.8) returns the same information.
  - Comparison with SBCL: textual agreement (the entry message, restart reports, the flow of `assert`) and agreement in CL meaning (which restarts are available, evaluation results) are compared separately.
  - DAP: of the target clients, the ones actually tested are recorded.

## 5. Stages (decided on 2026-11-05: 0.4 includes stage 1)

| Stage | Content | Prerequisites | Release |
|---|---|---|---|
| 1 | Core basics (C1 ((a)-(d)), C2, C3 (functions and arguments; positions as far as known), C6, C7, C11, C13, C15, C16, C17, C18), `break` and `*break-on-signals*` (#7 of the first Codex review of Phase 25), JSON output (B1; local variables "unavailable"), MCP (M1, M2a, M3-M5) | Phase 25; VM safe points (C16), separation of input and output (C17) | 0.4 |
| 2 | Local variables and source positions (positions of C3, C4, C5, C14; debug information from the compiler), batch debugger (B2, B3), MCP (M2b), local variables in B1 | Stage 1 | 0.5 |
| 3 | Breakpoints and stepping ((e) and (f) of C1, C8, C9, C10), DAP (D1-D5), MCP (M2c) | Stage 2 | 0.5 |
| 4 | Swank (S1-S3), full `describe` and `inspect` (C12) | Stages 2 and 3, CLOS (Phases 27-29), Gray streams, sockets (Phase 31), `defstruct :include` (Phase 26) | 0.5 |
| 5 | Native (N1) | Phase 36 | 0.7 |
| Later | REPL debugger (R1-R3); the available commands depend on the stage of the core at that time | The core (stage 1 or later) | Any time after stage 1 |

The releases for stage 2 and later are estimates and are reviewed before each stage starts.

## 6. Decisions (2026-11-05, Lemon)

1. Goals 2 and 3 come first with equal weight; goal 1 later.
2. The REPL commands are based on SBCL's form, with keyword forms accepted as aliases (the final list is decided when that front end is built).
3. Non-interactive runs stay non-interactive by default; an option enters the debugger.
4. Stepping and line breakpoints are in scope (stage 3).
5. Native support goes as far as names and positions in error reports (N1); integration with gdb and the like (N2) is out of scope for now.
6. 0.4 includes stage 1.
7. These requirements are kept in docs in English and Japanese.

## 7. Survey summary and sources (2026-11-05)

### 7.1 Debuggers of implementations

- All the implementations surveyed (SBCL, CCL, ECL, CLISP, LispWorks, Allegro) use a nested REPL (showing the depth), print the report and numbered restarts on entry, and evaluate input that is not a debugger command. The command style is keywords (`:b`, `:c n` and the like) in CCL, ECL, CLISP, LispWorks and Allegro, and non-keyword names (`BACKTRACE`, `UP` and the like) in SBCL.
- Leaving one level, returning to the top level, choosing restarts by number, the call history, moving between frames, local variables and returning from a frame exist in almost all the implementations surveyed.
- Local variables and source positions depend on information kept by the compiler (Allegro's debug 3, CCL's `*save-local-symbols*` and `*record-pc-mapping*`, LispWorks's `*source-level-debugging*`). In ECL and CLISP, bytecode frames carry more information.
- LispWorks has an official remote debugging facility over TCP (its format is not documented). Whether other implementations have a similar official facility was not found within this survey (unverified).
- The command list of SBCL 2.6.7 was checked by printing `sb-debug::*debug-commands*` and `sb-debug::*debug-help-string*` in the local SBCL (2026-11-05). The Windows SBCL did not read debugger commands given through a pipe, so the results of actually typing the commands were not checked (unverified).
- Sources: https://ccl.clozure.com/docs/ccl.html , https://ecl.common-lisp.dev/static/manual/The-interpreter.html , https://clisp.sourceforge.io/impnotes/repl.html , https://www.lispworks.com/documentation/lw80/lw/lw-debugger-ug.htm , https://franz.com/support/documentation/current/doc/debugging.htm , CLHS (https://www.lispworks.com/documentation/HyperSpec/Body/f_invoke.htm , f_break.htm, v_break_.htm, f_signal.htm, f_invo_1.htm, m_step.htm, m_tracec.htm)

### 7.2 External tools

- Swank: a 6-digit hex length followed by an S-expression, over TCP; with communication style `nil` it runs single-threaded. Swank itself uses CLOS (`defgeneric`, `defclass`) and Gray streams; the backend needs functions for frames, variables, evaluation and stepping. Besides SLIME, clients using Swank include Vlime and IntelliJ's SLT (experimental). SLY uses Slynk and Lem uses micros (both servers forked from Swank). https://github.com/slime/slime , https://slime.common-lisp.dev/doc/html/Communication-style.html , https://github.com/joaotavora/sly , https://github.com/lem-project/micros
- DAP: a `Content-Length` header and JSON; one session over standard input and output. The `initialized` event starts the configuration requests, and features without capabilities are not used. Choosing restarts is not standard. No DAP adapter for debugging Common Lisp code was found. VS Code's Alive supports SBCL only. https://microsoft.github.io/debug-adapter-protocol/overview.html , https://microsoft.github.io/debug-adapter-protocol/implementors/tools/ , https://github.com/nobody-famous/alive
- The GUI debuggers in the Lisp world (the LispWorks, Allegro and CCL IDEs) are specific to each implementation. McCLIM's debugger uses Swank.
- Zig and `#line`: https://github.com/ziglang/zig/issues/1833 (not planned, 2026-04-21). The discussion in the same issue mentions that Zebra, a language that compiles to Zig, maps back to original positions with line comments and a relaying DAP adapter (Zebra's implementation itself was not checked).

### 7.3 Agents

- MCP: standard input/output (JSON-RPC) and Streamable HTTP; results as `structuredContent` and text. Cancellation is a notification for a request identifier and can cross with completion. Claude Code (output limit 25,000 tokens by default) and Codex (60-second default call timeout). https://modelcontextprotocol.io/specification/2025-06-18/basic/transports , https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/cancellation , https://code.claude.com/docs/en/mcp , https://learn.chatgpt.com/docs/extend/mcp?surface=cli
- Existing MCP servers for debugging: mcp-debugger and go-delve's mcp-dap-server (wrapping DAP), cl-mcp (SBCL; no operation for choosing restarts was found). https://github.com/debugmcpdev/mcp-debugger , https://github.com/go-delve/mcp-dap-server , https://github.com/cxxxr/lisp-mcp-server
- Building tools for agents: small output, paging and truncation, meaningful names, errors that say how to fix them. https://www.anthropic.com/engineering/writing-tools-for-agents
- Safety: https://modelcontextprotocol.io/specification/2025-06-18/basic/security_best_practices

## 8. Revision history

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-11-05 | First version |
| 1.1 | 2026-11-05 | Applied the Codex review of 1.0 (17 points): triggers and a single entry point (C1); stopped state, interrupts, separation of input and output, identifiers (C15-C18); details of local variables and evaluation in a frame (C4, C5); restart arguments and restarts that return normally (C6); display limits (C13); fixed stage dependencies (§5); MCP tools split by stage (M2a-M2c); DAP initialization and capabilities (D2, D3); Swank separated from SLY and Lem (S4); the interactive debugger is for the VM only (R3); a table of the core and front ends (§3.8); concrete safety (P2), tests (P4) and performance (P1); corrected overstatements in the survey summary (§7) |
