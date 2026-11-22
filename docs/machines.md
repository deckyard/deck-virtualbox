<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Machines

## Looking around

```jennifer
use io;

for (def m in virtualbox.vms($vb)) {
    def i as virtualbox.VmInfo init virtualbox.info($vb, $m.uuid);
    io.printf("%-20s %-10s %d CPU %5d MiB\n", $i.name, $i.state, $i.cpus, $i.memoryMb);
}
```

`info` reads `VBoxManage showvminfo --machinereadable` into a `VmInfo`: the
state, hardware, the enabled NICs (`nics`), the NAT port forwards of each
(`forwards`), the storage controllers and what is attached to them, and the
shared folders. `raw` keeps every value of that output, for the fields the
struct does not name (`raw["chipset"]`, `raw["VMStateChangeTime"]`); a
multi-line description is one value. `state` reads only the state, so it
stays cheap for a machine with thousands of snapshots.

The inventories are `vms`, `runningVms`, `osTypes`, `hdds`, `hostOnlyIfs`,
`natNets` and `hostInfo`.

## Building a machine

A machine from nothing: create it, size it, give it a disk and an
installer, and a NIC.

```jennifer
def name as string init "web";
virtualbox.create($vb, $name, "Ubuntu_64");
virtualbox.setCpus($vb, $name, 2);
virtualbox.setMemory($vb, $name, 4096);
virtualbox.setFirmware($vb, $name, "efi");
virtualbox.setNic($vb, $name, 1, "nat", "");
virtualbox.addController($vb, $name, "SATA", "sata");
virtualbox.createDisk($vb, "/srv/vms/web/web.vdi", 20480);
virtualbox.attachDisk($vb, $name, "SATA", 0, 0, "/srv/vms/web/web.vdi");
virtualbox.attachDvd($vb, $name, "SATA", 1, 0, "/srv/iso/ubuntu-24.04-live-server-amd64.iso");
```

The OS type is an `id` from `osTypes` (`Ubuntu_64`, `Debian_64`,
`Windows11_64`). Settings change only while the machine is powered off;
VirtualBox refuses otherwise: the machine is locked by its running session
(`VBOX_E_INVALID_OBJECT_STATE`).

A NIC is `nat` (the default, outbound only), `bridged` to a host interface,
`hostonly` on a `vboxnet` interface, `intnet` on an internal network,
`natnetwork` on a NAT network, `null` (a cable to nowhere) or `none` (no
card). The second argument names the interface or network:

```jennifer
virtualbox.setNic($vb, "web", 2, "bridged", "eth0");
```

`delete` unregisters a machine and deletes its settings, logs, saved states
and the disk images attached to it; `unregister` keeps them, and `register`
brings a `.vbox` file back.

## Power

```jennifer
virtualbox.start($vb, "web");              # headless
virtualbox.acpiShutdown($vb, "web");       # ask the guest to shut down
virtualbox.powerOff($vb, "web");           # or pull the plug
```

`startWith($vb, "web", "gui")` opens a window. `pause`, `resume`, `reset`
and `saveState` do what the VirtualBox menu does. `acpiShutdown` returns at
once; poll `state` until it reads `poweroff`.

## Port forwards

A NAT NIC reaches the guest through port forwards. `forward` makes a TCP
rule on all host addresses; change its fields for UDP or a fixed address.

```jennifer
virtualbox.addForward($vb, "web", virtualbox.forward(1, "ssh", 2222, 22));
def dns as virtualbox.Forward init virtualbox.forward(1, "dns", 5353, 53);
$dns.protocol = "udp";
$dns.hostIp = "127.0.0.1";
virtualbox.addForward($vb, "web", $dns);
virtualbox.removeForward($vb, "web", 1, "dns");
```

The deck uses `controlvm natpfN` on a running or paused machine and
`modifyvm --natpfN` otherwise, so the same call works either way. A rule
name may not hold a comma, which separates the rule's fields.

## Snapshots and clones

```jennifer
use io;
use strings;

virtualbox.takeSnapshot($vb, "web", "before-upgrade", "kernel 6.8");
for (def s in virtualbox.snapshots($vb, "web")) {
    def mark as string init "";
    if ($s.current) {
        $mark = " (current)";
    }
    io.printf("%s%s%s\n", strings.replicate("  ", $s.depth), $s.name, $mark);
}
virtualbox.restoreSnapshot($vb, "web", "before-upgrade");
```

`snapshots` lists the tree parents first, `depth` giving the level.
Restoring needs the machine powered off. `VBoxManage` prints snapshot names
and descriptions without escaping them, so a name or description holding
`"` at the end of a line can confuse the listing.

`clone` copies a machine and its disks into a new registered machine.
`linkedClone` is much faster and smaller: the clone's disks are difference
images on a snapshot of the original, which then cannot be deleted while
the clone exists.

```jennifer
virtualbox.takeSnapshot($vb, "template", "base", "");
virtualbox.linkedClone($vb, "template", "base", "ci-42");
```

## Appliances

```jennifer
virtualbox.importAs($vb, "/srv/images/debian-12.ova", "build-1");
virtualbox.exportOva($vb, "build-1", "/srv/out/build-1.ova");
```

`importOva` keeps the name the appliance gives. The file name's extension
picks the export form: `.ova` is one archive, `.ovf` a descriptor with the
disks beside it.

## Deadlines

An ordinary call is stopped after `DEFAULT_TIMEOUT_MS` (one minute);
imports, exports, clones, snapshots and guest copies after
`DEFAULT_LONG_TIMEOUT_MS` (one hour). `VBoxManage` cancels a long operation
when it is told to stop and gets 5 seconds for that; if it is still running
then, the call fails saying so, with its pid. Change the deadlines on the
`Config` before `open`:

```jennifer
def c as virtualbox.Config init virtualbox.withLongTimeout(virtualbox.local(), 4 * 3600000);
def vb as virtualbox.Host init virtualbox.open($c);
```
