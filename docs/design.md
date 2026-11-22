<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

`@deckyard/virtualbox` drives Oracle VirtualBox 7 through the `VBoxManage`
command-line tool that every VirtualBox install carries: inventories (VMs,
running VMs, OS types, disks, host-only interfaces, NAT networks, host
information), VM details, create, register, unregister and delete, CPU,
memory, firmware, NICs and storage, power, NAT port forwards, snapshots,
clones, OVA and OVF import and export, guest properties (including the
guest's IP address), guest control (run, copy to and from) and shared
folders. `run` reaches any other subcommand.

Not in scope:

- **The SOAP web service.** `vboxwebsrv` is the separate `@deckyard/virtualboxws`
  deck. Capabilities are per deck, and one deck with both backends would make
  every consumer grant both `exec` and `net`.
- **VirtualBox before 7.** `open` refuses an older major version.
- **Windows hosts over a prefix.** Their shells do not take POSIX quoting.
- **`jennifer-tiny`.** It has no `exec` capability.

## Decisions

- **The CLI, never a shell.** `VBoxManage` runs from an argument list through
  `os.spawn`, with `LC_ALL=C.UTF-8` so its output is not translated. Exit
  code 127 means the program is missing.
- **Remote hosts through a command prefix.** `remote` runs `VBoxManage` under
  a prefix such as `["ssh", "user@host"]`. `ssh` joins its arguments into one
  remote shell command, so every argument after the prefix is quoted for
  POSIX `sh`; `\` and `!` are refused because fish and csh read them inside
  single quotes. A prefix must hand one command line to a shell, as `ssh`
  does.
- **Version check once.** `open` runs `VBoxManage --version`, takes the last
  line that looks like a version (a kernel-driver warning can come first) and
  refuses a major below `MIN_MAJOR` (7).
- **Machine-readable output.** `--machinereadable` output (`key="value"`
  lines with indexed keys such as `SATA-0-0`, `natnet1`, `Forwarding(0)`) is
  parsed into typed structs. VBoxManage escapes only `\"` and `\\` and writes
  newlines raw, so a quoted value runs to an unescaped `"` at a line end;
  snapshot keys are printed unescaped and are taken raw. Port forwards are
  read in order under the NIC they follow. `list --long` blocks feed the
  inventories where the short form differs between 7.0 and 7.1.
- **Deadlines.** Ordinary calls get `DEFAULT_TIMEOUT_MS` (60 s); import,
  export, clone, snapshots and guest copies get `DEFAULT_LONG_TIMEOUT_MS`
  (1 hour); both are settable (`withTimeout`, `withLongTimeout`). At the
  deadline the process gets SIGTERM, which VBoxManage traps to cancel its
  operation, then a 5 s grace; a process still running after that is
  reported with its pid, since it cannot be killed harder or released.
- **Guest passwords never on the command line or disk.** `--password` would
  show in `ps`, so the password goes through `--passwordfile` pointed at a
  named pipe (mode 0600) in a private temporary directory, written by a task
  and drained and removed afterwards. These verbs are refused over a prefix,
  because the pipe would have to exist on the remote host.
- **Guest results are data.** `guestRun` tells a failure of `VBoxManage` from
  the guest program's own result by exit code only, never by stderr, so a
  guest printing `VBoxManage: error:` cannot make the deck throw.
- **NAT forwards on a running machine.** `addForward` and `removeForward` use
  `controlvm` for a running or paused machine and `modifyvm` otherwise.
- **Topics layout.** `src/virtualbox.j` includes core, parse, inventory,
  machine, power, snapshots and guest, each with its overlay.

## Errors

- Every error of kind `"virtualbox"` is a `VirtualboxError`: `reason` is
  `"exit"` (VBoxManage ran and failed), `"timeout"` (the deadline passed) or
  `""` (a check before the call, a program that cannot run, unreadable
  output); `code` is the `VBOX_E_*`, `E_*` or `NS_ERROR_*` code VBoxManage
  named; `exitCode` its exit code when `reason` is `"exit"`.
- The message quotes the first meaningful `VBoxManage: error:` line and ends
  with the code and exit code. `errorCode` returns the `code` field; the deck
  itself reads fields, never its own message text.
- Output over the caps is kind `"limit"`; a cancelled task stays
  `"cancelled"`.

## Security and limits

- Every value is checked before it reaches the argument list: names (not
  empty, at most 255 characters, no control characters, not starting with
  `-`), paths (at most 4096 characters), numbers within VirtualBox's ranges,
  fixed choices from their lists, rule names without commas, forward
  addresses as IP addresses. `attachDisk` and `attachDvd` refuse paths that
  VBoxManage reads as keywords (`none`, `additions`, `iscsi`, `host:...`).
- `run` passes its arguments as given; callers build them from trusted
  values.
- Parsed output is capped at 4 MiB and 50,000 lines, because each parsed line
  costs the interpreter several KiB; error output is read up to 64 KiB.
- Text from VBoxManage in an error message is cut to 300 characters, with
  control characters and the bidirectional controls that reorder a terminal
  line replaced.
- A deadline over `ssh` ends the local client only; the remote VBoxManage
  and any operation it started inside VirtualBox may run on.

## Testing and validation

- `src/virtualbox_test.j` includes the seven topic overlays (65 tests). They
  run a fake `VBoxManage` (a POSIX sh script) that logs its arguments and
  answers from canned output, exit code and delay files, records the password
  it was handed and its mode, and can ignore SIGTERM to test the grace
  period.
- The fixtures live in `src/topics/fixtures/vbox_test.j` as constants, because
  the publish gate runs the overlays from a copy of `src/` alone.
- The canned output follows the VBoxManage 7.0.6 and 7.1.4 sources (checked
  2026-11-13), not recordings: no VirtualBox host was available.
- Not covered: a run against a real VirtualBox host, and a real `ssh` prefix.

## Known limitations and open questions

- The parsers should be checked against a real host before 1.0.
- Guest-password verbs over a prefix are not supported in this version.
- A process that ignores SIGTERM past the grace period is left running.

## Dependencies on the interpreter

- Floor `jennifer >=0.27.0`; the default binary (capability `exec`). The
  tests use `strings.replicate`, new in 0.27.0.
- `os.spawn` and `os.kill`, `fs.mkfifo` and private temporary directories,
  tasks for the password writer.
- Thrown structs classified by kind (`jennifer` `6abf345`, the error-struct
  work of M28.51 to M28.57).
