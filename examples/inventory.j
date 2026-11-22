#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * inventory example: list the machines of a VirtualBox host with their state,
 * hardware, NICs and port forwards.
 *
 *   jennifer run examples/inventory.j local
 *   jennifer run examples/inventory.j ssh admin@vmhost
 *
 * Without arguments it prints this usage, so CI runs it without VirtualBox.
 */

use io;
use os;

import "../src/virtualbox.j" as virtualbox;

def args as list of string init os.ARGS;
if (len($args) < 2 or ($args[1] != "local" and $args[1] != "ssh") or
    ($args[1] == "ssh" and len($args) != 3)) {
    io.printf("usage: jennifer run examples/inventory.j local | ssh <user@host>\n");
    exit 0;
}

try {
    def c as virtualbox.Config init virtualbox.local();
    if ($args[1] == "ssh") {
        $c = virtualbox.remote(["ssh", "-o", "BatchMode=yes", $args[2]]);
    }
    def vb as virtualbox.Host init virtualbox.open($c);
    def host as virtualbox.HostInfo init virtualbox.hostInfo($vb);
    io.printf(
        "VirtualBox %s on %s %s, %d processors, %d MiB\n",
        $vb.version,
        $host.os,
        $host.osVersion,
        $host.processors,
        $host.memoryMb);
    for (def m in virtualbox.vms($vb)) {
        if ($m.name == "<inaccessible>") {
            io.printf("%s: inaccessible\n", $m.uuid);
            continue;
        }
        def i as virtualbox.VmInfo init virtualbox.info($vb, $m.uuid);
        io.printf(
            "%s (%s): %s, %d CPU, %d MiB\n",
            $i.name,
            $i.uuid,
            $i.state,
            $i.cpus,
            $i.memoryMb);
        for (def n in $i.nics) {
            io.printf("  nic%d %s %s\n", $n.index, $n.attachment, $n.network);
        }
        for (def f in $i.forwards) {
            io.printf(
                "  nic%d %s %s %s:%d -> %s:%d\n",
                $f.nic,
                $f.name,
                $f.protocol,
                $f.hostIp,
                $f.hostPort,
                $f.guestIp,
                $f.guestPort);
        }
    }
} catch (e) {
    io.printf("%s\n", $e.message);
    exit 1;
}
