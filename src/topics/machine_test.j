# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# virtualbox - white-box tests for the machine topic. Spliced into
# virtualbox_test.j via include.

func testInfoReadsTheMachine() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "showvminfo_web", "out", fixture("showvminfo-web.out"));
    def i as VmInfo init info(fakeHost(), "web");
    testing.assertEqual(lastCall($d), "showvminfo|web|--machinereadable");
    testing.assertEqual($i.name, "web");
    testing.assertEqual($i.uuid, "4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c");
    testing.assertEqual($i.osType, "Ubuntu (64-bit)");
    testing.assertEqual($i.state, "running");
    testing.assertEqual($i.memoryMb, 2048);
    testing.assertEqual($i.vramMb, 16);
    testing.assertEqual($i.cpus, 2);
    testing.assertEqual($i.firmware, "EFI");
    testing.assertEqual($i.configFile, "/home/ada/VirtualBox VMs/web/web.vbox");
    testing.assertEqual($i.guestAdditions, "7.1.4 r165100");
    testing.assertEqual($i.currentSnapshot, "patched");
    testing.assertEqual($i.raw["chipset"], "piix3");
    testing.assertEqual(state(fakeHost(), "web"), "running");
}

func testInfoReadsNics() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "showvminfo_web", "out", fixture("showvminfo-web.out"));
    def nics as list of Nic init info(fakeHost(), "web").nics;
    testing.assertEqual(len($nics), 4);
    testing.assertEqual($nics[0].index, 1);
    testing.assertEqual($nics[0].attachment, "nat");
    testing.assertEqual($nics[0].model, "82540EM");
    testing.assertEqual($nics[0].mac, "0800273C5A7E");
    testing.assertTrue($nics[0].connected);
    testing.assertEqual($nics[0].network, "");
    testing.assertEqual($nics[1].index, 2);
    testing.assertEqual($nics[1].attachment, "bridged");
    testing.assertEqual($nics[1].network, "eth0");
    testing.assertFalse($nics[1].connected);
    testing.assertEqual($nics[2].index, 3);
    testing.assertEqual($nics[3].index, 4);
    testing.assertEqual($nics[3].attachment, "generic");
    testing.assertEqual($nics[3].network, "VDE");
    def other as map of string to string init {
        "nic1": "intnet",
        "intnet1": "lan",
        "nic2": "natnetwork",
        "nat-network2": "lab",
        "nic3": "hostonly",
        "hostonlyadapter3": "vboxnet0",
        "nic4": "natnetwork",
        "natnetwork4": "old"
    };
    def more as list of Nic init nicsFrom($other);
    testing.assertEqual($more[0].network, "lan");
    testing.assertEqual($more[1].network, "lab");
    testing.assertEqual($more[2].network, "vboxnet0");
    testing.assertEqual($more[3].network, "old");
}

func testInfoReadsForwardsPerNic() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "showvminfo_web", "out", fixture("showvminfo-web.out"));
    def rules as list of Forward init info(fakeHost(), "web").forwards;
    testing.assertEqual(len($rules), 3);
    testing.assertEqual($rules[0].nic, 1);
    testing.assertEqual($rules[0].name, "ssh");
    testing.assertEqual($rules[0].protocol, "tcp");
    testing.assertEqual($rules[0].hostIp, "");
    testing.assertEqual($rules[0].hostPort, 2222);
    testing.assertEqual($rules[0].guestPort, 22);
    testing.assertEqual($rules[1].hostIp, "127.0.0.1");
    testing.assertEqual($rules[2].nic, 3);
    testing.assertEqual($rules[2].protocol, "udp");
    testing.assertEqual($rules[2].guestIp, "10.0.2.15");
    testing.assertEqual(len(forwardsFrom(pairs("nic1=\"nat\"\nForwarding(0)=\"bad,rule\"\n"))), 0);
}

func testInfoReadsStorageAndFolders() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "showvminfo_web", "out", fixture("showvminfo-web.out"));
    def i as VmInfo init info(fakeHost(), "web");
    testing.assertEqual(len($i.controllers), 2);
    testing.assertEqual($i.controllers[0].name, "SATA");
    testing.assertEqual($i.controllers[0].type, "IntelAhci");
    testing.assertEqual($i.controllers[0].ports, 2);
    testing.assertTrue($i.controllers[0].bootable);
    testing.assertEqual($i.controllers[1].name, "IDE");
    testing.assertEqual(len($i.attachments), 2);
    testing.assertEqual($i.attachments[0].controller, "SATA");
    testing.assertEqual($i.attachments[0].port, 0);
    testing.assertEqual($i.attachments[0].device, 0);
    testing.assertEqual($i.attachments[0].medium, "/home/ada/VirtualBox VMs/web/web.vdi");
    testing.assertEqual($i.attachments[1].controller, "IDE");
    testing.assertEqual($i.attachments[1].port, 1);
    testing.assertEqual($i.attachments[1].medium, "emptydrive");
    testing.assertEqual(len($i.sharedFolders), 3);
    testing.assertEqual($i.sharedFolders[0].name, "site");
    testing.assertEqual($i.sharedFolders[0].hostPath, "/srv/site");
    testing.assertEqual($i.sharedFolders[0].scope, "machine");
    testing.assertEqual($i.sharedFolders[1].name, "scratch");
    testing.assertEqual($i.sharedFolders[1].scope, "transient");
    testing.assertEqual($i.sharedFolders[2].name, "iso");
    testing.assertEqual($i.sharedFolders[2].hostPath, "/srv/iso");
    testing.assertEqual($i.sharedFolders[2].scope, "global");
}

func testCreateRegistersAndReturnsTheUuid() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "createvm", "out", fixture("createvm.out"));
    testing.assertEqual(
        create(fakeHost(), "web", "Ubuntu_64"),
        "4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c");
    testing.assertEqual(lastCall($d), "createvm|--name|web|--ostype|Ubuntu_64|--register");
    createIn(fakeHost(), "web", "Ubuntu_64", "/srv/vms");
    testing.assertEqual(
        lastCall($d),
        "createvm|--name|web|--ostype|Ubuntu_64|--register|--basefolder|/srv/vms");
    for (def osName in ["", "Ubuntu 64", "--register", "a;b"]) {
        try {
            create(fakeHost(), "web", $osName);
            missed($osName);
        } catch (e) {
            testing.assertContains($e.message, "the OS type must be an id");
        }
    }
    answer($d, "createvm", "out", "done\n");
    try {
        create(fakeHost(), "web", "Ubuntu_64");
        missed("no uuid");
    } catch (e) {
        testing.assertEqual($e.message, "virtualbox: createvm web: printed no UUID: \"done\"");
    }
}

func testRegisterUnregisterDelete() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    register(fakeHost(), "/srv/vms/web/web.vbox");
    unregister(fakeHost(), "web");
    delete(fakeHost(), "web");
    testing.assertEqual(
        strings.join(calls($d), ";"),
        "registervm|/srv/vms/web/web.vbox;unregistervm|web;unregistervm|web|--delete");
    try {
        register(fakeHost(), "-x.vbox");
        missed("-x.vbox");
    } catch (e) {
        testing.assertContains($e.message, "the settings file must not start with -");
    }
}

func testSettings() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    setCpus(fakeHost(), "web", 4);
    setMemory(fakeHost(), "web", 4096);
    setFirmware(fakeHost(), "web", "efi");
    testing.assertEqual(
        strings.join(calls($d), ";"),
        "modifyvm|web|--cpus|4;modifyvm|web|--memory|4096;modifyvm|web|--firmware|efi");
    try {
        setCpus(fakeHost(), "web", 0);
        missed("0 cpus");
    } catch (e) {
        testing.assertContains($e.message, "the processor count must be 1 to 64");
    }
    try {
        setMemory(fakeHost(), "web", 2);
        missed("2 MiB");
    } catch (e) {
        testing.assertContains($e.message, "the memory size must be 4 to 2097152");
    }
    try {
        setFirmware(fakeHost(), "web", "uefi");
        missed("uefi");
    } catch (e) {
        testing.assertContains($e.message, "the firmware must be one of bios, efi, efi32, efi64");
    }
}

func testSetNic() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    setNic(fakeHost(), "web", 1, "nat", "");
    setNic(fakeHost(), "web", 2, "bridged", "eth0");
    setNic(fakeHost(), "web", 3, "hostonly", "vboxnet0");
    setNic(fakeHost(), "web", 4, "intnet", "lan");
    setNic(fakeHost(), "web", 5, "natnetwork", "lab");
    setNic(fakeHost(), "web", 6, "none", "");
    testing.assertEqual(
        strings.join(calls($d), ";"),
        "modifyvm|web|--nic1|nat;modifyvm|web|--nic2|bridged|--bridgeadapter2|eth0;" +
            "modifyvm|web|--nic3|hostonly|--hostonlyadapter3|vboxnet0;" +
            "modifyvm|web|--nic4|intnet|--intnet4|lan;modifyvm|web|--nic5|natnetwork|--natnetwork5|lab;" +
            "modifyvm|web|--nic6|none");
    try {
        setNic(fakeHost(), "web", 1, "nat", "eth0");
        missed("nat with a network");
    } catch (e) {
        testing.assertContains($e.message, "a nat NIC names no network");
    }
    try {
        setNic(fakeHost(), "web", 1, "bridged", "");
        missed("bridged without a network");
    } catch (e) {
        testing.assertContains($e.message, "the network of a bridged NIC is empty");
    }
    try {
        setNic(fakeHost(), "web", 37, "nat", "");
        missed("slot 37");
    } catch (e) {
        testing.assertContains($e.message, "the NIC slot must be 1 to 36");
    }
    try {
        setNic(fakeHost(), "web", 1, "generic", "");
        missed("generic");
    } catch (e) {
        testing.assertContains($e.message, "the attachment must be one of");
    }
}

func testStorage() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    addController(fakeHost(), "web", "SATA", "sata");
    attachDisk(fakeHost(), "web", "SATA", 0, 0, "/srv/vms/web.vdi");
    attachDvd(fakeHost(), "web", "SATA", 1, 0, "/srv/iso/debian.iso");
    detach(fakeHost(), "web", "SATA", 1, 0);
    testing.assertEqual(
        strings.join(calls($d), ";"),
        "storagectl|web|--name|SATA|--add|sata;" +
            "storageattach|web|--storagectl|SATA|--port|0|--device|0|--type|hdd|--medium|/srv/vms/web.vdi;" +
            "storageattach|web|--storagectl|SATA|--port|1|--device|0|--type|dvddrive|--medium|/srv/iso/debian.iso;" +
            "storageattach|web|--storagectl|SATA|--port|1|--device|0|--medium|none");
    try {
        addController(fakeHost(), "web", "SATA", "nvme");
        missed("nvme");
    } catch (e) {
        testing.assertContains($e.message, "the bus must be one of");
    }
    try {
        attachDisk(fakeHost(), "web", "SATA", -1, 0, "/srv/vms/web.vdi");
        missed("port -1");
    } catch (e) {
        testing.assertContains($e.message, "the port must be 0 to 1000");
    }
    try {
        detach(fakeHost(), "web", "SATA", 0, 1001);
        missed("device 1001");
    } catch (e) {
        testing.assertContains($e.message, "the device must be 0 to 1000");
    }
}

func testCreateDisk() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    answer($d, "createmedium", "out", fixture("createmedium.out"));
    testing.assertEqual(
        createDisk(fakeHost(), "/srv/vms/web.vdi", 20480),
        "9b3c1d2e-4f5a-4b6c-8d7e-9f0a1b2c3d4e");
    testing.assertEqual(
        lastCall($d),
        "createmedium|disk|--filename|/srv/vms/web.vdi|--size|20480|--format|VDI");
    for (def bad in ["/srv/vms/web.vmdk", "-web.vdi"]) {
        try {
            createDisk(fakeHost(), $bad, 1);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "virtualbox");
        }
    }
    try {
        createDisk(fakeHost(), "/srv/vms/web.vdi", 0);
        missed("size 0");
    } catch (e) {
        testing.assertContains($e.message, "the disk size must be 1 to 67108864");
    }
}

func testMediumKeywordsAreRefusedAsPaths() {
    def d as string init fakeDir();
    defer fs.removeAll($d);
    for (def keyword in ["none", "emptydrive", "Additions", "iscsi", "host:/dev/sr0", "HOST:sr0"]) {
        try {
            attachDisk(fakeHost(), "web", "SATA", 0, 0, $keyword);
            missed($keyword);
        } catch (e) {
            testing.assertContains($e.message, "is a VBoxManage keyword, not a file");
        }
    }
    for (def keyword in ["none", "additions", "host:/dev/sr0"]) {
        try {
            attachDvd(fakeHost(), "web", "SATA", 1, 0, $keyword);
            missed($keyword);
        } catch (e) {
            testing.assertContains($e.message, "(write ./" + $keyword + " for a file)");
        }
    }
    attachDvd(fakeHost(), "web", "SATA", 1, 0, "emptydrive");
    attachDisk(fakeHost(), "web", "SATA", 0, 0, "./none");
    testing.assertEqual(
        strings.join(calls($d), ";"),
        "storageattach|web|--storagectl|SATA|--port|1|--device|0|--type|dvddrive|--medium|emptydrive;" +
            "storageattach|web|--storagectl|SATA|--port|0|--device|0|--type|hdd|--medium|./none");
}
