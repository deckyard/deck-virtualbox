<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# The guest

## Its IP address

The Guest Additions publish the guest's addresses as guest properties.
`waitForIp` polls the one for a guest interface (counted from 0, unlike the
NIC slots, which count from 1) until it is set:

```jennifer
virtualbox.start($vb, "web");
def ip as string init virtualbox.waitForIp($vb, "web", 0, 180000);
```

It fails after the timeout, which usually means the Guest Additions are not
installed or not running yet; each poll gets at most the time left. `guestIp`
reads it once, `""` when it is not there.

The property can survive a hard power-off, so right after `start` it may
still hold the address of the previous boot. Remove it first when that
matters:

```jennifer
virtualbox.unsetGuestProperty($vb, "web", "/VirtualBox/GuestInfo/Net/0/V4/IP");
virtualbox.start($vb, "web");
def ip as string init virtualbox.waitForIp($vb, "web", 0, 180000);
```

Any guest property works the same way: `guestProperty` reads one (`""` when
unset), `setGuestProperty` and `unsetGuestProperty` change it, for instance
to hand a value to a script in the guest.

```jennifer
use io;

io.printf("%s\n", virtualbox.guestProperty($vb, "web", "/VirtualBox/GuestInfo/OS/Product"));
virtualbox.setGuestProperty($vb, "web", "/myapp/role", "frontend");
```

## Commands and files

With the Guest Additions running, `guestRun` runs a program in the guest as
a guest user and waits for it; `copyTo` and `copyFrom` copy files.

```jennifer
use io;
use os;

def admin as virtualbox.Credentials init virtualbox.credentials("ada", os.getEnv("GUEST_PASSWORD"));
def r as virtualbox.GuestResult init virtualbox.guestRun($vb, "web", $admin,
    ["/usr/bin/uname", "-a"]);
io.printf("%s %d: %s", $r.status, $r.exitCode, $r.stdout);
virtualbox.copyTo($vb, "web", $admin, "/srv/site/index.html", "/var/www/html/index.html");
virtualbox.copyFrom($vb, "web", $admin, "/var/log/syslog", "/tmp/web-syslog");
```

The program is named by its absolute path in the guest; the list is its
whole argument vector, the path first. A command runs within the ordinary
deadline (one minute; `withTimeout` for longer ones).

`VBoxManage` folds the program's exit code into its own: 0 stays 0, 1 to
93 become 33 to 125, anything higher 126, and 18 or 19 mean a signal or an
abnormal end. `GuestResult` undoes that: `status` is `exited`, `killed` or
`abnormal`, and `exitCode` is the program's own code when it exited (-1 for
94 or more, which `VBoxManage` cannot pass on). Every other exit code is a
failure of `VBoxManage` itself (no Guest Additions, a wrong password, a
missing program) and throws, whatever the guest printed.

The password goes to `VBoxManage` through `--passwordfile`, pointed at a
named pipe (mode 0600, in a private directory) that the deck writes the
password into: it never touches the disk, and the directory is removed when
the call returns. `--password` would put it on the command line, where every
user of the host can read it with `ps`. For the same reason these three calls
are refused over a command prefix: the password would have to reach the
remote host.

## Shared folders

```jennifer
virtualbox.addSharedFolder($vb, "web", "site", "/srv/site", true, true);
```

shares `/srv/site` read-only as `site`, mounted by the Guest Additions at
boot (on Linux™ under `/media/sf_site`). `sharedFolders` lists them with a
`scope`: `machine` for the machine's own, `transient` for those added to a
running machine by other tools, `global` for those every machine sees.
`removeSharedFolder` stops sharing one of the machine's own.
