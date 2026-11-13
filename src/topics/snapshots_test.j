# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualbox - white-box tests for the snapshots topic. Spliced into
# virtualbox_test.j via include.

func testSnapshotsReadTheTree() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "showvminfo_web", "out", fixture("showvminfo-web.out"));
    def s as list of Snapshot init snapshots(fakeHost(), "web");
    testing.assertEqual(len($s), 4);
    testing.assertEqual($s[0].name, "installed");
    testing.assertEqual($s[0].depth, 0);
    testing.assertEqual($s[0].description, "fresh install");
    testing.assertFalse($s[0].current);
    testing.assertEqual($s[1].name, "patched");
    testing.assertEqual($s[1].depth, 1);
    testing.assertTrue($s[1].current);
    testing.assertEqual($s[2].name, "experiment");
    testing.assertEqual($s[2].depth, 2);
    testing.assertEqual($s[2].uuid, "e3f4a5b6-c7d8-4e9f-8a1b-2c3d4e5f6a7b");
    testing.assertEqual($s[3].name, "say \"hi\" \\o/");
    testing.assertEqual($s[3].depth, 1);
    answer($d, "showvminfo_db", "out", fixture("showvminfo-off.out"));
    testing.assertEqual(len(snapshots(fakeHost(), "db")), 0);
}

func testSnapshotVerbs() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "snapshot_web_take", "out", fixture("snapshot-take.out"));
    testing.assertEqual(
        takeSnapshot(fakeHost(), "web", "patched", ""),
        "d2e3f4a5-b6c7-4d8e-9f0a-1b2c3d4e5f6a");
    takeSnapshot(fakeHost(), "web", "patched", "after the upgrade");
    restoreSnapshot(fakeHost(), "web", "installed");
    deleteSnapshot(fakeHost(), "web", "experiment");
    testing.assertEqual(
        strings.join(calls($d), ";"),
        "snapshot|web|take|patched;snapshot|web|take|patched|--description|after the upgrade;" +
            "snapshot|web|restore|installed;snapshot|web|delete|experiment");
    try {
        takeSnapshot(fakeHost(), "web", "--live", "");
        missed("--live");
    } catch (e) {
        testing.assertContains($e.message, "the snapshot name must not start with -");
    }
    try {
        takeSnapshot(fakeHost(), "web", "x", "two\nlines");
        missed("newline");
    } catch (e) {
        testing.assertContains($e.message, "the description holds a control character");
    }
}

func testClones() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    clone(fakeHost(), "template", "web2");
    linkedClone(fakeHost(), "template", "base", "web3");
    testing.assertEqual(
        strings.join(calls($d), ";"),
        "clonevm|template|--name|web2|--register;" +
            "clonevm|template|--snapshot|base|--options|link|--name|web3|--register");
}

func testClonesUseTheLongDeadline() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "clonevm", "sleep", "1");
    def h as Host init fakeHost();
    $h.config = withTimeout($h.config, 200);
    clone($h, "template", "web2");
    $h.config = withLongTimeout($h.config, 200);
    try {
        clone($h, "template", "web2");
        missed("slow clone");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualbox: clonevm template: no answer after 200 ms, stopped");
    }
}

func testImportAndExport() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    importOva(fakeHost(), "/srv/images/debian.ova");
    importAs(fakeHost(), "/srv/images/debian.OVF", "build-1");
    exportOva(fakeHost(), "web", "/srv/out/web.ova");
    testing.assertEqual(
        strings.join(calls($d), ";"),
        "import|/srv/images/debian.ova;import|/srv/images/debian.OVF|--vsys|0|--vmname|build-1;" +
            "export|web|--output|/srv/out/web.ova");
    for (def bad in ["/srv/images/debian.zip", "-x.ova", ""]) {
        try {
            importOva(fakeHost(), $bad);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "virtualbox");
        }
    }
}
