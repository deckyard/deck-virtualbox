# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualbox - power: starting, stopping, pausing and saving machines, and
# NAT port forwards. Spliced into virtualbox.j via include.

# the ways startWith starts a machine
def const START_MODES as list of string init ["headless", "gui", "separate"];

# the states in which a machine takes controlvm, not modifyvm
def const LIVE_STATES as list of string init ["running", "paused"];

/**
 * Start a machine without a window, as a server does.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxError} kind "virtualbox" if the name is unusable or VirtualBox refuses (already running, `VBOX_E_INVALID_OBJECT_STATE`)
 * @example
 *   virtualbox.start($vb, "web");
 */
export func start(h as Host, vm as string) {
    startWith($h, $vm, "headless");
}

/**
 * Start a machine in a given mode.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param mode {string} `headless` (no window), `gui` (a window) or `separate` (headless, with a window that may be closed)
 * @throws {VirtualboxError} kind "virtualbox" if the name or mode is unusable or VirtualBox refuses
 */
export func startWith(h as Host, vm as string, mode as string) {
    checkVm($vm);
    checkChoice($mode, START_MODES, "the start mode");
    call($h, ["startvm", $vm, "--type", $mode], "startvm " + $vm);
}

/**
 * Run a `controlvm` action on a running machine.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param action {string} the action
 * @throws {VirtualboxError} kind "virtualbox" if the name is unusable or VirtualBox refuses
 */
func control(h as Host, vm as string, action as string) {
    checkVm($vm);
    call($h, ["controlvm", $vm, $action], "controlvm " + $vm + " " + $action);
}

/**
 * Turn a machine off at once, as pulling the plug does.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxError} kind "virtualbox" if the name is unusable or the machine is not running
 */
export func powerOff(h as Host, vm as string) {
    control($h, $vm, "poweroff");
}

/**
 * Press the machine's ACPI power button, so the guest shuts down by itself.
 * It returns at once; poll `state` for `poweroff`.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxError} kind "virtualbox" if the name is unusable or the machine is not running
 */
export func acpiShutdown(h as Host, vm as string) {
    control($h, $vm, "acpipowerbutton");
}

/**
 * Pause a running machine.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxError} kind "virtualbox" if the name is unusable or the machine is not running
 */
export func pause(h as Host, vm as string) {
    control($h, $vm, "pause");
}

/**
 * Resume a paused machine.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxError} kind "virtualbox" if the name is unusable or the machine is not paused
 */
export func resume(h as Host, vm as string) {
    control($h, $vm, "resume");
}

/**
 * Reset a running machine, as the reset button does.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxError} kind "virtualbox" if the name is unusable or the machine is not running
 */
export func reset(h as Host, vm as string) {
    control($h, $vm, "reset");
}

/**
 * Save a running machine's state to disk and stop it; `start` resumes it.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxError} kind "virtualbox" if the name is unusable or the machine is not running
 */
export func saveState(h as Host, vm as string) {
    control($h, $vm, "savestate");
}

# --- NAT port forwards -----------------------------------------------------

/**
 * A machine's NAT port forwards, on all its NICs.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @return {list of Forward} the rules
 * @throws {VirtualboxError} kind "virtualbox" as `info`
 */
export func forwards(h as Host, vm as string) {
    return info($h, $vm).forwards;
}

/**
 * A port-forwarding rule, for `addForward`: TCP on every host address to the
 * guest's own address.
 *
 * @param nic {int} the NAT NIC, from 1
 * @param name {string} the rule's name, unique on the NIC
 * @param hostPort {int} the host port
 * @param guestPort {int} the guest port
 * @return {Forward} the rule; change `protocol`, `hostIp` or `guestIp` on it as needed
 * @example
 *   virtualbox.addForward($vb, "web", virtualbox.forward(1, "ssh", 2222, 22));
 */
export func forward(nic as int, name as string, hostPort as int, guestPort as int) {
    return Forward{
        nic: $nic,
        name: $name,
        protocol: "tcp",
        hostIp: "",
        hostPort: $hostPort,
        guestIp: "",
        guestPort: $guestPort
    };
}

/**
 * Add a NAT port forward: `controlvm natpfN` on a running or paused
 * machine, `modifyvm --natpfN` otherwise.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param rule {Forward} the rule, from `forward`
 * @throws {VirtualboxError} kind "virtualbox" if the rule is unusable or VirtualBox refuses (a name or host port in use)
 */
export func addForward(h as Host, vm as string, rule as Forward) {
    checkForward($rule);
    def spec as string init $rule.name + "," + $rule.protocol + "," + $rule.hostIp + "," +
        convert.toString($rule.hostPort) + "," + $rule.guestIp + "," +
        convert.toString($rule.guestPort);
    natpf($h, $vm, $rule.nic, [$spec]);
}

/**
 * Remove a NAT port forward by name.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param nic {int} the NIC, from 1
 * @param name {string} the rule's name
 * @throws {VirtualboxError} kind "virtualbox" if the name is unusable or VirtualBox refuses (no such rule)
 */
export func removeForward(h as Host, vm as string, nic as int, name as string) {
    checkRange($nic, 1, 36, "the NIC");
    checkRuleName($name);
    natpf($h, $vm, $nic, ["delete", $name]);
}

/**
 * Change a NIC's port forwards on a live or a stopped machine.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param nic {int} the NIC
 * @param args {list of string} the rule, or `delete` and a name
 * @throws {VirtualboxError} kind "virtualbox" if VirtualBox refuses
 */
func natpf(h as Host, vm as string, nic as int, args as list of string) {
    def n as string init convert.toString($nic);
    def all as list of string init [];
    if (lists.contains(LIVE_STATES, state($h, $vm))) {
        $all = ["controlvm", $vm, "natpf" + $n];
    } else {
        $all = ["modifyvm", $vm, "--natpf" + $n];
    }
    for (def a in $args) {
        $all[] = $a;
    }
    call($h, $all, $all[0] + " " + $vm + " natpf" + $n);
}

/**
 * Refuse a rule VirtualBox could misread.
 *
 * @param rule {Forward} the rule
 * @throws {VirtualboxError} kind "virtualbox" if a field is unusable
 */
func checkForward(rule as Forward) {
    checkRange($rule.nic, 1, 36, "the NIC");
    checkRuleName($rule.name);
    checkChoice($rule.protocol, ["tcp", "udp"], "the protocol");
    checkRange($rule.hostPort, 1, 65535, "the host port");
    checkRange($rule.guestPort, 1, 65535, "the guest port");
    for (def ip in [$rule.hostIp, $rule.guestIp]) {
        if ($ip != "" and not regex.matches('^[0-9A-Fa-f.:]{2,45}$', $ip)) {
            fail("a forward's address must be an IPv4 or IPv6 address or empty, got " + shown($ip));
        }
    }
}

/**
 * Refuse a rule name: a name without commas, which separate the rule's
 * fields.
 *
 * @param name {string} the name
 * @throws {VirtualboxError} kind "virtualbox" if it is unusable
 */
func checkRuleName(name as string) {
    checkName($name, "the rule name");
    if (strings.contains($name, ",")) {
        fail("the rule name must not hold a comma, got " + shown($name));
    }
}
