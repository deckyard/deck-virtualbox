# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualbox - inventory: what the host has, from `VBoxManage list`. Spliced
# into virtualbox.j via include.

/**
 * A registered machine, from `vms` or `runningVms`.
 *
 * @field name {string} its name; `<inaccessible>` when VirtualBox cannot read its settings
 * @field uuid {string} its UUID
 */
export def struct Vm {
    name as string,
    uuid as string
};

/**
 * A guest OS type VirtualBox knows, from `osTypes`.
 *
 * @field id {string} the id `create` takes, such as `Ubuntu_64`
 * @field description {string} its name, such as `Ubuntu (64-bit)`
 * @field familyId {string} the family, such as `Linux`
 * @field familyDescription {string} the family's name
 * @field is64Bit {bool} whether it is a 64-bit OS
 */
export def struct OsType {
    id as string,
    description as string,
    familyId as string,
    familyDescription as string,
    is64Bit as bool
};

/**
 * A virtual disk VirtualBox knows, from `hdds`.
 *
 * @field uuid {string} its UUID
 * @field parentUuid {string} the disk it is a difference image of, `"base"` for a base disk
 * @field state {string} `created`, `inaccessible`, ...
 * @field type {string} `normal (base)`, `normal (differencing)`, `immutable`, ...
 * @field location {string} its file
 * @field format {string} `VDI`, `VMDK`, `VHD`, ...
 * @field capacityMb {int} its size in MiB
 */
export def struct Medium {
    uuid as string,
    parentUuid as string,
    state as string,
    type as string,
    location as string,
    format as string,
    capacityMb as int
};

/**
 * A host-only network interface, from `hostOnlyIfs`.
 *
 * @field name {string} its name, such as `vboxnet0`
 * @field ip {string} the host's IPv4 address on it
 * @field netmask {string} its IPv4 network mask
 * @field dhcp {bool} whether the host configures it by DHCP
 * @field status {string} `Up` or `Down`
 * @field mac {string} its hardware address
 */
export def struct HostOnlyIf {
    name as string,
    ip as string,
    netmask as string,
    dhcp as bool,
    status as string,
    mac as string
};

/**
 * A NAT network, from `natNets`.
 *
 * @field name {string} its name, which a NIC of type `natnetwork` names
 * @field network {string} its IPv4 network, such as `10.0.2.0/24`
 * @field gateway {string} the gateway's IPv4 address
 * @field dhcp {bool} whether its DHCP server is on
 * @field enabled {bool} whether it is enabled
 * @field ipv6 {bool} whether IPv6 is enabled
 */
export def struct NatNet {
    name as string,
    network as string,
    gateway as string,
    dhcp as bool,
    enabled as bool,
    ipv6 as bool
};

/**
 * The host machine, from `hostInfo`.
 *
 * @field processors {int} logical processors
 * @field cores {int} processor cores
 * @field processor {string} the first processor's description
 * @field hardwareVirtualization {bool} whether the processor supports VT-x or AMD-V
 * @field memoryMb {int} memory in MiB
 * @field memoryAvailableMb {int} free memory in MiB
 * @field os {string} the host OS, such as `Linux`
 * @field osVersion {string} its version
 */
export def struct HostInfo {
    processors as int,
    cores as int,
    processor as string,
    hardwareVirtualization as bool,
    memoryMb as int,
    memoryAvailableMb as int,
    os as string,
    osVersion as string
};

/**
 * Every registered machine.
 *
 * @param h {Host} the host
 * @return {list of Vm} the machines, in VirtualBox's order
 * @throws {Error} kind "virtualbox" if `VBoxManage` fails
 * @example
 *   for (def m in virtualbox.vms($vb)) {
 *       io.printf("%s %s\n", $m.uuid, $m.name);
 *   }
 */
export func vms(h as Host) {
    return vmLines(call($h, ["list", "vms"], "list vms"));
}

/**
 * The machines that are running (or paused, or starting).
 *
 * @param h {Host} the host
 * @return {list of Vm} the machines
 * @throws {Error} kind "virtualbox" if `VBoxManage` fails
 */
export func runningVms(h as Host) {
    return vmLines(call($h, ["list", "runningvms"], "list runningvms"));
}

/**
 * Whether a machine is registered, by name or UUID.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @return {bool} whether it is
 * @throws {Error} kind "virtualbox" if the name is unusable or `VBoxManage` fails
 */
export func hasVm(h as Host, vm as string) {
    checkVm($vm);
    for (def m in vms($h)) {
        if ($m.name == $vm or strings.lower($m.uuid) == strings.lower($vm)) {
            return true;
        }
    }
    return false;
}

/**
 * The `"name" {uuid}` lines of `list vms`.
 *
 * @param out {string} the output
 * @return {list of Vm} the machines
 */
func vmLines(out as string) {
    def found as list of Vm init [];
    for (def line in strings.split($out, "\n")) {
        def m as regex.Match init regex.find('^"(.*)" \{([0-9a-fA-F-]+)\}$', strings.trim($line));
        if ($m.start == 0) {
            $found[] = Vm{name: $m.groups[0], uuid: $m.groups[1]};
        }
    }
    return $found;
}

/**
 * The guest OS types VirtualBox knows, for `create`.
 *
 * @param h {Host} the host
 * @return {list of OsType} the types
 * @throws {Error} kind "virtualbox" if `VBoxManage` fails
 */
export func osTypes(h as Host) {
    def out as list of OsType init [];
    for (def b in blocks(call($h, ["list", "--long", "ostypes"], "list ostypes"))) {
        if (field($b, "ID") == "") {
            continue;
        }
        $out[] = OsType{
            id: field($b, "ID"),
            description: field($b, "Description"),
            familyId: field($b, "Family ID"),
            familyDescription: field($b, "Family Desc"),
            is64Bit: isYes(field($b, "64 bit"))
        };
    }
    return $out;
}

/**
 * The virtual disks VirtualBox knows.
 *
 * @param h {Host} the host
 * @return {list of Medium} the disks
 * @throws {Error} kind "virtualbox" if `VBoxManage` fails
 */
export func hdds(h as Host) {
    def out as list of Medium init [];
    for (def b in blocks(call($h, ["list", "hdds"], "list hdds"))) {
        if (field($b, "UUID") == "") {
            continue;
        }
        $out[] = Medium{
            uuid: field($b, "UUID"),
            parentUuid: field($b, "Parent UUID"),
            state: field($b, "State"),
            type: field($b, "Type"),
            location: field($b, "Location"),
            format: field($b, "Storage format"),
            capacityMb: number(field($b, "Capacity"))
        };
    }
    return $out;
}

/**
 * The host-only network interfaces.
 *
 * @param h {Host} the host
 * @return {list of HostOnlyIf} the interfaces
 * @throws {Error} kind "virtualbox" if `VBoxManage` fails
 */
export func hostOnlyIfs(h as Host) {
    def out as list of HostOnlyIf init [];
    for (def b in blocks(call($h, ["list", "hostonlyifs"], "list hostonlyifs"))) {
        if (field($b, "Name") == "") {
            continue;
        }
        $out[] = HostOnlyIf{
            name: field($b, "Name"),
            ip: field($b, "IPAddress"),
            netmask: field($b, "NetworkMask"),
            dhcp: isYes(field($b, "DHCP")),
            status: field($b, "Status"),
            mac: field($b, "HardwareAddress")
        };
    }
    return $out;
}

/**
 * The NAT networks (`list --long natnets`, which adds `Enabled`).
 *
 * @param h {Host} the host
 * @return {list of NatNet} the networks
 * @throws {Error} kind "virtualbox" if `VBoxManage` fails
 */
export func natNets(h as Host) {
    def out as list of NatNet init [];
    for (def b in blocks(call($h, ["list", "--long", "natnets"], "list natnets"))) {
        if (field($b, "Name") == "") {
            continue;
        }
        $out[] = NatNet{
            name: field($b, "Name"),
            network: field($b, "Network"),
            gateway: field($b, "Gateway"),
            dhcp: isYes(field($b, "DHCP Server")),
            enabled: isYes(field($b, "Enabled")),
            ipv6: isYes(field($b, "IPv6"))
        };
    }
    return $out;
}

/**
 * The host machine: processors, memory, OS.
 *
 * @param h {Host} the host
 * @return {HostInfo} the host's description
 * @throws {Error} kind "virtualbox" if `VBoxManage` fails
 */
export func hostInfo(h as Host) {
    def all as map of string to string init {};
    for (def b in blocks(call($h, ["list", "hostinfo"], "list hostinfo"))) {
        for (def k in maps.keys($b)) {
            if (not maps.has($all, $k)) {
                $all[$k] = $b[$k];
            }
        }
    }
    return HostInfo{
        processors: number(fieldOf($all, ["Processor online count", "Processor count"])),
        cores: number(fieldOf($all, ["Processor online core count", "Processor core count"])),
        processor: field($all, "Processor#0 description"),
        hardwareVirtualization: isYes(field($all, "Processor supports HW virtualization")),
        memoryMb: number(field($all, "Memory size")),
        memoryAvailableMb: number(field($all, "Memory available")),
        os: field($all, "Operating system"),
        osVersion: field($all, "Operating system version")
    };
}
