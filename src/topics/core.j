# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualbox - core: the configuration, the host handle, the argument checks,
# running VBoxManage with a deadline, and its errors. Spliced into
# virtualbox.j via include.

/** How long an ordinary call may run, in milliseconds: one minute. */
export def const DEFAULT_TIMEOUT_MS as int init 60000;

/** How long an import, export, clone, snapshot or guest copy may run, in milliseconds: one hour. */
export def const DEFAULT_LONG_TIMEOUT_MS as int init 3600000;

/** The oldest VirtualBox major version `open` accepts. */
export def const MIN_MAJOR as int init 7;

# the longest argument the deck passes on
def const MAX_ARG as int init 4096;

# the longest machine, snapshot, controller or folder name
def const MAX_NAME as int init 255;

# control characters (C0, DEL, C1), which no argument holds
def const CONTROL as string init '[\x00-\x1f\x7f-\x9f]';

# what an error message never shows: control characters, and the bidi marks,
# embeddings, overrides and isolates that reorder a terminal line
def const UNSHOWN as string init '[\x00-\x1f\x7f-\x9f\x{200e}\x{200f}\x{202a}-\x{202e}\x{2066}-\x{2069}]';

# characters an argument may not hold over a command prefix: the remote login
# shell must be POSIX sh, where single quotes quote everything, but fish reads
# `\` inside them and csh `!`, so neither ever reaches a remote shell
def const REMOTE_UNSAFE as string init '[\\!]';

# the most output parsed from one call, in characters and in lines: a large
# host's `list hdds` is well under 1 MiB, a machine with 3000 snapshots under
# 10000 lines. Each parsed line costs the interpreter a few KiB, so the line
# cap bounds the parsers' memory at a few hundred MiB.
def const MAX_OUTPUT as int init 4194304;
def const MAX_LINES as int init 50000;

# the most error output read for the message
def const MAX_ERROR_OUTPUT as int init 65536;

# how long a VBoxManage told to stop at its deadline may take to stop: it
# catches SIGTERM during long operations and cancels them first
def const STOP_GRACE_MS as int init 5000;

/**
 * How to reach `VBoxManage`. Build it with `local` or `remote` and change it
 * with the `with*` functions.
 *
 * @field binary {string} the program, `"VBoxManage"` from `PATH` by default
 * @field prefix {list of string} a command `VBoxManage` runs under, such as `["ssh", "admin@host"]`; empty to run it here
 * @field timeoutMs {int} how long an ordinary call may run
 * @field longTimeoutMs {int} how long an import, export, clone, snapshot or guest copy may run
 */
export def struct Config {
    binary as string,
    prefix as list of string,
    timeoutMs as int,
    longTimeoutMs as int
};

/**
 * A VirtualBox installation that answered, from `open`. Every other call
 * takes one.
 *
 * @field config {Config} how it is reached
 * @field version {string} what `VBoxManage --version` printed, `7.1.4r165100`
 * @field major {int} the major version
 * @field minor {int} the minor version
 */
export def struct Host {
    config as Config,
    version as string,
    major as int,
    minor as int
};

/**
 * Throw a virtualbox error.
 *
 * @param message {string} what went wrong, without the `virtualbox: ` prefix
 * @throws {Error} kind "virtualbox", always
 */
func fail(message as string) {
    throw Error{kind: "virtualbox", message: "virtualbox: " + $message};
}

/**
 * Text quoted for an error message: at most 200 characters, control
 * characters and bidi controls as `?`.
 *
 * @param s {string} the text
 * @return {string} the text in double quotes
 */
func shown(s as string) {
    return "\"" + cleaned($s, 200) + "\"";
}

/**
 * Text cut to a length, with control characters and the bidi controls that
 * reorder a terminal line as `?`.
 *
 * @param s {string} the text
 * @param most {int} the longest result, before the `...`
 * @return {string} the cleaned text
 */
func cleaned(s as string, most as int) {
    def t as string init $s;
    if (len($t) > $most) {
        $t = strings.substring($t, 0, $most) + "...";
    }
    return regex.replace(UNSHOWN, $t, "?");
}

# --- configuration ---------------------------------------------------------

/**
 * Run `VBoxManage` from `PATH` on this machine.
 *
 * @return {Config} the configuration
 * @example
 *   def vb as virtualbox.Host init virtualbox.open(virtualbox.local());
 */
export func local() {
    return Config{
        binary: "VBoxManage",
        prefix: [],
        timeoutMs: DEFAULT_TIMEOUT_MS,
        longTimeoutMs: DEFAULT_LONG_TIMEOUT_MS
    };
}

/**
 * Run `VBoxManage` under a command prefix that hands one command line to a
 * remote shell: `ssh` to another machine. `ssh` joins its arguments into one
 * command for the remote user's login shell, so every argument after the
 * prefix is quoted for POSIX `sh`, and that login shell must be one (sh, bash,
 * dash, ksh, zsh; not fish, csh or a Windows shell). Arguments holding `\` or
 * `!` are refused over a prefix. A prefix without a shell (`sudo`, `env`)
 * would pass the quotes on literally: point `withBinary` at a wrapper script
 * instead. Use key authentication: the deck cannot answer a password prompt.
 *
 * @param prefix {list of string} the command, such as `["ssh", "-o", "BatchMode=yes", "admin@host"]`
 * @return {Config} the configuration
 * @throws {Error} kind "virtualbox" if the prefix is empty or an element is empty or holds a control character
 * @example
 *   def c as virtualbox.Config init virtualbox.remote(["ssh", "-o", "BatchMode=yes", "admin@vmhost"]);
 */
export func remote(prefix as list of string) {
    if (len($prefix) == 0) {
        fail("the command prefix is empty");
    }
    for (def part in $prefix) {
        checkText($part, "a prefix element");
    }
    if (strings.startsWith($prefix[0], "-")) {
        fail("the command prefix must start with a program, got " + shown($prefix[0]));
    }
    def c as Config init local();
    $c.prefix = $prefix;
    return $c;
}

/**
 * The configuration with another `VBoxManage` program.
 *
 * @param c {Config} the configuration
 * @param binary {string} the program: a name looked up in `PATH`, or a path
 * @return {Config} the changed copy
 * @throws {Error} kind "virtualbox" if it is empty, starts with `-`, holds `=` or a control character
 */
export func withBinary(c as Config, binary as string) {
    checkPath($binary, "the VBoxManage program");
    if (strings.contains($binary, "=")) {
        fail("the VBoxManage program must not hold =, which env reads as a variable, got " +
            shown($binary));
    }
    def out as Config init $c;
    $out.binary = $binary;
    return $out;
}

/**
 * The configuration with another deadline for ordinary calls.
 *
 * @param c {Config} the configuration
 * @param ms {int} milliseconds, 1 to 86400000
 * @return {Config} the changed copy
 * @throws {Error} kind "virtualbox" if it is out of range
 */
export func withTimeout(c as Config, ms as int) {
    checkRange($ms, 1, 86400000, "the timeout");
    def out as Config init $c;
    $out.timeoutMs = $ms;
    return $out;
}

/**
 * The configuration with another deadline for import, export, clone,
 * snapshots and guest copies.
 *
 * @param c {Config} the configuration
 * @param ms {int} milliseconds, 1 to 86400000
 * @return {Config} the changed copy
 * @throws {Error} kind "virtualbox" if it is out of range
 */
export func withLongTimeout(c as Config, ms as int) {
    checkRange($ms, 1, 86400000, "the long timeout");
    def out as Config init $c;
    $out.longTimeoutMs = $ms;
    return $out;
}

/**
 * Reach VirtualBox: run `VBoxManage --version` and refuse a version older
 * than `MIN_MAJOR`.
 *
 * @param c {Config} the configuration
 * @return {Host} the host, for every other call
 * @throws {Error} kind "virtualbox" if `VBoxManage` cannot run, fails, prints no version or is older than VirtualBox 7
 * @example
 *   def vb as virtualbox.Host init virtualbox.open(virtualbox.local());
 *   io.printf("VirtualBox %s\n", $vb.version);
 */
export func open(c as Config) {
    def r as os.Result init execute($c, ["--version"], $c.timeoutMs, "--version");
    if ($r.exitCode != 0) {
        failed("--version", $r);
    }
    def h as Host init hostFrom($c, $r.stdout);
    if ($h.major < MIN_MAJOR) {
        fail("VirtualBox " + $h.version + " is too old; the deck needs VirtualBox " +
            convert.toString(MIN_MAJOR) + " or newer");
    }
    return $h;
}

/**
 * The host a `--version` answer describes. The version is the last line that
 * starts with `major.minor.patch`: a missing kernel module prints a warning
 * first.
 *
 * @param c {Config} the configuration
 * @param out {string} what `VBoxManage --version` printed
 * @return {Host} the host
 * @throws {Error} kind "virtualbox" if no line holds a version
 */
func hostFrom(c as Config, out as string) {
    def h as Host init Host{config: $c, version: "", major: 0, minor: 0};
    for (def line in strings.split($out, "\n")) {
        def t as string init strings.trim($line);
        def m as regex.Match init regex.find('^([0-9]+)\.([0-9]+)\.[0-9]+', $t);
        if ($m.start == 0) {
            $h.version = $t;
            $h.major = convert.toInt($m.groups[0]);
            $h.minor = convert.toInt($m.groups[1]);
        }
    }
    if ($h.version == "") {
        fail("VBoxManage --version printed no version: " + shown(strings.trim($out)));
    }
    return $h;
}

# --- checks ----------------------------------------------------------------

/**
 * Refuse text that is empty, too long or holds a control character.
 *
 * @param value {string} the text
 * @param what {string} what it is, for the message
 * @throws {Error} kind "virtualbox" if it is unusable
 */
func checkText(value as string, what as string) {
    if ($value == "") {
        fail($what + " is empty");
    }
    if (len($value) > MAX_ARG) {
        fail($what + " is longer than " + convert.toString(MAX_ARG) + " characters");
    }
    if (regex.matches(CONTROL, $value)) {
        fail($what + " holds a control character: " + shown($value));
    }
}

/**
 * Refuse a path that is empty, holds a control character or starts with `-`,
 * which `VBoxManage` would read as an option.
 *
 * @param path {string} the path
 * @param what {string} what it is, for the message
 * @throws {Error} kind "virtualbox" if it is unusable
 */
func checkPath(path as string, what as string) {
    checkText($path, $what);
    if (strings.startsWith($path, "-")) {
        fail($what + " must not start with -, got " + shown($path) + " (write ./" +
            cleaned($path, 80) +
            ")");
    }
}

/**
 * Refuse a name for a machine, snapshot, controller, folder or rule that is
 * empty, longer than 255 characters, holds a control character or starts
 * with `-`.
 *
 * @param name {string} the name
 * @param what {string} what it is, for the message
 * @throws {Error} kind "virtualbox" if it is unusable
 */
func checkName(name as string, what as string) {
    checkText($name, $what);
    if (len($name) > MAX_NAME) {
        fail($what + " is longer than " + convert.toString(MAX_NAME) + " characters");
    }
    if (strings.startsWith($name, "-")) {
        fail($what + " must not start with -, got " + shown($name));
    }
}

/**
 * Refuse a machine reference: a name or a UUID, checked as a name.
 *
 * @param vm {string} the machine's name or UUID
 * @throws {Error} kind "virtualbox" if it is unusable
 */
func checkVm(vm as string) {
    checkName($vm, "the machine");
}

/**
 * Refuse a value that is not one of a fixed set.
 *
 * @param value {string} the value
 * @param choices {list of string} the accepted values
 * @param what {string} what it is, for the message
 * @throws {Error} kind "virtualbox" if it is not one of them
 */
func checkChoice(value as string, choices as list of string, what as string) {
    if (not lists.contains($choices, $value)) {
        fail($what + " must be one of " + strings.join($choices, ", ") + ", got " + shown($value));
    }
}

/**
 * Refuse a number out of range.
 *
 * @param n {int} the number
 * @param low {int} the smallest accepted
 * @param high {int} the largest accepted
 * @param what {string} what it is, for the message
 * @throws {Error} kind "virtualbox" if it is out of range
 */
func checkRange(n as int, low as int, high as int, what as string) {
    if ($n < $low or $n > $high) {
        fail($what + " must be " + convert.toString($low) + " to " + convert.toString($high) +
            ", got " +
            convert.toString($n));
    }
}

# --- running VBoxManage ----------------------------------------------------

/**
 * The command line: `env LC_ALL=C.UTF-8`, the program and its arguments;
 * under a prefix the prefix, then the same with every argument after
 * `LC_ALL=C.UTF-8` quoted for the remote `sh`. The C locale keeps
 * VBoxManage's output in English: 7.x translates it under some locales
 * (Russian), and the parsers read English labels. Plain `C` will not do:
 * VirtualBox's runtime then has no conversion for non-ASCII arguments and
 * VBoxManage stops with `RTR3Init: VERR_NO_TRANSLATION`.
 *
 * @param c {Config} the configuration
 * @param args {list of string} the arguments after the program
 * @return {list of string} the argument list for `os.spawn`
 */
func commandLine(c as Config, args as list of string) {
    def out as list of string init [];
    def quote as bool init len($c.prefix) > 0;
    for (def part in $c.prefix) {
        $out[] = $part;
    }
    $out[] = "env";
    $out[] = "LC_ALL=C.UTF-8";
    for (def a in lists.concat([$c.binary], $args)) {
        if ($quote) {
            $out[] = shellQuoted($a);
        } else {
            $out[] = $a;
        }
    }
    return $out;
}

/**
 * One argument quoted for a POSIX shell: in single quotes, each `'` written
 * as `'\''`.
 *
 * @param s {string} the argument
 * @return {string} the quoted argument
 */
func shellQuoted(s as string) {
    return "'" + strings.replace($s, "'", "'\\''") + "'";
}

/**
 * Run `VBoxManage` and wait for it. At the deadline it gets SIGTERM; it
 * catches that during long operations and cancels them first, so it is given
 * `STOP_GRACE_MS` more to stop before the call gives up and leaves it
 * running.
 *
 * @param c {Config} the configuration
 * @param args {list of string} the arguments after the program
 * @param timeoutMs {int} the deadline
 * @param what {string} the operation, for error messages
 * @return {os.Result} the exit code and output
 * @throws {Error} kind "virtualbox" if an argument cannot go through the prefix, it cannot start, runs too long or prints something that is not UTF-8
 */
func execute(c as Config, args as list of string, timeoutMs as int, what as string) {
    if (len($c.prefix) > 0) {
        for (def a in lists.concat([$c.binary], $args)) {
            if (regex.matches(REMOTE_UNSAFE, $a)) {
                fail("over a command prefix an argument may not hold \\ or !, got " + shown($a));
            }
        }
    }
    def argv as list of string init commandLine($c, $args);
    def p as os.Process;
    try {
        $p = os.spawn($argv);
    } catch (e) {
        fail("cannot run " + shown($argv[0]) + " (is VirtualBox installed?): " +
            cleaned($e.message, 200));
    }
    if (not finished($p, $timeoutMs)) {
        os.kill($p);
        def late as string init $what + ": no answer after " + convert.toString($timeoutMs) + " ms";
        if (not finished($p, STOP_GRACE_MS)) {
            fail($late + "; still running " + convert.toString(STOP_GRACE_MS) +
                " ms after SIGTERM, left running as pid " + convert.toString($p.pid));
        }
        try {
            os.wait($p);
        } catch (e) {
            $late = $late + " (its output was unreadable)";
        }
        os.release($p);
        fail($late + ", stopped");
    }
    def r as os.Result;
    try {
        $r = os.wait($p);
    } catch (e) {
        os.release($p);
        fail($what + ": unreadable output: " + cleaned($e.message, 200));
    }
    os.release($p);
    if ($r.exitCode == 127) {
        # env, or the remote shell, found no such program
        fail("cannot run " + shown($c.binary) + " (is VirtualBox installed?): " +
            explain($r.stderr)[0]);
    }
    return $r;
}

/**
 * Wait for a process to end, polling with a backoff from 1 to 64 ms.
 *
 * @param p {os.Process} the process
 * @param ms {int} how long to wait
 * @return {bool} whether it ended in time
 */
func finished(p as os.Process, ms as int) {
    def started as time.Time init time.now();
    def pause as int init 1;
    while (not os.poll($p)) {
        if (time.milliseconds(time.sub(time.now(), $started)) > $ms) {
            return false;
        }
        time.sleep(time.fromMilliseconds($pause));
        if ($pause < 64) {
            $pause = $pause * 2;
        }
    }
    return true;
}

/**
 * Run a `VBoxManage` command with the ordinary deadline and return what it
 * printed.
 *
 * @param h {Host} the host
 * @param args {list of string} the arguments after the program
 * @param what {string} the operation, for error messages
 * @return {string} its standard output
 * @throws {Error} kind "virtualbox" if it fails
 */
func call(h as Host, args as list of string, what as string) {
    return checked(execute($h.config, $args, $h.config.timeoutMs, $what), $what);
}

/**
 * `call` with the long deadline, for import, export, clone, snapshots and
 * guest copies.
 *
 * @param h {Host} the host
 * @param args {list of string} the arguments after the program
 * @param what {string} the operation, for error messages
 * @return {string} its standard output
 * @throws {Error} kind "virtualbox" if it fails
 */
func callLong(h as Host, args as list of string, what as string) {
    return checked(execute($h.config, $args, $h.config.longTimeoutMs, $what), $what);
}

/**
 * The standard output of a finished command that succeeded, for the parsers:
 * at most `MAX_OUTPUT` characters and `MAX_LINES` lines.
 *
 * @param r {os.Result} the result
 * @param what {string} the operation, for the message
 * @return {string} its standard output
 * @throws {Error} kind "virtualbox" if the exit code is not 0 or it printed more
 */
func checked(r as os.Result, what as string) {
    if ($r.exitCode != 0) {
        failed($what, $r);
    }
    if (len($r.stdout) > MAX_OUTPUT) {
        fail($what + ": printed more than " + convert.toString(MAX_OUTPUT) + " characters");
    }
    if (strings.count($r.stdout, "\n") > MAX_LINES) {
        fail($what + ": printed more than " + convert.toString(MAX_LINES) + " lines");
    }
    return $r.stdout;
}

/**
 * Throw the error a failed command explains: its first `VBoxManage: error:`
 * line, the `VBOX_E_*` / `E_*` / `NS_ERROR_*` code from its `Details:` line, and the exit
 * code: `virtualbox: startvm web: Could not find a registered machine named
 * 'web' (VBOX_E_OBJECT_NOT_FOUND, exit 1)`.
 *
 * @param what {string} the operation
 * @param r {os.Result} the result
 * @throws {Error} kind "virtualbox", always
 */
func failed(what as string, r as os.Result) {
    def explained as list of string init explain($r.stderr);
    def tail as string init "exit " + convert.toString($r.exitCode);
    if ($explained[1] != "") {
        $tail = $explained[1] + ", " + $tail;
    }
    fail($what + ": " + $explained[0] + " (" + $tail + ")");
}

/**
 * The message and the code in `VBoxManage`'s error output.
 *
 * @param stderr {string} the error output
 * @return {list of string} the message, cleaned and cut, and the code (`""` if there is none)
 */
func explain(stderr as string) {
    def text as string init $stderr;
    if (len($text) > MAX_ERROR_OUTPUT) {
        $text = strings.substring($text, 0, MAX_ERROR_OUTPUT);
    }
    def message as string init "";
    def code as string init "";
    def first as string init "";
    for (def line in strings.split($text, "\n")) {
        def t as string init strings.trim($line);
        if ($t == "") {
            continue;
        }
        if ($first == "") {
            $first = $t;
        }
        def m as regex.Match init regex.find('^VBoxManage(\.exe)?: error: (.*)$', $t);
        if ($m.start < 0) {
            continue;
        }
        def body as string init $m.groups[1];
        def c as regex.Match init regex.find('code ((VBOX_E|E|NS_ERROR)_[A-Z0-9_]+) \(0x', $body);
        if ($c.start >= 0 and $code == "") {
            $code = $c.groups[0];
        }
        if ($message == "" and not strings.startsWith($body, "Details:") and
            not strings.startsWith($body, "Context:")) {
            $message = $body;
        }
    }
    if ($message == "") {
        $message = $first;
    }
    if ($message == "") {
        $message = "failed without a message";
    }
    return [cleaned($message, 300), $code];
}

/**
 * The `VBOX_E_*`, `E_*` or `NS_ERROR_*` code of a virtualbox error (Linux
 * and macOS hosts report generic failures as `NS_ERROR_FAILURE`), to tell a missing
 * machine (`VBOX_E_OBJECT_NOT_FOUND`) from a locked one
 * (`VBOX_E_INVALID_OBJECT_STATE`) and the like.
 *
 * @param e {Error} a caught error
 * @return {string} the code, `""` if the error is not a virtualbox error from `VBoxManage` or names none
 * @example
 *   try {
 *       virtualbox.info($vb, "web");
 *   } catch (e) {
 *       if (virtualbox.errorCode($e) == "VBOX_E_OBJECT_NOT_FOUND") {
 *           io.printf("no such machine\n");
 *       }
 *   }
 */
export func errorCode(e as Error) {
    if ($e.kind != "virtualbox") {
        return "";
    }
    def m as regex.Match init regex.find(
        '\(((VBOX_E|E|NS_ERROR)_[A-Z0-9_]+), exit -?[0-9]+\)$',
        $e.message);
    if ($m.start < 0) {
        return "";
    }
    return $m.groups[0];
}

/**
 * Run any `VBoxManage` subcommand the deck has no function for, with the
 * ordinary deadline. The arguments are passed as they are (options
 * included), so build them from trusted values only.
 *
 * @param h {Host} the host
 * @param args {list of string} the arguments after `VBoxManage`, such as `["list", "dhcpservers"]`
 * @return {string} its standard output
 * @throws {Error} kind "virtualbox" if an argument is empty, too long or holds a control character, or the command fails
 * @example
 *   io.printf("%s", virtualbox.run($vb, ["list", "dhcpservers"]));
 */
export func run(h as Host, args as list of string) {
    if (len($args) == 0) {
        fail("run needs a subcommand");
    }
    for (def a in $args) {
        checkText($a, "an argument");
    }
    return call($h, $args, $args[0]);
}
