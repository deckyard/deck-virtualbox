# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualbox - white-box tests for the guest topic. Spliced into
# virtualbox_test.j via include.

# the key guestIp reads for the first interface, as the fake's file name
def const IP0_KEY as string init "guestproperty_get_web__VirtualBox_GuestInfo_Net_0_V4_IP";

func testGuestProperties() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "guestproperty_get_web", "out", "Value: Ubuntu 24.04 LTS\n");
    testing.assertEqual(
        guestProperty(fakeHost(), "web", "/VirtualBox/GuestInfo/OS/Product"),
        "Ubuntu 24.04 LTS");
    testing.assertEqual(lastCall($d), "guestproperty|get|web|/VirtualBox/GuestInfo/OS/Product");
    answer($d, "guestproperty_get_web", "out", "No value set!\n");
    testing.assertEqual(guestProperty(fakeHost(), "web", "/mine"), "");
    setGuestProperty(fakeHost(), "web", "/mine", "a b");
    unsetGuestProperty(fakeHost(), "web", "/mine");
    def all as list of string init calls($d);
    testing.assertEqual($all[len($all) - 2], "guestproperty|set|web|/mine|a b");
    testing.assertEqual($all[len($all) - 1], "guestproperty|unset|web|/mine");
    try {
        setGuestProperty(fakeHost(), "web", "/mine", "");
        missed("empty value");
    } catch (e) {
        testing.assertContains($e.message, "the property value is empty");
    }
}

func testGuestIpAndWaitForIp() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, IP0_KEY, "out", "Value: 10.0.2.15\n");
    testing.assertEqual(guestIp(fakeHost(), "web", 0), "10.0.2.15");
    testing.assertEqual(waitForIp(fakeHost(), "web", 0, 5000), "10.0.2.15");
    answer($d, IP0_KEY, "out", "No value set!\n");
    testing.assertEqual(guestIp(fakeHost(), "web", 0), "");
    def started as time.Time init time.now();
    try {
        waitForIp(fakeHost(), "web", 0, 300);
        missed("no ip");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualbox: web reported no IP address for interface 0 within 300 ms (are the Guest Additions running?)");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 3000);
    answer($d, IP0_KEY, "sleep", "4");
    $started = time.now();
    try {
        waitForIp(fakeHost(), "web", 0, 500);
        missed("stalled poll");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualbox: web reported no IP address for interface 0 within 500 ms (the last poll did not answer)");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 2500);
    try {
        guestIp(fakeHost(), "web", 36);
        missed("interface 36");
    } catch (e) {
        testing.assertContains($e.message, "the guest interface must be 0 to 35");
    }
}

func testCredentialsAreChecked() {
    testing.assertEqual(credentials("ada", "").username, "ada");
    for (def user in ["", "-x", "a\nb"]) {
        try {
            credentials($user, "pw");
            missed($user);
        } catch (e) {
            testing.assertEqual($e.kind, "virtualbox");
        }
    }
    try {
        credentials("ada", "pw\n");
        missed("newline");
    } catch (e) {
        testing.assertEqual($e.message, "virtualbox: the guest password holds a control character");
    }
}

func testGuestRunPassesThePasswordThroughAPipe() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "guestcontrol_web_run", "out", "up 3 days\n");
    answer($d, "guestcontrol_web_run", "err", "warning: x\n");
    def r as GuestResult init guestRun(
        fakeHost(),
        "web",
        credentials("ada", "s3cret pw"),
        ["/usr/bin/uptime", "-p"]);
    testing.assertEqual($r.status, "exited");
    testing.assertEqual($r.exitCode, 0);
    testing.assertEqual($r.stdout, "up 3 days\n");
    testing.assertEqual($r.stderr, "warning: x\n");
    def argv as list of string init strings.split(lastCall($d), "|");
    testing.assertEqual(
        strings.join(lists.slice($argv, 0, 5), "|"),
        "guestcontrol|web|run|--username|ada");
    testing.assertEqual($argv[5], "--passwordfile");
    testing.assertEqual(
        strings.join(lists.slice($argv, 7), "|"),
        "--wait-stdout|--wait-stderr|--|/usr/bin/uptime|-p");
    testing.assertFalse(strings.contains(lastCall($d), "s3cret"));
    testing.assertEqual(fs.readString($d + "/password.seen"), "s3cret pw");
    testing.assertEqual(strings.trim(fs.readString($d + "/password.mode")), "600");
    testing.assertTrue(strings.endsWith($argv[6], "/password"));
    testing.assertFalse(fs.exists(strings.substring($argv[6], 0, len($argv[6]) - 9)));
}

func testGuestRunGivesTheProgramsOwnExitCode() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    def cases as map of string to string init {
        "0": "exited 0",
        "33": "exited 1",
        "35": "exited 3",
        "125": "exited 93",
        "126": "exited -1",
        "18": "killed -1",
        "19": "abnormal -1"
    };
    for (def code in maps.keys($cases)) {
        answer($d, "guestcontrol_web_run", "exit", $code);
        def r as GuestResult init guestRun(
            fakeHost(),
            "web",
            credentials("ada", "pw"),
            ["/bin/sh"]);
        testing.assertEqual($r.status + " " + convert.toString($r.exitCode), $cases[$code]);
    }
}

func testAGuestCannotForgeAVBoxManageError() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer(
        $d,
        "guestcontrol_web_run",
        "err",
        "VBoxManage: error: fake\nVBoxManage: error: Details: code VBOX_E_OBJECT_NOT_FOUND (0x80bb0001)\n");
    answer($d, "guestcontrol_web_run", "exit", "33");
    def r as GuestResult init guestRun(fakeHost(), "web", credentials("ada", "pw"), ["/bin/sh"]);
    testing.assertEqual($r.exitCode, 1);
    testing.assertContains($r.stderr, "VBoxManage: error: fake");
}

func testGuestRunReportsAVBoxManageError() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer(
        $d,
        "guestcontrol_web_run",
        "err",
        "VBoxManage: error: The guest execution service is not ready (yet)\n");
    answer($d, "guestcontrol_web_run", "exit", "1");
    try {
        guestRun(fakeHost(), "web", credentials("ada", "pw"), ["/bin/true"]);
        missed("not ready");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualbox: guestcontrol web run: The guest execution service is not ready (yet) (exit 1)");
    }
    def argv as list of string init strings.split(lastCall($d), "|");
    testing.assertFalse(fs.exists($argv[6]));
    answer($d, "guestcontrol_web_run", "exit", "2");
    try {
        guestRun(fakeHost(), "web", credentials("ada", "pw"), ["/bin/true"]);
        missed("syntax error");
    } catch (e) {
        testing.assertContains($e.message, "(exit 2)");
    }
    for (def bad in [[], ["-c"], ["/bin/echo", "a\nb"]]) {
        try {
            guestRun(fakeHost(), "web", credentials("ada", "pw"), $bad);
            missed(strings.join($bad, " "));
        } catch (e) {
            testing.assertEqual($e.kind, "virtualbox");
        }
    }
}

func testGuestCallsAreRefusedOverAPrefix() {
    def h as Host init fakeHost();
    $h.config = remote(["ssh", "admin@vmhost"]);
    try {
        guestRun($h, "web", credentials("ada", "pw"), ["/bin/true"]);
        missed("remote run");
    } catch (e) {
        testing.assertContains($e.message, "guestRun needs a local VBoxManage");
    }
    try {
        copyTo($h, "web", credentials("ada", "pw"), "/tmp/a", "/tmp/b");
        missed("remote copy");
    } catch (e) {
        testing.assertContains($e.message, "copyto needs a local VBoxManage");
    }
}

func testCopies() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    copyTo(
        fakeHost(),
        "web",
        credentials("ada", "pw"),
        "/srv/site/index.html",
        "/var/www/index.html");
    def sent as list of string init strings.split(lastCall($d), "|");
    testing.assertEqual(strings.join(lists.slice($sent, 0, 3), "|"), "guestcontrol|web|copyto");
    testing.assertEqual(
        strings.join(lists.slice($sent, 7), "|"),
        "/srv/site/index.html|/var/www/index.html");
    copyFrom(fakeHost(), "web", credentials("ada", "pw"), "/var/log/syslog", "/tmp/syslog");
    def back as list of string init strings.split(lastCall($d), "|");
    testing.assertEqual($back[2], "copyfrom");
    testing.assertEqual(strings.join(lists.slice($back, 7), "|"), "/var/log/syslog|/tmp/syslog");
    testing.assertFalse(fs.exists($back[6]));
    try {
        copyFrom(fakeHost(), "web", credentials("ada", "pw"), "/var/log/syslog", "-x");
        missed("-x");
    } catch (e) {
        testing.assertContains($e.message, "the target must not start with -");
    }
}

func testSharedFolders() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "showvminfo_web", "out", fixture("showvminfo-web.out"));
    testing.assertEqual(sharedFolders(fakeHost(), "web")[0].hostPath, "/srv/site");
    addSharedFolder(fakeHost(), "web", "site", "/srv/site", true, true);
    addSharedFolder(fakeHost(), "web", "data", "/srv/data", false, false);
    removeSharedFolder(fakeHost(), "web", "site");
    def all as list of string init calls($d);
    testing.assertEqual(
        strings.join(lists.slice($all, 1), ";"),
        "sharedfolder|add|web|--name|site|--hostpath|/srv/site|--readonly|--automount;" +
            "sharedfolder|add|web|--name|data|--hostpath|/srv/data;" +
            "sharedfolder|remove|web|--name|site");
}

func testAPasswordPipeNobodyReadsDoesNotHang() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "nopassword", "out", "");
    fs.writeString($d + "/nopassword", "");
    answer($d, "guestcontrol_web_run", "exit", "1");
    answer(
        $d,
        "guestcontrol_web_run",
        "err",
        "VBoxManage: error: Could not find a registered machine named 'web'\n");
    def started as time.Time init time.now();
    try {
        guestRun(fakeHost(), "web", credentials("ada", "pw"), ["/bin/true"]);
        missed("no machine");
    } catch (e) {
        testing.assertContains($e.message, "Could not find a registered machine");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 2000);
    def argv as list of string init strings.split(lastCall($d), "|");
    testing.assertFalse(fs.exists(strings.substring($argv[6], 0, len($argv[6]) - 9)));
    testing.assertFalse(fs.exists($d + "/password.seen"));
}
