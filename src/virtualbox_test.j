# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * White-box tests: jennifer test src/virtualbox_test.j (from the deck root)
 *
 * No test needs VirtualBox. A fake `VBoxManage` (POSIX sh) stands in: it
 * records each argument list and answers with output written in the formats
 * of the VBoxManage 7.0.6 and 7.1.4 sources (not recorded from a live host).
 * Both live in `topics/fixtures/vbox_test.j`, inside src/, because jvc runs
 * the overlays from a copy of src/ alone. The topic overlays are fragments
 * spliced in here, not standalone suites.
 */
use testing;

include "topics/core_test.j";
include "topics/parse_test.j";
include "topics/inventory_test.j";
include "topics/machine_test.j";
include "topics/power_test.j";
include "topics/snapshots_test.j";
include "topics/guest_test.j";
