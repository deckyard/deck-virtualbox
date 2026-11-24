# @deckyard/virtualbox

[![test](https://github.com/deckyard/deck-virtualbox/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-virtualbox/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-virtualbox/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-virtualbox)](https://github.com/deckyard/deck-virtualbox/releases/latest)

Oracle™ VirtualBox™ 7 for [Jennifer](https://jennifer-lang.dev/) programs,
through the `VBoxManage` command line: list machines, disks and networks,
create and delete machines, start and stop them, forward ports, take and
restore snapshots, clone, import and export appliances, read the guest's IP,
and run commands or copy files in the guest. Names and paths are checked
before they reach `VBoxManage`, a guest password never appears on a command
line, and a command prefix (`ssh`) drives a VirtualBox on another machine.

**[Documentation](https://deckyard.github.io/deck-virtualbox/)**

## Install

```sh
jvc add @deckyard/virtualbox
```

This vendors the deck to `vendor/<scope>/virtualbox/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-virtualbox-<version>.tar.gz`) there.

## Usage

```jennifer
use io;

import "@deckyard/virtualbox/" as virtualbox;

def vb as virtualbox.Host init virtualbox.open(virtualbox.local());
virtualbox.importAs($vb, "debian.ova", "build-1");
virtualbox.addForward($vb, "build-1", virtualbox.forward(1, "ssh", 2222, 22));
virtualbox.start($vb, "build-1");
io.printf("up at %s\n", virtualbox.waitForIp($vb, "build-1", 0, 180000));
```

## Requirements

Jennifer 0.27.0 or newer, the default `jennifer` binary (the deck runs
programs, capability `exec`; `jennifer-tiny` cannot), and VirtualBox 7.0 or
newer with `VBoxManage` on `PATH`, here or on the host a prefix reaches.
Commands and copies in the guest need the Guest Additions.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/virtualbox_test.j  # the tests, against a fake VBoxManage
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.

## Trademarks

Oracle™ and VirtualBox™ are trademarks of Oracle Corporation and/or its
affiliates. VBoxManage™ and other product and company names may be
trademarks of their respective owners. They are used only to identify the
products this deck works with. This deck is an independent project, not
affiliated with, sponsored or endorsed by Oracle Corporation.
