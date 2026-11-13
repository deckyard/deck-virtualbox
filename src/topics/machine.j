# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualbox - machine: one machine's details, creating, registering and
# deleting machines, their settings, NICs, storage controllers and disks.
# Spliced into virtualbox.j via include.

# the NIC attachments setNic accepts
def const ATTACHMENTS as list of string init
    [
    "none",
    "null",
    "nat",
    "bridged",
    "hostonly",
    "intnet",
    "natnetwork"
];

# the storage buses addController accepts
def const BUSES as list of string init
    [
    "ide",
    "sata",
    "scsi",
    "floppy",
    "sas",
    "usb",
    "pcie",
    "virtio"
];

# the firmware setFirmware accepts
def const FIRMWARE as list of string init ["bios", "efi", "efi32", "efi64"];

/**
 * A network adapter of a machine.
 *
 * @field index {int} its slot, from 1
 * @field attachment {string} in lower case: `nat`, `bridged`, `hostonly`, `intnet`, `natnetwork`, `hostonlynetwork`, `generic`, `cloud`, `null`
 * @field model {string} the emulated card, such as `82540EM` or `virtio`
 * @field mac {string} its MAC address, 12 hex digits
 * @field connected {bool} whether its cable is connected
 * @field network {string} what it is attached to: the host interface (bridged, host-only), the internal or NAT network's name; `""` for NAT
 */
export def struct Nic {
    index as int,
    attachment as string,
    model as string,
    mac as string,
    connected as bool,
    network as string
};

/**
 * A NAT port-forwarding rule.
 *
 * @field nic {int} the NIC it belongs to, from 1
 * @field name {string} the rule's name
 * @field protocol {string} `tcp` or `udp`
 * @field hostIp {string} the host address it listens on, `""` for all
 * @field hostPort {int} the host port
 * @field guestIp {string} the guest address it forwards to, `""` for the guest's DHCP address
 * @field guestPort {int} the guest port
 */
export def struct Forward {
    nic as int,
    name as string,
    protocol as string,
    hostIp as string,
    hostPort as int,
    guestIp as string,
    guestPort as int
};

/**
 * A storage controller of a machine.
 *
 * @field name {string} its name, such as `SATA`
 * @field type {string} the emulated chip, such as `IntelAhci` or `PIIX4`
 * @field ports {int} its port count
 * @field bootable {bool} whether the machine may boot from it
 */
export def struct Controller {
    name as string,
    type as string,
    ports as int,
    bootable as bool
};

/**
 * A medium attached to a controller port.
 *
 * @field controller {string} the controller's name
 * @field port {int} the port
 * @field device {int} the device on the port
 * @field medium {string} the image file, or `emptydrive` for a drive with no disc
 */
export def struct Attachment {
    controller as string,
    port as int,
    device as int,
    medium as string
};

/**
 * A folder of the host the guest sees.
 *
 * @field name {string} its name in the guest
 * @field hostPath {string} the host directory
 * @field scope {string} `machine` (in the machine's settings), `transient` (until the machine stops) or `global` (every machine)
 */
export def struct SharedFolder {
    name as string,
    hostPath as string,
    scope as string
};

/**
 * One machine's details, from `info`.
 *
 * @field name {string} its name
 * @field uuid {string} its UUID
 * @field osType {string} its guest OS type, as VirtualBox describes it
 * @field state {string} `poweroff`, `running`, `paused`, `saved`, `aborted`, `starting`, ...
 * @field memoryMb {int} its memory in MiB
 * @field vramMb {int} its video memory in MiB
 * @field cpus {int} its processors
 * @field firmware {string} `BIOS`, `EFI`, ...
 * @field configFile {string} its settings file (`.vbox`)
 * @field guestAdditions {string} the Guest Additions version the guest reports, `""` when none run
 * @field currentSnapshot {string} the current snapshot's name, `""` without snapshots
 * @field nics {list of Nic} its enabled network adapters
 * @field forwards {list of Forward} the NAT port forwards of all its NICs
 * @field controllers {list of Controller} its storage controllers
 * @field attachments {list of Attachment} what is attached to them
 * @field sharedFolders {list of SharedFolder} its shared folders
 * @field raw {map of string to string} every `showvminfo --machinereadable` value, for the fields not read here (a repeated key keeps its first value)
 */
export def struct VmInfo {
    name as string,
    uuid as string,
    osType as string,
    state as string,
    memoryMb as int,
    vramMb as int,
    cpus as int,
    firmware as string,
    configFile as string,
    guestAdditions as string,
    currentSnapshot as string,
    nics as list of Nic,
    forwards as list of Forward,
    controllers as list of Controller,
    attachments as list of Attachment,
    sharedFolders as list of SharedFolder,
    raw as map of string to string
};

/**
 * One machine's details: state, hardware, NICs and their forwards, storage,
 * shared folders.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @return {VmInfo} the details
 * @throws {Error} kind "virtualbox" if the name is unusable or the machine is not found (`VBOX_E_OBJECT_NOT_FOUND`)
 * @example
 *   def i as virtualbox.VmInfo init virtualbox.info($vb, "web");
 *   io.printf("%s: %s, %d MiB\n", $i.name, $i.state, $i.memoryMb);
 */
export func info(h as Host, vm as string) {
    checkVm($vm);
    return vmInfoFrom(call($h, ["showvminfo", $vm, "--machinereadable"], "showvminfo " + $vm));
}

/**
 * A machine's state: `poweroff`, `running`, `paused`, `saved`, `aborted`, ...
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @return {string} the state
 * @throws {Error} kind "virtualbox" as `info`
 */
export func state(h as Host, vm as string) {
    checkVm($vm);
    return stateFrom(call($h, ["showvminfo", $vm, "--machinereadable"], "showvminfo " + $vm));
}

/**
 * The `VMState` in `showvminfo --machinereadable` output, without parsing
 * the rest: the first line that is exactly `VMState="<word>"`. An escaped
 * description cannot hold such a line (its `"` are `\"`), and VBoxManage
 * prints the state before the unescaped snapshot lines.
 *
 * @param out {string} the output
 * @return {string} the state, `""` when there is none
 */
func stateFrom(out as string) {
    def m as regex.Match init regex.find('(?m)^VMState="([a-z]+)"\r?$', $out);
    if ($m.start < 0) {
        return "";
    }
    return $m.groups[0];
}

/**
 * The details in `showvminfo --machinereadable` output.
 *
 * @param out {string} the output
 * @return {VmInfo} the details
 */
func vmInfoFrom(out as string) {
    def lines as list of Pair init pairs($out);
    def m as map of string to string init pairMap($lines);
    def controllers as list of Controller init controllersFrom($m);
    return VmInfo{
        name: field($m, "name"),
        uuid: field($m, "UUID"),
        osType: field($m, "ostype"),
        state: field($m, "VMState"),
        memoryMb: number(field($m, "memory")),
        vramMb: number(field($m, "vram")),
        cpus: number(field($m, "cpus")),
        firmware: field($m, "firmware"),
        configFile: field($m, "CfgFile"),
        guestAdditions: field($m, "GuestAdditionsVersion"),
        currentSnapshot: field($m, "CurrentSnapshotName"),
        nics: nicsFrom($m),
        forwards: forwardsFrom($lines),
        controllers: $controllers,
        attachments: attachmentsFrom($lines, $controllers),
        sharedFolders: foldersFrom($m),
        raw: $m
    };
}

/**
 * The enabled NICs: `nicN` keys other than `none`.
 *
 * @param m {map of string to string} the machine-readable values
 * @return {list of Nic} the NICs, by slot
 */
func nicsFrom(m as map of string to string) {
    def out as list of Nic init [];
    for (def i in 1..37) {
        def n as string init convert.toString($i);
        def attachment as string init strings.lower(field($m, "nic" + $n));
        if ($attachment == "" or $attachment == "none") {
            continue;
        }
        def network as string init "";
        if ($attachment == "bridged") {
            $network = field($m, "bridgeadapter" + $n);
        } elseif ($attachment == "hostonly") {
            $network = field($m, "hostonlyadapter" + $n);
        } elseif ($attachment == "intnet") {
            $network = field($m, "intnet" + $n);
        } elseif ($attachment == "natnetwork") {
            $network = fieldOf($m, ["nat-network" + $n, "natnetwork" + $n]);
        } elseif ($attachment == "hostonlynetwork") {
            $network = field($m, "hostonly-network" + $n);
        } elseif ($attachment == "generic") {
            $network = field($m, "generic" + $n);
        }
        $out[] = Nic{
            index: $i,
            attachment: $attachment,
            model: field($m, "nictype" + $n),
            mac: field($m, "macaddress" + $n),
            connected: isYes(field($m, "cableconnected" + $n)),
            network: $network
        };
    }
    return $out;
}

/**
 * The `Forwarding(N)` rules, each under the `nicN` line before it.
 *
 * @param lines {list of Pair} the machine-readable lines, in order
 * @return {list of Forward} the rules
 */
func forwardsFrom(lines as list of Pair) {
    def out as list of Forward init [];
    def nic as int init 0;
    for (def p in $lines) {
        if (strings.startsWith($p.key, "nic") and regex.matches('^nic[0-9]{1,2}$', $p.key)) {
            $nic = convert.toInt(strings.substring($p.key, 3));
            continue;
        }
        if (not strings.startsWith($p.key, "Forwarding(") or
            not regex.matches('^Forwarding\([0-9]+\)$', $p.key)) {
            continue;
        }
        def parts as list of string init strings.split($p.value, ",");
        if (len($parts) != 6) {
            continue;
        }
        $out[] = Forward{
            nic: $nic,
            name: $parts[0],
            protocol: $parts[1],
            hostIp: $parts[2],
            hostPort: number($parts[3]),
            guestIp: $parts[4],
            guestPort: number($parts[5])
        };
    }
    return $out;
}

/**
 * The storage controllers: `storagecontrollernameN` and its siblings.
 *
 * @param m {map of string to string} the machine-readable values
 * @return {list of Controller} the controllers
 */
func controllersFrom(m as map of string to string) {
    def out as list of Controller init [];
    def i as int init 0;
    while (maps.has($m, "storagecontrollername" + convert.toString($i))) {
        def n as string init convert.toString($i);
        $out[] = Controller{
            name: $m["storagecontrollername" + $n],
            type: field($m, "storagecontrollertype" + $n),
            ports: number(field($m, "storagecontrollerportcount" + $n)),
            bootable: isYes(field($m, "storagecontrollerbootable" + $n))
        };
        $i = $i + 1;
    }
    return $out;
}

/**
 * What is attached to the controllers: `"<controller>-<port>-<device>"` keys
 * whose value is not `none`.
 *
 * @param lines {list of Pair} the machine-readable lines
 * @param controllers {list of Controller} the controllers
 * @return {list of Attachment} the attachments
 */
func attachmentsFrom(lines as list of Pair, controllers as list of Controller) {
    def names as list of string init [];
    for (def c in $controllers) {
        $names[] = $c.name;
    }
    def out as list of Attachment init [];
    for (def p in $lines) {
        if ($p.value == "none" or not strings.contains($p.key, "-")) {
            continue;
        }
        def m as regex.Match init regex.find('^(.+)-([0-9]+)-([0-9]+)$', $p.key);
        if ($m.start != 0 or not lists.contains($names, $m.groups[0])) {
            continue;
        }
        $out[] = Attachment{
            controller: $m.groups[0],
            port: convert.toInt($m.groups[1]),
            device: convert.toInt($m.groups[2]),
            medium: $p.value
        };
    }
    return $out;
}

/**
 * The shared folders: the machine's own (`MachineMapping`), transient ones
 * and global ones.
 *
 * @param m {map of string to string} the machine-readable values
 * @return {list of SharedFolder} the folders
 */
func foldersFrom(m as map of string to string) {
    def out as list of SharedFolder init [];
    for (def kind in ["Machine", "Transient", "Global"]) {
        def i as int init 1;
        while (maps.has($m, "SharedFolderName" + $kind + "Mapping" + convert.toString($i))) {
            def n as string init convert.toString($i);
            $out[] = SharedFolder{
                name: $m["SharedFolderName" + $kind + "Mapping" + $n],
                hostPath: field($m, "SharedFolderPath" + $kind + "Mapping" + $n),
                scope: strings.lower($kind)
            };
            $i = $i + 1;
        }
    }
    return $out;
}

/**
 * Create and register a machine in VirtualBox's default folder.
 *
 * @param h {Host} the host
 * @param name {string} the new machine's name
 * @param osType {string} its guest OS type id, from `osTypes` (such as `Ubuntu_64`)
 * @return {string} its UUID
 * @throws {Error} kind "virtualbox" if the name or type is unusable or VirtualBox refuses
 * @example
 *   def id as string init virtualbox.create($vb, "web", "Ubuntu_64");
 */
export func create(h as Host, name as string, osType as string) {
    return createVm($h, $name, $osType, "");
}

/**
 * `create`, with the machine's folder under another base folder.
 *
 * @param h {Host} the host
 * @param name {string} the new machine's name
 * @param osType {string} its guest OS type id
 * @param baseFolder {string} the folder the machine's own folder goes in
 * @return {string} its UUID
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func createIn(h as Host, name as string, osType as string, baseFolder as string) {
    checkPath($baseFolder, "the base folder");
    return createVm($h, $name, $osType, $baseFolder);
}

/**
 * `createvm --register`, and the UUID it prints.
 *
 * @param h {Host} the host
 * @param name {string} the new machine's name
 * @param osType {string} its guest OS type id
 * @param baseFolder {string} the base folder, `""` for VirtualBox's default
 * @return {string} the UUID
 * @throws {Error} kind "virtualbox" if an argument is unusable, VirtualBox refuses or prints no UUID
 */
func createVm(h as Host, name as string, osType as string, baseFolder as string) {
    checkName($name, "the machine name");
    if (not regex.matches('^[A-Za-z0-9_]{1,64}$', $osType)) {
        fail("the OS type must be an id from osTypes, such as Ubuntu_64, got " + shown($osType));
    }
    def args as list of string init [
        "createvm",
        "--name",
        $name,
        "--ostype",
        $osType,
        "--register"
    ];
    if ($baseFolder != "") {
        $args[] = "--basefolder";
        $args[] = $baseFolder;
    }
    return printedUuid(call($h, $args, "createvm " + $name), "createvm " + $name);
}

/**
 * The UUID a command printed (`UUID: ...`).
 *
 * @param out {string} its output
 * @param what {string} the command, for the message
 * @return {string} the UUID
 * @throws {Error} kind "virtualbox" if it printed none
 */
func printedUuid(out as string, what as string) {
    def m as regex.Match init regex.find(
        'UUID: ([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})',
        $out);
    if ($m.start < 0) {
        fail($what + ": printed no UUID: " + shown(strings.trim($out)));
    }
    return $m.groups[0];
}

/**
 * Register a machine from its settings file.
 *
 * @param h {Host} the host
 * @param settingsFile {string} the machine's `.vbox` file
 * @throws {Error} kind "virtualbox" if the path is unusable or VirtualBox refuses
 */
export func register(h as Host, settingsFile as string) {
    checkPath($settingsFile, "the settings file");
    call($h, ["registervm", $settingsFile], "registervm");
}

/**
 * Unregister a machine, keeping its files.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @throws {Error} kind "virtualbox" if the name is unusable or VirtualBox refuses
 */
export func unregister(h as Host, vm as string) {
    checkVm($vm);
    call($h, ["unregistervm", $vm], "unregistervm " + $vm);
}

/**
 * Unregister a machine and delete its files: settings, logs, saved states and
 * the disk images attached to it. It must be powered off.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @throws {Error} kind "virtualbox" if the name is unusable or VirtualBox refuses
 */
export func delete(h as Host, vm as string) {
    checkVm($vm);
    call($h, ["unregistervm", $vm, "--delete"], "unregistervm " + $vm);
}

/**
 * Change a powered-off machine's settings with `modifyvm`.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param args {list of string} the options after the machine
 * @throws {Error} kind "virtualbox" if VirtualBox refuses
 */
func modify(h as Host, vm as string, args as list of string) {
    checkVm($vm);
    def all as list of string init ["modifyvm", $vm];
    for (def a in $args) {
        $all[] = $a;
    }
    call($h, $all, "modifyvm " + $vm);
}

/**
 * Set a powered-off machine's processor count.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param cpus {int} processors, 1 to 64
 * @throws {Error} kind "virtualbox" if the count is out of range or VirtualBox refuses
 */
export func setCpus(h as Host, vm as string, cpus as int) {
    checkRange($cpus, 1, 64, "the processor count");
    modify($h, $vm, ["--cpus", convert.toString($cpus)]);
}

/**
 * Set a powered-off machine's memory.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param memoryMb {int} MiB, 4 to 2097152
 * @throws {Error} kind "virtualbox" if the size is out of range or VirtualBox refuses
 */
export func setMemory(h as Host, vm as string, memoryMb as int) {
    checkRange($memoryMb, 4, 2097152, "the memory size");
    modify($h, $vm, ["--memory", convert.toString($memoryMb)]);
}

/**
 * Set a powered-off machine's firmware.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param firmware {string} `bios`, `efi`, `efi32` or `efi64`
 * @throws {Error} kind "virtualbox" if the firmware is not one of these or VirtualBox refuses
 */
export func setFirmware(h as Host, vm as string, firmware as string) {
    checkChoice($firmware, FIRMWARE, "the firmware");
    modify($h, $vm, ["--firmware", $firmware]);
}

/**
 * Attach a powered-off machine's network adapter.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param index {int} the adapter's slot, 1 to 36 (more than 8 needs the ICH9 chipset)
 * @param attachment {string} `nat`, `bridged`, `hostonly`, `intnet`, `natnetwork`, `null` (a cable to nowhere) or `none` (no adapter)
 * @param network {string} the host interface for `bridged` and `hostonly`, the network's name for `intnet` and `natnetwork`; `""` for the others
 * @throws {Error} kind "virtualbox" if the slot, attachment or network is unusable or VirtualBox refuses
 * @example
 *   virtualbox.setNic($vb, "web", 1, "bridged", "eth0");
 */
export func setNic(h as Host, vm as string, index as int, attachment as string, network as string) {
    checkRange($index, 1, 36, "the NIC slot");
    checkChoice($attachment, ATTACHMENTS, "the attachment");
    def n as string init convert.toString($index);
    def args as list of string init ["--nic" + $n, $attachment];
    def option as string init "";
    if ($attachment == "bridged") {
        $option = "--bridgeadapter";
    } elseif ($attachment == "hostonly") {
        $option = "--hostonlyadapter";
    } elseif ($attachment == "intnet") {
        $option = "--intnet";
    } elseif ($attachment == "natnetwork") {
        $option = "--natnetwork";
    }
    if ($option == "") {
        if ($network != "") {
            fail("a " + $attachment + " NIC names no network, got " + shown($network));
        }
    } else {
        checkName($network, "the network of a " + $attachment + " NIC");
        $args[] = $option + $n;
        $args[] = $network;
    }
    modify($h, $vm, $args);
}

/**
 * Add a storage controller to a powered-off machine.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param name {string} the controller's name, such as `SATA`
 * @param bus {string} `ide`, `sata`, `scsi`, `floppy`, `sas`, `usb`, `pcie` (NVMe) or `virtio`
 * @throws {Error} kind "virtualbox" if the name or bus is unusable or VirtualBox refuses
 */
export func addController(h as Host, vm as string, name as string, bus as string) {
    checkVm($vm);
    checkName($name, "the controller name");
    checkChoice($bus, BUSES, "the bus");
    call($h, ["storagectl", $vm, "--name", $name, "--add", $bus], "storagectl " + $vm);
}

/**
 * Attach a disk image to a controller port.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param controller {string} the controller's name
 * @param port {int} the port, from 0
 * @param device {int} the device on the port, from 0 (IDE has 0 and 1)
 * @param path {string} the disk image (`.vdi`, `.vmdk`, `.vhd`) or a disk's UUID; a file named like one of VBoxManage's keywords (`none`, `emptydrive`, `additions`, `iscsi`, `host:...`) needs a `./`
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func attachDisk(
    h as Host,
    vm as string,
    controller as string,
    port as int,
    device as int,
    path as string) {
    checkMedium($path, "the disk", false);
    attach($h, $vm, $controller, $port, $device, "hdd", $path);
}

/**
 * Put a disc image in a DVD drive on a controller port, adding the drive.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param controller {string} the controller's name
 * @param port {int} the port, from 0
 * @param device {int} the device on the port, from 0
 * @param path {string} the `.iso` file, or `emptydrive` for a drive with no disc; a file named like another VBoxManage keyword (`none`, `additions`, `iscsi`, `host:...`) needs a `./`
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func attachDvd(
    h as Host,
    vm as string,
    controller as string,
    port as int,
    device as int,
    path as string) {
    checkMedium($path, "the disc image", true);
    attach($h, $vm, $controller, $port, $device, "dvddrive", $path);
}

/**
 * Remove what is attached to a controller port.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param controller {string} the controller's name
 * @param port {int} the port
 * @param device {int} the device on the port
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func detach(h as Host, vm as string, controller as string, port as int, device as int) {
    checkVm($vm);
    checkName($controller, "the controller name");
    checkRange($port, 0, 1000, "the port");
    checkRange($device, 0, 1000, "the device");
    call(
        $h,
        [
            "storageattach",
            $vm,
            "--storagectl",
            $controller,
            "--port",
            convert.toString($port),
            "--device",
            convert.toString($device),
            "--medium",
            "none"
        ],
        "storageattach " + $vm);
}

/**
 * Refuse a medium path VBoxManage would read as a keyword instead of a file:
 * `none` (detach), `emptydrive`, `additions` (the Guest Additions ISO),
 * `iscsi`, or `host:` (a host drive).
 *
 * @param path {string} the path
 * @param what {string} what it is, for the message
 * @param emptyDrive {bool} whether `emptydrive` is allowed
 * @throws {Error} kind "virtualbox" if it is unusable or a keyword
 */
func checkMedium(path as string, what as string, emptyDrive as bool) {
    checkPath($path, $what);
    if ($emptyDrive and $path == "emptydrive") {
        return;
    }
    def lower as string init strings.lower($path);
    if (lists.contains(["none", "emptydrive", "additions", "iscsi"], $lower) or
        strings.startsWith($lower, "host:")) {
        fail($what + " " + shown($path) + " is a VBoxManage keyword, not a file (write ./" +
            cleaned($path, 80) + " for a file)");
    }
}

/**
 * `storageattach` with a medium type.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param controller {string} the controller's name
 * @param port {int} the port
 * @param device {int} the device on the port
 * @param type {string} `hdd` or `dvddrive`
 * @param medium {string} the image, checked by the caller
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
func attach(
    h as Host,
    vm as string,
    controller as string,
    port as int,
    device as int,
    type as string,
    medium as string) {
    checkVm($vm);
    checkName($controller, "the controller name");
    checkRange($port, 0, 1000, "the port");
    checkRange($device, 0, 1000, "the device");
    call(
        $h,
        [
            "storageattach",
            $vm,
            "--storagectl",
            $controller,
            "--port",
            convert.toString($port),
            "--device",
            convert.toString($device),
            "--type",
            $type,
            "--medium",
            $medium
        ],
        "storageattach " + $vm);
}

/**
 * Create a dynamically growing VDI disk image.
 *
 * @param h {Host} the host
 * @param path {string} the new file, ending in `.vdi`
 * @param sizeMb {int} its size in MiB, 1 to 67108864 (64 TiB)
 * @return {string} the new disk's UUID
 * @throws {Error} kind "virtualbox" if the path or size is unusable or VirtualBox refuses (the file exists)
 * @example
 *   virtualbox.createDisk($vb, "/srv/vms/web/web.vdi", 20480);
 */
export func createDisk(h as Host, path as string, sizeMb as int) {
    checkPath($path, "the disk file");
    if (not strings.endsWith(strings.lower($path), ".vdi")) {
        fail("the disk file must end in .vdi, got " + shown($path));
    }
    checkRange($sizeMb, 1, 67108864, "the disk size");
    def out as string init call(
        $h,
        [
            "createmedium",
            "disk",
            "--filename",
            $path,
            "--size",
            convert.toString($sizeMb),
            "--format",
            "VDI"
        ],
        "createmedium");
    return printedUuid($out, "createmedium");
}
