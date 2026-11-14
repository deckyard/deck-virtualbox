<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/virtualbox

Oracle VirtualBox 7 from a Jennifer program, through `VBoxManage`, the
command line every VirtualBox install has. The deck covers what scripts that
build and run test machines do by hand:

- **Inventory**: machines, running machines, OS types, disks, host-only
  interfaces, NAT networks, the host.
- **Machines**: their details (state, hardware, NICs, port forwards, storage,
  shared folders); create, register, unregister, delete; processors, memory,
  firmware, NICs, storage controllers, disks and DVDs.
- **Power**: start, power off, ACPI shutdown, pause, resume, reset, save;
  NAT port forwards on running and stopped machines.
- **Snapshots, clones, appliances**: take, list, restore, delete; full and
  linked clones; OVA / OVF import and export.
- **The guest**: guest properties and the IP address it reports, commands and
  file copies inside it (with the Guest Additions), shared folders.

`virtualbox.run` reaches every other `VBoxManage` subcommand.

## Conventions

Snippets assume this import, and add the `use` lines they need:

```jennifer
import "@deckyard/virtualbox/" as virtualbox;
```

The trailing slash resolves to the entry module.

Every call takes the `Host` that `open` returns. `open` runs
`VBoxManage --version` once and refuses VirtualBox older than 7, so a
program fails at its first line instead of halfway through:

```jennifer
use io;

def vb as virtualbox.Host init virtualbox.open(virtualbox.local());
io.printf("VirtualBox %s\n", $vb.version);
```

A machine is named by its name or its UUID. The deck needs the `exec`
capability, so it runs on the default `jennifer` binary, not
`jennifer-tiny`, and a Linux, macOS or other Unix host: it starts
`VBoxManage` through `env LC_ALL=C.UTF-8`, since VirtualBox 7 translates its
output under some locales and the deck reads the English labels, and it
passes a guest password through a named pipe. A host without the `C.UTF-8`
locale still runs every call, but VBoxManage refuses arguments outside ASCII
there (`VERR_NO_TRANSLATION`).

## Errors

Every failure is a `virtualbox.VirtualboxError` (kind `"virtualbox"`), its
message starting with `virtualbox: `:

- an argument the deck refuses before running anything: an empty name, a
  name or path starting with `-`, a control character, a number out of range,
  an unknown option value;
- `VBoxManage` cannot be started, or runs past its deadline. It then gets
  SIGTERM; during an import, export, clone or snapshot it catches that and
  cancels the operation first, so it gets 5 more seconds, after which the
  call gives up and says it left `VBoxManage` running, with its pid. The
  error's `reason` is `"timeout"`;
- `VBoxManage` printed more than 4 Mi characters or 50 000 lines, which no
  real answer does, so the parsers stay within a few hundred MiB. This one is
  a plain `Error` of kind `"limit"`, not a `VirtualboxError`;
- `VBoxManage` fails. The message carries its first error line, its
  `VBOX_E_*` / `E_*` / `NS_ERROR_*` code and the exit code:
  `virtualbox: startvm web: Could not find a registered machine named 'web'
  (VBOX_E_OBJECT_NOT_FOUND, exit 1)`. The error's `reason` is `"exit"`, `code`
  holds the code (`virtualbox.errorCode(e)` returns it too) and `exitCode` the
  exit code.

```jennifer
use io;

try {
    virtualbox.start($vb, "web");
} catch (e) {
    if ($e.kind == "virtualbox" and $e.code == "VBOX_E_INVALID_OBJECT_STATE") {
        io.printf("web is already running\n");
    } else {
        io.printf("%s\n", $e.message);
    }
}
```
