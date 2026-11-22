# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# virtualbox - white-box tests for the core topic, and the helpers every
# topic's tests share. Spliced into virtualbox_test.j via include.

include "fixtures/vbox_test.j";

/**
 * Mark a call that should have thrown. The error reaches the test's own
 * `catch`, whose assertions on kind and message then fail.
 *
 * @param what {string} what got through
 * @throws {Error} always, with `kind` `"missed"`
 */
func missed(what as string) {
    throw Error{kind: "missed", message: $what};
}

/**
 * A fresh answer directory for the fake `VBoxManage`, made the one it uses,
 * with the fake itself written into it.
 *
 * @return {string} the directory; remove it with `fs.removeAll`
 */
func fakeDir() {
    def d as string init fs.makeTempDir("", "vbox-test-");
    os.setEnv("FAKE_VBOX_DIR", $d);
    fs.writeString($d + "/fake-vboxmanage", strings.join(FAKE_VBOXMANAGE, "\n"));
    fs.chmod($d + "/fake-vboxmanage", 0o755);
    return $d;
}

/**
 * A host that runs the fake `VBoxManage` in the answer directory of the last
 * `fakeDir`, as `open` would return it.
 *
 * @return {Host} the host
 */
func fakeHost() {
    return Host{
        config: withBinary(local(), os.getEnv("FAKE_VBOX_DIR") + "/fake-vboxmanage"),
        version: "7.1.4r165100",
        major: 7,
        minor: 1
    };
}

/**
 * Give the fake an answer for a command.
 *
 * @param d {string} the answer directory
 * @param key {string} the command's leading arguments joined by `_`
 * @param ext {string} `out`, `err`, `exit` or `sleep`
 * @param text {string} the content
 */
func answer(d as string, key as string, ext as string, text as string) {
    fs.writeString($d + "/" + $key + "." + $ext, $text);
}

/**
 * A recorded `VBoxManage` output.
 *
 * @param name {string} its file name, such as `list-vms.out`
 * @return {string} its content
 */
func fixture(name as string) {
    return strings.join(VBOX_OUTPUT[$name], "\n");
}

/**
 * Every argument list the fake received, in order.
 *
 * @param d {string} the answer directory
 * @return {list of string} each call's arguments joined by `|`
 */
func calls(d as string) {
    if (not fs.exists($d + "/argv.log")) {
        return [];
    }
    def out as list of string init [];
    def current as list of string init [];
    for (def line in strings.split(fs.readString($d + "/argv.log"), "\n")) {
        if ($line == "----") {
            $out[] = strings.join($current, "|");
            $current = [];
        } elseif ($line != "") {
            $current[] = $line;
        }
    }
    return $out;
}

/**
 * The last argument list the fake received.
 *
 * @param d {string} the answer directory
 * @return {string} its arguments joined by `|`
 */
func lastCall(d as string) {
    def all as list of string init calls($d);
    testing.assertTrue(len($all) > 0);
    return $all[len($all) - 1];
}

func testLocalDefaults() {
    def c as Config init local();
    testing.assertEqual($c.binary, "VBoxManage");
    testing.assertEqual(len($c.prefix), 0);
    testing.assertEqual($c.timeoutMs, DEFAULT_TIMEOUT_MS);
    testing.assertEqual($c.longTimeoutMs, DEFAULT_LONG_TIMEOUT_MS);
}

func testRemoteQuotesEveryArgumentForTheRemoteShell() {
    def c as Config init remote(["ssh", "-o", "BatchMode=yes", "admin@vmhost"]);
    testing.assertEqual(
        strings.join(
            commandLine($c, ["showvminfo", "it's mine; rm -rf /", "--machinereadable"]),
            "|"),
        "ssh|-o|BatchMode=yes|admin@vmhost|env|LC_ALL=C.UTF-8|'VBoxManage'|'showvminfo'|'it'\\''s mine; rm -rf /'|'--machinereadable'");
    testing.assertEqual(
        strings.join(commandLine(local(), ["list", "vms"]), "|"),
        "env|LC_ALL=C.UTF-8|VBoxManage|list|vms");
}

func testRemoteRefusesWhatANonPosixShellWouldRead() {
    def h as Host init fakeHost();
    $h.config = remote(["/nonexistent/ssh", "admin@vmhost"]);
    for (def bad in ["/x\\", "/x!y"]) {
        try {
            setGuestProperty($h, "web", $bad, "; touch /tmp/pwned; echo #");
            missed($bad);
        } catch (e) {
            testing.assertContains(
                $e.message,
                "over a command prefix an argument may not hold \\ or !");
        }
    }
    try {
        withBinary(local(), "/opt/a=b/VBoxManage");
        missed("=");
    } catch (e) {
        testing.assertContains($e.message, "must not hold =");
    }
}

func testVBoxManageRunsInTheCLocale() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    vms(fakeHost());
    testing.assertEqual(strings.trim(fs.readString($d + "/lc_all.seen")), "C.UTF-8");
}

func testRemoteRefusesAnUnusablePrefix() {
    for (def prefix in [[], ["-oProxyCommand=x"], ["ssh", ""], ["ssh", "a\nb"]]) {
        try {
            remote($prefix);
            missed(strings.join($prefix, " "));
        } catch (e) {
            testing.assertEqual($e.kind, "virtualbox");
        }
    }
}

func testWithFunctionsCheckTheirValues() {
    testing.assertEqual(withTimeout(local(), 500).timeoutMs, 500);
    testing.assertEqual(withLongTimeout(local(), 9000).longTimeoutMs, 9000);
    testing.assertEqual(withBinary(local(), "/opt/vbox/VBoxManage").binary, "/opt/vbox/VBoxManage");
    for (def ms in [0, -1, 86400001]) {
        try {
            withTimeout(local(), $ms);
            missed("timeout " + convert.toString($ms));
        } catch (e) {
            testing.assertContains($e.message, "the timeout must be 1 to 86400000");
        }
        try {
            withLongTimeout(local(), $ms);
            missed("long timeout " + convert.toString($ms));
        } catch (e) {
            testing.assertContains($e.message, "the long timeout must be");
        }
    }
    try {
        withBinary(local(), "--help");
        missed("--help");
    } catch (e) {
        testing.assertContains($e.message, "must not start with -");
    }
}

func testOpenReadsTheVersionAfterAWarning() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "--version", "out", fixture("version-warning.out"));
    def h as Host init open(fakeHost().config);
    testing.assertEqual($h.version, "7.0.20r163906");
    testing.assertEqual($h.major, 7);
    testing.assertEqual($h.minor, 0);
    testing.assertEqual(lastCall($d), "--version");
}

func testOpenRefusesAnOldOrSilentVirtualBox() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "--version", "out", "6.1.50r161033\n");
    try {
        open(fakeHost().config);
        missed("6.1");
    } catch (e) {
        testing.assertEqual($e.kind, "virtualbox");
        testing.assertContains($e.message, "VirtualBox 6.1.50r161033 is too old");
    }
    answer($d, "--version", "out", "Oracle VM VirtualBox\n");
    try {
        open(fakeHost().config);
        missed("no version");
    } catch (e) {
        testing.assertContains($e.message, "printed no version");
    }
    answer($d, "--version", "exit", "1");
    answer($d, "--version", "err", "VBoxManage: error: the kernel driver is missing\n");
    try {
        open(fakeHost().config);
        missed("exit 1");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualbox: --version: the kernel driver is missing (exit 1)");
    }
}

func testOpenWithoutTheProgram() {
    try {
        open(withBinary(local(), "/nonexistent/VBoxManage"));
        missed("no program");
    } catch (e) {
        testing.assertEqual($e.kind, "virtualbox");
        testing.assertContains(
            $e.message,
            "cannot run \"/nonexistent/VBoxManage\" (is VirtualBox installed?)");
    }
}

func testAFailureCarriesTheCodeAndTheExitCode() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "showvminfo_ghost", "err", fixture("notfound.err"));
    answer($d, "showvminfo_ghost", "exit", "1");
    try {
        info(fakeHost(), "ghost");
        missed("ghost");
    } catch (e) {
        testing.assertEqual($e.kind, "virtualbox");
        testing.assertEqual(
            $e.message,
            "virtualbox: showvminfo ghost: Could not find a registered machine named 'ghost' (VBOX_E_OBJECT_NOT_FOUND, exit 1)");
        testing.assertEqual(errorCode($e), "VBOX_E_OBJECT_NOT_FOUND");
        # a VirtualboxError: the reason, the code and the exit code as fields
        testing.assertEqual($e.reason, "exit");
        testing.assertEqual($e.code, "VBOX_E_OBJECT_NOT_FOUND");
        testing.assertEqual($e.exitCode, 1);
    }
}

func testAFailureWithoutVBoxManageLines() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_vms", "err", "\n  segmentation fault\u0007 here\n");
    answer($d, "list_vms", "exit", "139");
    try {
        vms(fakeHost());
        missed("crash");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualbox: list vms: segmentation fault? here (exit 139)");
        testing.assertEqual(errorCode($e), "");
        testing.assertEqual($e.exitCode, 139);
    }
    answer($d, "list_vms", "err", "");
    try {
        vms(fakeHost());
        missed("silent");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualbox: list vms: failed without a message (exit 139)");
    }
}

func testExplainPrefersTheFirstErrorLine() {
    def e as list of string init explain(
        "Progress state: E_FAIL\n" +
            "VBoxManage: error: Details: code E_ACCESSDENIED (0x80070005), component SessionMachine\n" +
            "VBoxManage: error: The machine is locked\n" +
            "VBoxManage: error: Context: \"LockMachine\"\n");
    testing.assertEqual($e[0], "The machine is locked");
    testing.assertEqual($e[1], "E_ACCESSDENIED");
    testing.assertEqual(len(explain(strings.replicate("x", 500))[0]), 303);
}

func testACallPastItsDeadlineIsKilled() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_vms", "sleep", "5");
    def h as Host init fakeHost();
    $h.config = withTimeout($h.config, 300);
    def started as time.Time init time.now();
    try {
        vms($h);
        missed("slow");
    } catch (e) {
        testing.assertEqual($e.message, "virtualbox: list vms: no answer after 300 ms, stopped");
        testing.assertEqual($e.reason, "timeout");
        testing.assertEqual($e.exitCode, 0);
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 3000);
}

func testRunPassesItsArgumentsAsTheyAre() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_dhcpservers", "out", "NetworkName: HostInterfaceNetworking-vboxnet0\n");
    testing.assertContains(run(fakeHost(), ["list", "dhcpservers"]), "vboxnet0");
    testing.assertEqual(lastCall($d), "list|dhcpservers");
    for (def args in [[], ["list", ""], ["list", "a\tb"]]) {
        try {
            run(fakeHost(), $args);
            missed(strings.join($args, " "));
        } catch (e) {
            testing.assertEqual($e.kind, "virtualbox");
        }
    }
}

func testChecksRefuseWhatVBoxManageWouldMisread() {
    for (def bad in ["", "-x", "--register", "a\nb", "tab\there", strings.replicate("n", 256)]) {
        try {
            checkVm($bad);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "virtualbox");
        }
    }
    checkVm("web 2 (copy)");
    checkVm("4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c");
    try {
        checkPath("-rf", "the disk");
        missed("-rf");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualbox: the disk must not start with -, got \"-rf\" (write ./-rf)");
    }
    try {
        checkPath(strings.replicate("p", 4097), "the disk");
        missed("long path");
    } catch (e) {
        testing.assertContains($e.message, "longer than 4096 characters");
    }
    try {
        checkChoice("vmdk", ["vdi"], "the format");
        missed("vmdk");
    } catch (e) {
        testing.assertEqual($e.message, "virtualbox: the format must be one of vdi, got \"vmdk\"");
    }
}

func testShownCutsAndCleans() {
    testing.assertEqual(shown("a\u0001b"), "\"a?b\"");
    testing.assertEqual(shown("a\u0085b\u202Ec\u2066d"), "\"a?b?c?d\"");
    testing.assertEqual(len(shown(strings.replicate("x", 300))), 205);
    testing.assertEqual(shellQuoted("a'b"), "'a'\\''b'");
}

func testAVBoxManageThatIgnoresSigtermIsLeftRunning() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_vms", "sleep", "7");
    answer($d, "list_vms", "ignoreterm", "");
    def h as Host init fakeHost();
    $h.config = withTimeout($h.config, 200);
    def started as time.Time init time.now();
    try {
        vms($h);
        missed("ignored SIGTERM");
    } catch (e) {
        testing.assertContains(
            $e.message,
            "virtualbox: list vms: no answer after 200 ms; still running 5000 ms after SIGTERM, left running as pid ");
    }
    def spent as int init time.milliseconds(time.sub(time.now(), $started));
    testing.assertTrue($spent >= 5000 and $spent < 6500);
}

func testNsErrorCodes() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "startvm_web", "exit", "1");
    answer(
        $d,
        "startvm_web",
        "err",
        "VBoxManage: error: The virtual machine 'web' has terminated unexpectedly during startup\n" +
            "VBoxManage: error: Details: code NS_ERROR_FAILURE (0x80004005), component MachineWrap, interface IMachine\n");
    try {
        start(fakeHost(), "web");
        missed("start");
    } catch (e) {
        testing.assertEqual(errorCode($e), "NS_ERROR_FAILURE");
        testing.assertContains($e.message, "(NS_ERROR_FAILURE, exit 1)");
    }
}

func testOutputBeyondTheCapIsRefused() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_vms", "out", strings.replicate("x", 4194305));
    try {
        vms(fakeHost());
        missed("big output");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualbox: list vms: printed more than 4194304 characters");
        testing.assertEqual($e.kind, "limit");
    }
    answer($d, "list_vms", "out", strings.replicate("\n", 50001));
    try {
        vms(fakeHost());
        missed("many lines");
    } catch (e) {
        testing.assertEqual($e.message, "virtualbox: list vms: printed more than 50000 lines");
        testing.assertEqual($e.kind, "limit");
    }
    answer($d, "list_vms", "out", "");
    answer($d, "list_vms", "err", strings.replicate("y\n", 200000));
    answer($d, "list_vms", "exit", "1");
    try {
        vms(fakeHost());
        missed("big error");
    } catch (e) {
        testing.assertEqual($e.message, "virtualbox: list vms: y (exit 1)");
    }
}
