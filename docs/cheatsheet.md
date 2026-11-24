<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# virtualbox cheatsheet

Every export of `@deckyard/virtualbox`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/virtualbox/" as virtualbox;
```

Every failure is a `VirtualboxError` (kind `"virtualbox"`), except a
`VBoxManage` output over the caps (kind `"limit"`) and a cancelled task (kind
`"cancelled"`). A `c` argument is a `Config`,
an `h` a `Host`, a `vm` a machine's name or UUID.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `DEFAULT_TIMEOUT_MS` | `60000` | how long an ordinary call may run |
| `DEFAULT_LONG_TIMEOUT_MS` | `3600000` | how long an import, export, clone or snapshot may run |
| `MIN_MAJOR` | `7` | the oldest VirtualBox™ major version `open` accepts |

## Connecting

| Function | Returns | Does |
|---|---|---|
| `virtualbox.local()` | `Config` | run `VBoxManage` from `PATH` here |
| `virtualbox.remote(prefix)` | `Config` | run it through `ssh` (a prefix that hands one command line to a POSIX remote login shell); every argument is quoted for `sh`, and `\` and `!` are refused |
| `virtualbox.withBinary(c, binary)` | `Config` | another `VBoxManage` program |
| `virtualbox.withTimeout(c, ms)` | `Config` | the deadline of an ordinary call, 1 to 86400000 ms |
| `virtualbox.withLongTimeout(c, ms)` | `Config` | the deadline of import, export, clone, snapshots and guest copies |
| `virtualbox.open(c)` | `Host` | run `VBoxManage --version`; refuse VirtualBox older than 7 |
| `virtualbox.run(h, args)` | `string` | any other subcommand, arguments as given; its output |
| `virtualbox.errorCode(e)` | `string` | a `VirtualboxError`'s `code`: the `VBOX_E_*` / `E_*` / `NS_ERROR_*` code, `""` if none (read `$e.code` directly) |

## Inventory

| Function | Returns | Does |
|---|---|---|
| `virtualbox.vms(h)` | `list of Vm` | every registered machine |
| `virtualbox.runningVms(h)` | `list of Vm` | the running ones |
| `virtualbox.hasVm(h, vm)` | `bool` | whether a machine is registered |
| `virtualbox.osTypes(h)` | `list of OsType` | the guest OS types, for `create` |
| `virtualbox.hdds(h)` | `list of Medium` | the virtual disks |
| `virtualbox.hostOnlyIfs(h)` | `list of HostOnlyIf` | the host-only interfaces |
| `virtualbox.natNets(h)` | `list of NatNet` | the NAT networks |
| `virtualbox.hostInfo(h)` | `HostInfo` | the host's processors, memory and OS |

## Machines

| Function | Returns | Does |
|---|---|---|
| `virtualbox.info(h, vm)` | `VmInfo` | state, hardware, NICs, forwards, storage, folders |
| `virtualbox.state(h, vm)` | `string` | `poweroff`, `running`, `paused`, `saved`, ... |
| `virtualbox.create(h, name, osType)` | `string` | create and register a machine; its UUID |
| `virtualbox.createIn(h, name, osType, baseFolder)` | `string` | the same, under another folder |
| `virtualbox.register(h, settingsFile)` | `null` | register a `.vbox` file |
| `virtualbox.unregister(h, vm)` | `null` | unregister, keeping the files |
| `virtualbox.delete(h, vm)` | `null` | unregister and delete the files |
| `virtualbox.setCpus(h, vm, cpus)` | `null` | processors, 1 to 64 |
| `virtualbox.setMemory(h, vm, memoryMb)` | `null` | memory, 4 to 2097152 MiB |
| `virtualbox.setFirmware(h, vm, firmware)` | `null` | `bios`, `efi`, `efi32`, `efi64` |
| `virtualbox.setNic(h, vm, index, attachment, network)` | `null` | attach NIC 1 to 36: `nat`, `bridged`, `hostonly`, `intnet`, `natnetwork`, `null`, `none` |
| `virtualbox.addController(h, vm, name, bus)` | `null` | a storage controller: `ide`, `sata`, `scsi`, `floppy`, `sas`, `usb`, `pcie`, `virtio` |
| `virtualbox.attachDisk(h, vm, controller, port, device, path)` | `null` | a disk image on a port; VBoxManage™'s medium keywords (`none`, `host:...`) are refused |
| `virtualbox.attachDvd(h, vm, controller, port, device, path)` | `null` | a DVD drive with an `.iso`, or `emptydrive` |
| `virtualbox.detach(h, vm, controller, port, device)` | `null` | empty a port |
| `virtualbox.createDisk(h, path, sizeMb)` | `string` | a dynamically growing `.vdi`; its UUID |

## Power and port forwards

| Function | Returns | Does |
|---|---|---|
| `virtualbox.start(h, vm)` | `null` | start without a window |
| `virtualbox.startWith(h, vm, mode)` | `null` | start `headless`, `gui` or `separate` |
| `virtualbox.powerOff(h, vm)` | `null` | pull the plug |
| `virtualbox.acpiShutdown(h, vm)` | `null` | press the power button; the guest shuts down |
| `virtualbox.pause(h, vm)` | `null` | pause |
| `virtualbox.resume(h, vm)` | `null` | resume |
| `virtualbox.reset(h, vm)` | `null` | press reset |
| `virtualbox.saveState(h, vm)` | `null` | save the state to disk and stop |
| `virtualbox.forwards(h, vm)` | `list of Forward` | the NAT port forwards of every NIC |
| `virtualbox.forward(nic, name, hostPort, guestPort)` | `Forward` | a TCP rule on all host addresses |
| `virtualbox.addForward(h, vm, rule)` | `null` | add a rule, running or stopped |
| `virtualbox.removeForward(h, vm, nic, name)` | `null` | remove a rule |

## Snapshots, clones, appliances

| Function | Returns | Does |
|---|---|---|
| `virtualbox.snapshots(h, vm)` | `list of Snapshot` | the snapshot tree, parents first |
| `virtualbox.takeSnapshot(h, vm, name, description)` | `string` | take one; its UUID |
| `virtualbox.restoreSnapshot(h, vm, name)` | `null` | go back to one (machine off) |
| `virtualbox.deleteSnapshot(h, vm, name)` | `null` | delete one |
| `virtualbox.clone(h, vm, newName)` | `null` | a full, registered copy |
| `virtualbox.linkedClone(h, vm, snapshot, newName)` | `null` | a copy on difference disks from a snapshot |
| `virtualbox.importOva(h, path)` | `null` | import an `.ova` / `.ovf` |
| `virtualbox.importAs(h, path, name)` | `null` | the same, naming the machine |
| `virtualbox.exportOva(h, vm, path)` | `null` | export to an `.ova` / `.ovf` |

## The guest

| Function | Returns | Does |
|---|---|---|
| `virtualbox.guestProperty(h, vm, key)` | `string` | a guest property, `""` when unset |
| `virtualbox.setGuestProperty(h, vm, key, value)` | `null` | set one |
| `virtualbox.unsetGuestProperty(h, vm, key)` | `null` | remove one |
| `virtualbox.guestIp(h, vm, nic)` | `string` | the IPv4 address of guest interface `nic` (from 0), `""` if none yet |
| `virtualbox.waitForIp(h, vm, nic, timeoutMs)` | `string` | wait for that address |
| `virtualbox.credentials(username, password)` | `Credentials` | a guest account |
| `virtualbox.guestRun(h, vm, account, argv)` | `GuestResult` | run a program in the guest and wait; how it ended and its own exit code |
| `virtualbox.copyTo(h, vm, account, hostPath, guestPath)` | `null` | copy a file into the guest |
| `virtualbox.copyFrom(h, vm, account, guestPath, hostPath)` | `null` | copy a file out of the guest |
| `virtualbox.sharedFolders(h, vm)` | `list of SharedFolder` | the shared folders |
| `virtualbox.addSharedFolder(h, vm, name, hostPath, readOnly, autoMount)` | `null` | share a host directory |
| `virtualbox.removeSharedFolder(h, vm, name)` | `null` | stop sharing it |

## Types

### `Config`

| Field | Meaning |
|---|---|
| `binary as string` | the `VBoxManage` program |
| `prefix as list of string` | the command it runs under; empty to run it here |
| `timeoutMs as int` | the deadline of an ordinary call |
| `longTimeoutMs as int` | the deadline of the long operations |

### `Host`

| Field | Meaning |
|---|---|
| `config as Config` | how it is reached |
| `version as string` | `VBoxManage --version`, such as `7.1.4r165100` |
| `major as int` | the major version |
| `minor as int` | the minor version |

### `Vm`

| Field | Meaning |
|---|---|
| `name as string` | the machine's name |
| `uuid as string` | its UUID |

### `OsType`

| Field | Meaning |
|---|---|
| `id as string` | the id `create` takes, such as `Ubuntu_64` |
| `description as string` | its name |
| `familyId as string` | the family, such as `Linux` |
| `familyDescription as string` | the family's name |
| `is64Bit as bool` | a 64-bit OS |

### `Medium`

| Field | Meaning |
|---|---|
| `uuid as string` | the disk's UUID |
| `parentUuid as string` | its parent, `base` for a base disk |
| `state as string` | `created`, `inaccessible`, ... |
| `type as string` | `normal (base)`, `normal (differencing)`, ... |
| `location as string` | its file |
| `format as string` | `VDI`, `VMDK`, `VHD`, ... |
| `capacityMb as int` | its size in MiB |

### `HostOnlyIf`

| Field | Meaning |
|---|---|
| `name as string` | such as `vboxnet0` |
| `ip as string` | the host's IPv4 address on it |
| `netmask as string` | its network mask |
| `dhcp as bool` | configured by DHCP |
| `status as string` | `Up` or `Down` |
| `mac as string` | its hardware address |

### `NatNet`

| Field | Meaning |
|---|---|
| `name as string` | the network's name |
| `network as string` | such as `10.0.2.0/24` |
| `gateway as string` | the gateway address |
| `dhcp as bool` | its DHCP server is on |
| `enabled as bool` | it is enabled |
| `ipv6 as bool` | IPv6 is on |

### `HostInfo`

| Field | Meaning |
|---|---|
| `processors as int` | logical processors |
| `cores as int` | processor cores |
| `processor as string` | the first processor's description |
| `hardwareVirtualization as bool` | VT-x or AMD-V |
| `memoryMb as int` | memory in MiB |
| `memoryAvailableMb as int` | free memory in MiB |
| `os as string` | the host OS |
| `osVersion as string` | its version |

### `Nic`

| Field | Meaning |
|---|---|
| `index as int` | the slot, from 1 |
| `attachment as string` | in lower case: `nat`, `bridged`, `hostonly`, `intnet`, `natnetwork`, `generic`, ... |
| `model as string` | the emulated card |
| `mac as string` | 12 hex digits |
| `connected as bool` | the cable is connected |
| `network as string` | the host interface or network it is attached to |

### `Forward`

| Field | Meaning |
|---|---|
| `nic as int` | the NIC, from 1 |
| `name as string` | the rule's name |
| `protocol as string` | `tcp` or `udp` |
| `hostIp as string` | the host address, `""` for all |
| `hostPort as int` | the host port |
| `guestIp as string` | the guest address, `""` for its DHCP address |
| `guestPort as int` | the guest port |

### `Controller`

| Field | Meaning |
|---|---|
| `name as string` | such as `SATA` |
| `type as string` | the emulated chip |
| `ports as int` | its port count |
| `bootable as bool` | the machine may boot from it |

### `Attachment`

| Field | Meaning |
|---|---|
| `controller as string` | the controller |
| `port as int` | the port |
| `device as int` | the device on it |
| `medium as string` | the image file, or `emptydrive` |

### `SharedFolder`

| Field | Meaning |
|---|---|
| `name as string` | its name in the guest |
| `hostPath as string` | the host directory |
| `scope as string` | `machine`, `transient` (until the machine stops) or `global` (every machine) |

### `VmInfo`

| Field | Meaning |
|---|---|
| `name as string` | the machine's name |
| `uuid as string` | its UUID |
| `osType as string` | its guest OS type, as described |
| `state as string` | `poweroff`, `running`, ... |
| `memoryMb as int` | memory in MiB |
| `vramMb as int` | video memory in MiB |
| `cpus as int` | processors |
| `firmware as string` | `BIOS`, `EFI`, ... |
| `configFile as string` | its `.vbox` file |
| `guestAdditions as string` | the running Guest Additions' version, `""` if none |
| `currentSnapshot as string` | the current snapshot's name |
| `nics as list of Nic` | the enabled NICs |
| `forwards as list of Forward` | the NAT port forwards |
| `controllers as list of Controller` | the storage controllers |
| `attachments as list of Attachment` | what is attached to them |
| `sharedFolders as list of SharedFolder` | the shared folders |
| `raw as map of string to string` | every `showvminfo --machinereadable` value |

### `Snapshot`

| Field | Meaning |
|---|---|
| `name as string` | its name |
| `uuid as string` | its UUID |
| `description as string` | its description |
| `depth as int` | 0 for a first snapshot, 1 below it, ... |
| `current as bool` | the machine runs from it |

### `Credentials`

| Field | Meaning |
|---|---|
| `username as string` | the guest user |
| `password as string` | the password, passed through a named pipe, never on disk or a command line |

### `GuestResult`

| Field | Meaning |
|---|---|
| `status as string` | `exited`, `killed` (by a signal) or `abnormal` |
| `exitCode as int` | its exit code when `exited`: 0 to 93, -1 for 94 or more; -1 otherwise |
| `stdout as string` | its standard output |
| `stderr as string` | its error output |

### `VirtualboxError`

Every error of kind `"virtualbox"`.

| Field | Meaning |
|---|---|
| `kind as string` | always `"virtualbox"` |
| `message as string` | `virtualbox: ` and what went wrong |
| `reason as string` | `"exit"` (`VBoxManage` failed), `"timeout"` (no answer within the deadline), `""` otherwise |
| `code as string` | the `VBOX_E_*` / `E_*` / `NS_ERROR_*` code `VBoxManage` named, `""` if none |
| `exitCode as int` | `VBoxManage`'s exit code when `reason` is `"exit"`, 0 otherwise |
