# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualbox - snapshots: snapshots, clones, and OVA / OVF import and export.
# Spliced into virtualbox.j via include.

/**
 * A snapshot of a machine, from `snapshots`.
 *
 * @field name {string} its name
 * @field uuid {string} its UUID
 * @field description {string} its description, `""` if it has none
 * @field depth {int} how deep in the tree it is: 0 for the first snapshot, 1 for one taken from it, ...
 * @field current {bool} whether the machine runs from it
 */
export def struct Snapshot {
    name as string,
    uuid as string,
    description as string,
    depth as int,
    current as bool
};

/**
 * A machine's snapshots, as a tree in depth-first order (parents before
 * children).
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @return {list of Snapshot} the snapshots, empty without any
 * @throws {Error} kind "virtualbox" as `info`
 * @example
 *   for (def s in virtualbox.snapshots($vb, "web")) {
 *       io.printf("%s%s\n", strings.repeat("  ", $s.depth), $s.name);
 *   }
 */
export func snapshots(h as Host, vm as string) {
    checkVm($vm);
    return snapshotsFrom(pairs(call(
        $h,
        ["showvminfo", $vm, "--machinereadable"],
        "showvminfo " + $vm)));
}

/**
 * The snapshots in `showvminfo --machinereadable` lines: `SnapshotName`,
 * `SnapshotName-1`, `SnapshotName-1-1`, ..., each suffix a step down the
 * tree, with `SnapshotUUID` and `SnapshotDescription` under the same suffix.
 *
 * @param lines {list of Pair} the lines
 * @return {list of Snapshot} the snapshots
 */
func snapshotsFrom(lines as list of Pair) {
    def m as map of string to string init pairMap($lines);
    def current as string init strings.lower(field($m, "CurrentSnapshotUUID"));
    def out as list of Snapshot init [];
    for (def p in $lines) {
        if (not strings.startsWith($p.key, "SnapshotName")) {
            continue;
        }
        def s as regex.Match init regex.find('^SnapshotName((-[0-9]+)*)$', $p.key);
        if ($s.start != 0) {
            continue;
        }
        def suffix as string init $s.groups[0];
        def uuid as string init field($m, "SnapshotUUID" + $suffix);
        $out[] = Snapshot{
            name: $p.value,
            uuid: $uuid,
            description: field($m, "SnapshotDescription" + $suffix),
            depth: strings.count($suffix, "-"),
            current: $uuid != "" and strings.lower($uuid) == $current
        };
    }
    return $out;
}

/**
 * Take a snapshot. A running machine is paused while it is taken.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param name {string} the snapshot's name
 * @param description {string} its description, `""` for none
 * @return {string} the snapshot's UUID
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 * @example
 *   virtualbox.takeSnapshot($vb, "web", "before-upgrade", "");
 */
export func takeSnapshot(h as Host, vm as string, name as string, description as string) {
    checkVm($vm);
    checkName($name, "the snapshot name");
    def args as list of string init ["snapshot", $vm, "take", $name];
    if ($description != "") {
        checkText($description, "the description");
        $args[] = "--description";
        $args[] = $description;
    }
    return printedUuid(
        callLong($h, $args, "snapshot " + $vm + " take"),
        "snapshot " + $vm + " take");
}

/**
 * Return a powered-off machine to a snapshot.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param name {string} the snapshot's name or UUID
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses (the machine runs, no such snapshot)
 */
export func restoreSnapshot(h as Host, vm as string, name as string) {
    checkVm($vm);
    checkName($name, "the snapshot name");
    callLong($h, ["snapshot", $vm, "restore", $name], "snapshot " + $vm + " restore");
}

/**
 * Delete a snapshot, merging its changes into the disks after it.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param name {string} the snapshot's name or UUID
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func deleteSnapshot(h as Host, vm as string, name as string) {
    checkVm($vm);
    checkName($name, "the snapshot name");
    callLong($h, ["snapshot", $vm, "delete", $name], "snapshot " + $vm + " delete");
}

/**
 * Copy a machine and its disks into a new, registered machine (a full
 * clone), within the long deadline.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param newName {string} the clone's name
 * @throws {Error} kind "virtualbox" if a name is unusable or VirtualBox refuses
 * @example
 *   virtualbox.clone($vb, "template", "web2");
 */
export func clone(h as Host, vm as string, newName as string) {
    checkVm($vm);
    checkName($newName, "the clone's name");
    callLong($h, ["clonevm", $vm, "--name", $newName, "--register"], "clonevm " + $vm);
}

/**
 * Make a linked clone: a new, registered machine whose disks are difference
 * images on a snapshot's disks. Fast and small, but tied to that snapshot.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param snapshot {string} the snapshot the clone starts from
 * @param newName {string} the clone's name
 * @throws {Error} kind "virtualbox" if a name is unusable or VirtualBox refuses
 */
export func linkedClone(h as Host, vm as string, snapshot as string, newName as string) {
    checkVm($vm);
    checkName($snapshot, "the snapshot name");
    checkName($newName, "the clone's name");
    callLong(
        $h,
        [
            "clonevm",
            $vm,
            "--snapshot",
            $snapshot,
            "--options",
            "link",
            "--name",
            $newName,
            "--register"
        ],
        "clonevm " + $vm);
}

/**
 * Import an appliance (`.ova` or `.ovf`) as VirtualBox names it, within the
 * long deadline.
 *
 * @param h {Host} the host
 * @param path {string} the appliance file
 * @throws {Error} kind "virtualbox" if the path is unusable or VirtualBox refuses
 */
export func importOva(h as Host, path as string) {
    checkAppliance($path);
    callLong($h, ["import", $path], "import");
}

/**
 * Import an appliance's first machine under a name of your choice.
 *
 * @param h {Host} the host
 * @param path {string} the appliance file
 * @param name {string} the imported machine's name
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses (the name is taken)
 * @example
 *   virtualbox.importAs($vb, "/srv/images/debian.ova", "build-1");
 */
export func importAs(h as Host, path as string, name as string) {
    checkAppliance($path);
    checkName($name, "the machine name");
    callLong($h, ["import", $path, "--vsys", "0", "--vmname", $name], "import");
}

/**
 * Export a powered-off machine to an appliance, within the long deadline.
 * The file name's extension picks the form: `.ova` one archive, `.ovf`
 * a descriptor with the disks beside it.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param path {string} the appliance file to write
 * @throws {Error} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func exportOva(h as Host, vm as string, path as string) {
    checkVm($vm);
    checkAppliance($path);
    callLong($h, ["export", $vm, "--output", $path], "export " + $vm);
}

/**
 * Refuse an appliance path: a path ending in `.ova` or `.ovf`.
 *
 * @param path {string} the path
 * @throws {Error} kind "virtualbox" if it is unusable
 */
func checkAppliance(path as string) {
    checkPath($path, "the appliance file");
    def lower as string init strings.lower($path);
    if (not strings.endsWith($lower, ".ova") and not strings.endsWith($lower, ".ovf")) {
        fail("the appliance file must end in .ova or .ovf, got " + shown($path));
    }
}
