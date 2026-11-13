# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualbox - white-box tests for the inventory topic. Spliced into
# virtualbox_test.j via include.

func testVmsReadsNamesAndUuids() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_vms", "out", fixture("list-vms.out"));
    def found as list of Vm init vms(fakeHost());
    testing.assertEqual(len($found), 3);
    testing.assertEqual($found[0].name, "web");
    testing.assertEqual($found[0].uuid, "4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c");
    testing.assertEqual($found[1].name, "say \"hi\"");
    testing.assertEqual($found[2].name, "<inaccessible>");
    testing.assertEqual(lastCall($d), "list|vms");
}

func testRunningVmsAndHasVm() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_runningvms", "out", '"web" {4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c}' + "\n");
    answer($d, "list_vms", "out", fixture("list-vms.out"));
    testing.assertEqual(runningVms(fakeHost())[0].name, "web");
    testing.assertEqual(lastCall($d), "list|runningvms");
    testing.assertTrue(hasVm(fakeHost(), "web"));
    testing.assertTrue(hasVm(fakeHost(), "4E5C3B6A-1F2D-4C8E-9A7B-0D1E2F3A4B5C"));
    testing.assertFalse(hasVm(fakeHost(), "db"));
    try {
        hasVm(fakeHost(), "-x");
        missed("-x");
    } catch (e) {
        testing.assertEqual($e.kind, "virtualbox");
    }
}

func testOsTypesInBothLongForms() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_--long_ostypes", "out", fixture("list-ostypes-70.out"));
    def types as list of OsType init osTypes(fakeHost());
    testing.assertEqual(lastCall($d), "list|--long|ostypes");
    testing.assertEqual(len($types), 2);
    testing.assertEqual($types[1].id, "Ubuntu_64");
    testing.assertEqual($types[1].description, "Ubuntu (64-bit)");
    testing.assertEqual($types[1].familyId, "Linux");
    testing.assertEqual($types[1].familyDescription, "Linux");
    testing.assertTrue($types[1].is64Bit);
    testing.assertFalse($types[0].is64Bit);
    answer($d, "list_--long_ostypes", "out", fixture("list-ostypes-71.out"));
    $types = osTypes(fakeHost());
    testing.assertEqual(len($types), 2);
    testing.assertEqual($types[1].id, "Ubuntu_arm64");
    testing.assertEqual($types[1].description, "Ubuntu (ARM 64-bit)");
    testing.assertEqual($types[1].familyId, "Linux");
    testing.assertTrue($types[1].is64Bit);
}

func testHdds() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_hdds", "out", fixture("list-hdds.out"));
    def disks as list of Medium init hdds(fakeHost());
    testing.assertEqual(len($disks), 2);
    testing.assertEqual($disks[0].parentUuid, "base");
    testing.assertEqual($disks[0].capacityMb, 20480);
    testing.assertEqual($disks[0].format, "VDI");
    testing.assertEqual($disks[0].state, "created");
    testing.assertEqual($disks[1].type, "normal (differencing)");
    testing.assertEqual($disks[1].parentUuid, $disks[0].uuid);
    testing.assertContains($disks[1].location, "/Snapshots/");
}

func testHostOnlyIfs() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_hostonlyifs", "out", fixture("list-hostonlyifs.out"));
    def ifs as list of HostOnlyIf init hostOnlyIfs(fakeHost());
    testing.assertEqual(len($ifs), 1);
    testing.assertEqual($ifs[0].name, "vboxnet0");
    testing.assertEqual($ifs[0].ip, "192.168.56.1");
    testing.assertEqual($ifs[0].netmask, "255.255.255.0");
    testing.assertFalse($ifs[0].dhcp);
    testing.assertEqual($ifs[0].status, "Up");
    testing.assertEqual($ifs[0].mac, "0a:00:27:00:00:00");
}

func testNatNets() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_--long_natnets", "out", fixture("list-natnets.out"));
    def nets as list of NatNet init natNets(fakeHost());
    testing.assertEqual(lastCall($d), "list|--long|natnets");
    testing.assertEqual(len($nets), 2);
    testing.assertEqual($nets[0].name, "NatNetwork");
    testing.assertEqual($nets[0].gateway, "10.0.2.1");
    testing.assertEqual($nets[0].network, "10.0.2.0/24");
    testing.assertTrue($nets[0].dhcp);
    testing.assertTrue($nets[0].enabled);
    testing.assertFalse($nets[0].ipv6);
    testing.assertEqual($nets[1].name, "lab");
    testing.assertEqual($nets[1].gateway, "10.0.9.1");
    testing.assertFalse($nets[1].dhcp);
    testing.assertFalse($nets[1].enabled);
    testing.assertTrue($nets[1].ipv6);
}

func testHostInfo() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "list_hostinfo", "out", fixture("list-hostinfo.out"));
    def i as HostInfo init hostInfo(fakeHost());
    testing.assertEqual($i.processors, 16);
    testing.assertEqual($i.cores, 8);
    testing.assertEqual($i.processor, "AMD Ryzen 7 5800X 8-Core Processor");
    testing.assertTrue($i.hardwareVirtualization);
    testing.assertEqual($i.memoryMb, 64217);
    testing.assertEqual($i.memoryAvailableMb, 41003);
    testing.assertEqual($i.os, "Linux");
    testing.assertEqual($i.osVersion, "6.8.0-45-generic");
}
