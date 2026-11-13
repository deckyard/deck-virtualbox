<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Remote hosts and safety

## Another machine

`remote` runs `VBoxManage` under a command prefix, usually `ssh`:

```jennifer
def c as virtualbox.Config init virtualbox.remote(["ssh", "-o", "BatchMode=yes", "admin@vmhost"]);
def vb as virtualbox.Host init virtualbox.open($c);
```

`ssh` joins the arguments after the host into one command line for the
remote user's login shell, so the deck quotes each of them for POSIX `sh`:
a machine named `it's mine; rm -rf /` stays one argument. That holds when the
login shell is sh, bash, dash, ksh or zsh. fish reads `\` inside single
quotes and csh `!`, so the deck refuses any argument holding either over a
prefix; a Windows host's cmd or PowerShell does not take `sh` quoting at all
and is not supported. Use key authentication (`BatchMode=yes` makes a
missing key fail at once instead of waiting for a password). Paths are paths
on the remote host.

The prefix must hand one command line to a shell, as `ssh` does. A prefix
without one (`sudo`, `env`, `docker exec`) would pass the quotes on
literally and every call fails; for `sudo`, point `withBinary` at a wrapper
script that runs `sudo VBoxManage "$@"` instead.

A deadline ends the local `ssh`. sshd sends the remote command no signal
for it, so `VBoxManage` on the other side runs on until it next writes, and
an operation it started inside VirtualBox (a clone, an import) finishes
regardless: check the machine's state before trying again. The calls that
need a guest password (`guestRun`, `copyTo`, `copyFrom`) are refused over a
prefix.

For a host without `ssh`, VirtualBox's SOAP web service is the other way
in; it is not part of this deck.

## What the deck checks

`VBoxManage` is started with an argument list, never through a local shell,
and every value is checked before it reaches it:

- machine, snapshot, controller, folder and rule names: not empty, at most
  255 characters, no control characters, not starting with `-` (which
  `VBoxManage` would read as an option);
- paths: the same, at most 4096 characters; write `./-file` for a file whose
  name starts with `-`;
- numbers (processors, memory, ports, NIC slots, sizes) within VirtualBox's
  ranges;
- fixed choices (NIC attachments, buses, firmware, start modes, protocols)
  from their lists; rule names without commas; forward addresses as IP
  addresses.

Error messages quote what `VBoxManage` printed, cut to 300 characters, with
control characters and the bidi controls that reorder a terminal line
replaced. `attachDisk` and `attachDvd` refuse paths that `VBoxManage` reads
as keywords (`none`, `additions`, `iscsi`, `host:...`; `emptydrive` except
in a DVD drive): write `./none` for a file of that name.

A guest's output reaches you as data, never as the deck's decisions:
`guestRun` tells a failure of `VBoxManage` from the program's own result by
the exit code alone, so a guest printing `VBoxManage: error:` cannot make it
throw.

`virtualbox.run` passes its arguments as they are, options included: build
them from trusted values only.
