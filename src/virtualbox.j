# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0
# pragma-jennifer-capability: exec

/**
 * Oracle VirtualBox 7 through its `VBoxManage` command line: inventories,
 * machine details, creating and deleting machines, power, NAT port forwards,
 * snapshots, clones, OVA import and export, guest properties, commands and
 * files in the guest, and shared folders.
 *
 * `VBoxManage` runs with an argument list, never through a local shell.
 * Machine names, paths and options are checked before they reach it; a guest
 * password goes through a named pipe, never the disk or the command line. A
 * `Config` with an `ssh` prefix runs `VBoxManage` on another machine whose
 * login shell is POSIX sh. Every call has a deadline and a bound on the
 * output it parses, and every failure is `Error{kind: "virtualbox"}`.
 * Linux, macOS or another Unix: `VBoxManage` runs through `env LC_ALL=C.UTF-8`.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | `Config`, `Host`, `open`, the checks, running `VBoxManage`, errors, `run` |
 * | `parse` | the `--machinereadable` and `list` output parsers |
 * | `inventory` | machines, OS types, disks, host-only interfaces, NAT networks, the host |
 * | `machine` | `info`, create, register, delete, settings, NICs, storage, disks |
 * | `power` | start, stop, pause, save; NAT port forwards |
 * | `snapshots` | snapshots, clones, OVA / OVF import and export |
 * | `guest` | guest properties and the IP, commands and copies in the guest, shared folders |
 *
 * @module virtualbox
 * @see https://www.virtualbox.org/manual/ch08.html
 * @example
 *   def vb as virtualbox.Host init virtualbox.open(virtualbox.local());
 *   virtualbox.start($vb, "web");
 *   io.printf("%s\n", virtualbox.waitForIp($vb, "web", 0, 120000));
 */
use convert;
use fs;
use lists;
use maps;
use os;
use regex;
use strings;
use task;
use time;

include "topics/core.j";
include "topics/parse.j";
include "topics/inventory.j";
include "topics/machine.j";
include "topics/power.j";
include "topics/snapshots.j";
include "topics/guest.j";
