#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * buildvm example: a throw-away build machine from an appliance. It imports
 * the appliance, forwards host port 2222 to the guest's SSH, starts it, waits
 * for its IP, runs `uname -a` in it and powers it off again; with `--keep`
 * it keeps the machine, else it deletes it.
 *
 *   GUEST_PASSWORD=... jennifer run examples/buildvm.j debian.ova build-1 ada [--keep]
 *
 * The appliance needs the Guest Additions. Without arguments it prints this
 * usage, so CI runs it without VirtualBox.
 */

use io;
use os;
use time;

import "../src/virtualbox.j" as virtualbox;

def args as list of string init os.ARGS;
if (len($args) < 4) {
    io.printf("usage: GUEST_PASSWORD=... jennifer run examples/buildvm.j ");
    io.printf("<appliance.ova> <name> <guest-user> [--keep]\n");
    exit 0;
}
def appliance as string init $args[1];
def name as string init $args[2];
def admin as virtualbox.Credentials init virtualbox.credentials(
    $args[3],
    os.getEnv("GUEST_PASSWORD"));
def keep as bool init len($args) > 4 and $args[4] == "--keep";

/**
 * Delete a machine that was just powered off. VirtualBox releases the
 * machine's session a moment after `powerOff` returns, so a delete right
 * away can find it still locked; wait for `poweroff` and retry a few times.
 *
 * @param vb {virtualbox.Host} the host
 * @param name {string} the machine
 */
func deleteWhenUnlocked(vb as virtualbox.Host, name as string) {
    def tries as int init 0;
    while (true) {
        try {
            if (virtualbox.state($vb, $name) == "poweroff") {
                virtualbox.delete($vb, $name);
                return;
            }
        } catch (e) {
            if (virtualbox.errorCode($e) != "VBOX_E_INVALID_OBJECT_STATE" or $tries >= 20) {
                throw $e;
            }
        }
        $tries = $tries + 1;
        if ($tries > 20) {
            throw Error{kind: "virtualbox", message: $name + " did not power off within 10 s"};
        }
        time.sleep(time.fromMilliseconds(500));
    }
}

def vb as virtualbox.Host;
try {
    $vb = virtualbox.open(virtualbox.local());
    if (virtualbox.hasVm($vb, $name)) {
        io.printf("%s exists already\n", $name);
        exit 1;
    }
    io.printf("importing %s as %s\n", $appliance, $name);
    virtualbox.importAs($vb, $appliance, $name);
} catch (e) {
    io.printf("%s\n", $e.message);
    exit 1;
}

def failed as bool init false;
try {
    virtualbox.addForward($vb, $name, virtualbox.forward(1, "ssh", 2222, 22));
    virtualbox.start($vb, $name);
    io.printf(
        "up at %s; ssh -p 2222 %s@127.0.0.1\n",
        virtualbox.waitForIp($vb, $name, 0, 300000),
        $admin.username);
    def r as virtualbox.GuestResult init virtualbox.guestRun(
        $vb,
        $name,
        $admin,
        ["/usr/bin/uname", "-a"]);
    io.printf("uname (%s %d): %s", $r.status, $r.exitCode, $r.stdout);
} catch (e) {
    io.printf("%s\n", $e.message);
    $failed = true;
}

try {
    if (virtualbox.state($vb, $name) == "running") {
        virtualbox.powerOff($vb, $name);
    }
    if (not $keep) {
        deleteWhenUnlocked($vb, $name);
        io.printf("deleted %s\n", $name);
    }
} catch (e) {
    io.printf("cleanup: %s\n", $e.message);
    $failed = true;
}
if ($failed) {
    exit 1;
}
