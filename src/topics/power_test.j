# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# virtualbox - white-box tests for the power topic. Spliced into
# virtualbox_test.j via include.

func testStartAndControl() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    start(fakeHost(), "web");
    startWith(fakeHost(), "web", "gui");
    powerOff(fakeHost(), "web");
    acpiShutdown(fakeHost(), "web");
    pause(fakeHost(), "web");
    resume(fakeHost(), "web");
    reset(fakeHost(), "web");
    saveState(fakeHost(), "web");
    testing.assertEqual(
        strings.join(calls($d), ";"),
        "startvm|web|--type|headless;startvm|web|--type|gui;controlvm|web|poweroff;" +
            "controlvm|web|acpipowerbutton;controlvm|web|pause;controlvm|web|resume;" +
            "controlvm|web|reset;controlvm|web|savestate");
    try {
        startWith(fakeHost(), "web", "sdl");
        missed("sdl");
    } catch (e) {
        testing.assertContains($e.message, "the start mode must be one of headless, gui, separate");
    }
    try {
        powerOff(fakeHost(), "--all");
        missed("--all");
    } catch (e) {
        testing.assertContains($e.message, "the machine must not start with -");
    }
}

func testAStartThatVirtualBoxRefuses() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "startvm_web", "exit", "1");
    answer(
        $d,
        "startvm_web",
        "err",
        "VBoxManage: error: The machine 'web' is already locked by a session (or being locked or unlocked)\n" +
            "VBoxManage: error: Details: code VBOX_E_INVALID_OBJECT_STATE (0x80bb0007), component MachineWrap, interface IMachine\n");
    try {
        start(fakeHost(), "web");
        missed("locked");
    } catch (e) {
        testing.assertEqual(errorCode($e), "VBOX_E_INVALID_OBJECT_STATE");
        testing.assertContains(
            $e.message,
            "virtualbox: startvm web: The machine 'web' is already locked");
    }
}

func testForwardsOnARunningMachineGoThroughControlvm() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "showvminfo_web", "out", fixture("showvminfo-web.out"));
    testing.assertEqual(len(forwards(fakeHost(), "web")), 3);
    def rule as Forward init forward(1, "web", 8080, 80);
    $rule.hostIp = "127.0.0.1";
    addForward(fakeHost(), "web", $rule);
    testing.assertEqual(lastCall($d), "controlvm|web|natpf1|web,tcp,127.0.0.1,8080,,80");
    removeForward(fakeHost(), "web", 1, "web");
    testing.assertEqual(lastCall($d), "controlvm|web|natpf1|delete|web");
}

func testForwardsOnAStoppedMachineGoThroughModifyvm() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "showvminfo_db", "out", fixture("showvminfo-off.out"));
    def rule as Forward init forward(2, "dns", 5353, 53);
    $rule.protocol = "udp";
    $rule.guestIp = "10.0.2.15";
    addForward(fakeHost(), "db", $rule);
    testing.assertEqual(lastCall($d), "modifyvm|db|--natpf2|dns,udp,,5353,10.0.2.15,53");
    removeForward(fakeHost(), "db", 2, "dns");
    testing.assertEqual(lastCall($d), "modifyvm|db|--natpf2|delete|dns");
}

func testForwardRulesAreChecked() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    def bad as list of Forward init [];
    def r as Forward init forward(1, "a,b", 2222, 22);
    $bad[] = $r;
    $r = forward(0, "ssh", 2222, 22);
    $bad[] = $r;
    $r = forward(1, "ssh", 0, 22);
    $bad[] = $r;
    $r = forward(1, "ssh", 2222, 65536);
    $bad[] = $r;
    $r = forward(1, "ssh", 2222, 22);
    $r.protocol = "sctp";
    $bad[] = $r;
    $r = forward(1, "ssh", 2222, 22);
    $r.hostIp = "localhost";
    $bad[] = $r;
    $r = forward(1, "ssh", 2222, 22);
    $r.guestIp = "10.0.2.15,evil";
    $bad[] = $r;
    for (def rule in $bad) {
        try {
            addForward(fakeHost(), "web", $rule);
            missed($rule.name);
        } catch (e) {
            testing.assertEqual($e.kind, "virtualbox");
        }
    }
    try {
        removeForward(fakeHost(), "web", 1, "a,b");
        missed("a,b");
    } catch (e) {
        testing.assertContains($e.message, "the rule name must not hold a comma");
    }
    testing.assertEqual(len(calls($d)), 0);
}
