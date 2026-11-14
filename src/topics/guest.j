# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualbox - guest: guest properties and the guest's IP, commands and file
# copies in the guest, and shared folders. Spliced into virtualbox.j via
# include.

# how often waitForIp asks, in milliseconds
def const IP_POLL_MS as int init 1000;

/**
 * A guest account, for the commands and copies in the guest.
 *
 * @field username {string} the guest user
 * @field password {string} the user's password; it reaches `VBoxManage` through a named pipe, never the disk or its command line
 */
export def struct Credentials {
    username as string,
    password as string
};

/**
 * What a command in the guest did, from `guestRun`.
 *
 * @field status {string} `exited` (it ended by itself), `killed` (a signal ended it) or `abnormal` (the guest reports it ended abnormally)
 * @field exitCode {int} its exit code when `status` is `exited`: 0 to 93 as the program returned it, -1 for 94 or more (VBoxManage cannot pass those on); -1 for the other statuses
 * @field stdout {string} its standard output
 * @field stderr {string} its error output
 */
export def struct GuestResult {
    status as string,
    exitCode as int,
    stdout as string,
    stderr as string
};

/**
 * A guest property, which the Guest Additions and the host set: the guest's
 * addresses under `/VirtualBox/GuestInfo/Net/`, its OS under
 * `/VirtualBox/GuestInfo/OS/`, and any key of your own.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param key {string} the property, such as `/VirtualBox/GuestInfo/OS/Product`
 * @return {string} its value, `""` when it is not set
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func guestProperty(h as Host, vm as string, key as string) {
    checkVm($vm);
    checkPath($key, "the property");
    def out as string init call($h, ["guestproperty", "get", $vm, $key], "guestproperty get");
    for (def line in strings.split($out, "\n")) {
        if (strings.startsWith($line, "Value: ")) {
            return strings.trimRight(strings.substring($line, 7));
        }
    }
    return "";
}

/**
 * Set a guest property.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param key {string} the property
 * @param value {string} its value; use `unsetGuestProperty` to remove it
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func setGuestProperty(h as Host, vm as string, key as string, value as string) {
    checkVm($vm);
    checkPath($key, "the property");
    checkText($value, "the property value");
    call($h, ["guestproperty", "set", $vm, $key, $value], "guestproperty set");
}

/**
 * Remove a guest property.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param key {string} the property
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func unsetGuestProperty(h as Host, vm as string, key as string) {
    checkVm($vm);
    checkPath($key, "the property");
    call($h, ["guestproperty", "unset", $vm, $key], "guestproperty unset");
}

/**
 * The IPv4 address the Guest Additions report for a NIC.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param nic {int} the guest's network interface, from 0 (not the NIC slot, which counts from 1)
 * @return {string} the address, `""` before the guest reports one
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func guestIp(h as Host, vm as string, nic as int) {
    checkRange($nic, 0, 35, "the guest interface");
    return guestProperty($h, $vm, "/VirtualBox/GuestInfo/Net/" + convert.toString($nic) + "/V4/IP");
}

/**
 * Wait until the guest reports an IPv4 address for a NIC: a started machine
 * has one once its Guest Additions run. Each `VBoxManage` call gets at most
 * the time left. The property can survive a hard power-off, so a machine
 * started after one may report its old address at first: unset
 * `/VirtualBox/GuestInfo/Net/<nic>/V4/IP` with `unsetGuestProperty` before
 * `start` when that matters.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param nic {int} the guest's network interface, from 0
 * @param timeoutMs {int} how long to wait, 1 to 86400000
 * @return {string} the address
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable, VirtualBox refuses, or no address comes in time
 * @example
 *   virtualbox.start($vb, "web");
 *   def ip as string init virtualbox.waitForIp($vb, "web", 0, 120000);
 */
export func waitForIp(h as Host, vm as string, nic as int, timeoutMs as int) {
    checkRange($timeoutMs, 1, 86400000, "the timeout");
    def started as time.Time init time.now();
    def polling as Host init $h;
    while (true) {
        def left as int init $timeoutMs - time.milliseconds(time.sub(time.now(), $started));
        if ($left <= 0) {
            fail($vm + " reported no IP address for interface " + convert.toString($nic) +
                " within " +
                convert.toString($timeoutMs) + " ms (are the Guest Additions running?)");
        }
        $polling.config.timeoutMs = $h.config.timeoutMs;
        if ($left < $polling.config.timeoutMs) {
            $polling.config.timeoutMs = $left;
        }
        def ip as string init "";
        try {
            $ip = guestIp($polling, $vm, $nic);
        } catch (e) {
            # a poll cut short by the end of the wait ends it the same way
            if ($e.kind != "virtualbox" or $e.reason != "timeout" or
                $polling.config.timeoutMs == $h.config.timeoutMs) {
                throw $e;
            }
            fail($vm + " reported no IP address for interface " + convert.toString($nic) +
                " within " +
                convert.toString($timeoutMs) + " ms (the last poll did not answer)");
        }
        if ($ip != "") {
            return $ip;
        }
        $left = $timeoutMs - time.milliseconds(time.sub(time.now(), $started));
        if ($left > 0) {
            def pause as int init IP_POLL_MS;
            if ($left < $pause) {
                $pause = $left;
            }
            time.sleep(time.fromMilliseconds($pause));
        }
    }
    return "";
}

# --- commands and files in the guest ---------------------------------------

/**
 * A guest account for `guestRun`, `copyTo` and `copyFrom`.
 *
 * @param username {string} the guest user
 * @param password {string} the password
 * @return {Credentials} the account
 * @throws {VirtualboxError} kind "virtualbox" if the user is empty or starts with `-`, or either holds a control character
 */
export func credentials(username as string, password as string) {
    checkName($username, "the guest user");
    if (regex.matches(CONTROL, $password)) {
        fail("the guest password holds a control character");
    }
    return Credentials{username: $username, password: $password};
}

/**
 * Run a program in the guest and wait for it, within the ordinary deadline
 * (`withTimeout` for longer commands). Needs the Guest Additions. Refused
 * for a remote host: the password would have to reach it.
 *
 * VBoxManage folds the program's exit code into its own (0 stays 0, 1 to 93
 * become 33 to 125, anything higher 126; 18 and 19 for a signal or an
 * abnormal end); `GuestResult` gives the program's code back. Any other exit
 * code is a failure of VBoxManage itself and throws, whatever the guest
 * printed.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param account {Credentials} the guest account, from `credentials`
 * @param argv {list of string} the program, by its absolute path in the guest, and its arguments
 * @return {GuestResult} how it ended and its output
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable, the host is remote, or `VBoxManage` cannot run the program (no Guest Additions, a wrong password, no such program)
 * @example
 *   def r as virtualbox.GuestResult init virtualbox.guestRun($vb, "web",
 *       virtualbox.credentials("ada", $password), ["/usr/bin/uptime"]);
 */
export func guestRun(h as Host, vm as string, account as Credentials, argv as list of string) {
    checkVm($vm);
    requireLocal($h, "guestRun");
    if (len($argv) == 0) {
        fail("guestRun needs a program");
    }
    checkPath($argv[0], "the guest program");
    for (def a in $argv) {
        checkText($a, "a guest argument");
    }
    def dir as string init passwordDir();
    def pipe as string init $dir + "/password";
    def secret as string init $account.password;
    def feeder as task of bool init spawn {
        return feedPassword($pipe, $secret);
    };
    defer closePassword($feeder, $dir);
    # Without --exe, the first argument after `--` is both the program and
    # its argv[0]; with --exe, VBoxManage 7.1 would pass it twice.
    def args as list of string init guestArgs($vm, "run", $account, $pipe);
    for (def a in ["--wait-stdout", "--wait-stderr", "--"]) {
        $args[] = $a;
    }
    for (def a in $argv) {
        $args[] = $a;
    }
    def what as string init "guestcontrol " + $vm + " run";
    return guestOutcome(execute($h.config, $args, $h.config.timeoutMs, $what), $what);
}

/**
 * The guest program's outcome from VBoxManage's exit code.
 *
 * @param r {os.Result} VBoxManage's result
 * @param what {string} the operation, for the message
 * @return {GuestResult} the outcome
 * @throws {VirtualboxError} kind "virtualbox" if the exit code is VBoxManage's own failure
 */
func guestOutcome(r as os.Result, what as string) {
    def out as GuestResult init GuestResult{
        status: "exited",
        exitCode: -1,
        stdout: $r.stdout,
        stderr: $r.stderr
    };
    def code as int init $r.exitCode;
    if ($code == 0) {
        $out.exitCode = 0;
    } elseif ($code >= 33 and $code <= 125) {
        $out.exitCode = $code - 32;
    } elseif ($code == 126) {
        $out.exitCode = -1;
    } elseif ($code == 18) {
        $out.status = "killed";
    } elseif ($code == 19) {
        $out.status = "abnormal";
    } else {
        failed($what, $r);
    }
    return $out;
}

/**
 * Copy a file from the host into the guest. Needs the Guest Additions;
 * refused for a remote host.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param account {Credentials} the guest account
 * @param hostPath {string} the file on the host
 * @param guestPath {string} where it goes in the guest
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable, the host is remote or the copy fails
 */
export func copyTo(
    h as Host,
    vm as string,
    account as Credentials,
    hostPath as string,
    guestPath as string) {
    guestCopy($h, $vm, $account, "copyto", $hostPath, $guestPath);
}

/**
 * Copy a file from the guest to the host. Needs the Guest Additions;
 * refused for a remote host.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param account {Credentials} the guest account
 * @param guestPath {string} the file in the guest
 * @param hostPath {string} where it goes on the host
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable, the host is remote or the copy fails
 */
export func copyFrom(
    h as Host,
    vm as string,
    account as Credentials,
    guestPath as string,
    hostPath as string) {
    guestCopy($h, $vm, $account, "copyfrom", $guestPath, $hostPath);
}

/**
 * `guestcontrol copyto` or `copyfrom`.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param account {Credentials} the guest account
 * @param verb {string} `copyto` or `copyfrom`
 * @param source {string} the file to copy
 * @param target {string} where it goes
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable, the host is remote or the copy fails
 */
func guestCopy(
    h as Host,
    vm as string,
    account as Credentials,
    verb as string,
    source as string,
    target as string) {
    checkVm($vm);
    requireLocal($h, $verb);
    checkPath($source, "the source");
    checkPath($target, "the target");
    def dir as string init passwordDir();
    def pipe as string init $dir + "/password";
    def secret as string init $account.password;
    def feeder as task of bool init spawn {
        return feedPassword($pipe, $secret);
    };
    defer closePassword($feeder, $dir);
    def args as list of string init guestArgs($vm, $verb, $account, $pipe);
    $args[] = $source;
    $args[] = $target;
    callLong($h, $args, "guestcontrol " + $vm + " " + $verb);
}

/**
 * The start of a `guestcontrol` command line.
 *
 * @param vm {string} the machine
 * @param verb {string} the subcommand
 * @param account {Credentials} the guest account
 * @param file {string} the password pipe
 * @return {list of string} the arguments
 */
func guestArgs(vm as string, verb as string, account as Credentials, file as string) {
    return ["guestcontrol", $vm, $verb, "--username", $account.username, "--passwordfile", $file];
}

/**
 * A private directory (mode 0700) holding a named pipe `password` (mode
 * 0600) for `--passwordfile`: the password goes through the pipe and never
 * touches the disk.
 *
 * @return {string} the directory
 * @throws {VirtualboxError} kind "virtualbox" if it cannot be made (named pipes need Linux, macOS or another Unix)
 */
func passwordDir() {
    def dir as string init "";
    try {
        $dir = fs.makeTempDir("", "jennifer-vbox-");
        fs.mkfifo($dir + "/password", 384);
    } catch (e) {
        if ($dir != "") {
            fs.removeAll($dir);
        }
        fail("cannot make the password pipe: " + cleaned($e.message, 200));
    }
    return $dir;
}

/**
 * Write the password into the pipe; runs as a task, blocked until
 * `VBoxManage` opens the pipe.
 *
 * @param pipe {string} the pipe
 * @param secret {string} the password
 * @return {bool} true once it is written
 */
func feedPassword(pipe as string, secret as string) {
    def f as fs.File init fs.open($pipe, "write");
    defer fs.close($f);
    fs.writeString($f, $secret);
    return true;
}

/**
 * Finish the password pipe after `VBoxManage` ended: if it never opened the
 * pipe, open the read end to release the waiting writer; then remove the
 * directory.
 *
 * @param feeder {task of bool} the writer
 * @param dir {string} the directory from `passwordDir`
 */
func closePassword(feeder as task of bool, dir as string) {
    if (not task.poll($feeder)) {
        def drain as task of bool init spawn {
            return drainPipe($dir + "/password");
        };
        try {
            task.waitTimeout($drain, 2000);
        } catch (e) {
            task.discard($drain);
        }
    }
    try {
        task.waitTimeout($feeder, 2000);
    } catch (e) {
        task.discard($feeder);
    }
    try {
        fs.removeAll($dir);
    } catch (e) {
        $dir = "";
    }
}

/**
 * Open and close a pipe's read end, which lets a writer blocked on opening
 * it go on.
 *
 * @param pipe {string} the pipe
 * @return {bool} true
 */
func drainPipe(pipe as string) {
    def f as fs.File init fs.open($pipe, "read");
    fs.close($f);
    return true;
}

/**
 * Refuse a guest-account call over a command prefix.
 *
 * @param h {Host} the host
 * @param what {string} the call
 * @throws {VirtualboxError} kind "virtualbox" if the host is reached through a prefix
 */
func requireLocal(h as Host, what as string) {
    if (len($h.config.prefix) > 0) {
        fail($what +
            " needs a local VBoxManage: over a command prefix the password would have to reach the remote host");
    }
}

# --- shared folders --------------------------------------------------------

/**
 * A machine's shared folders.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @return {list of SharedFolder} the folders
 * @throws {VirtualboxError} kind "virtualbox" as `info`
 */
export func sharedFolders(h as Host, vm as string) {
    return info($h, $vm).sharedFolders;
}

/**
 * Share a host directory with a machine, in its settings.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param name {string} the folder's name in the guest
 * @param hostPath {string} the host directory, an absolute path
 * @param readOnly {bool} whether the guest may only read it
 * @param autoMount {bool} whether the Guest Additions mount it at boot
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 * @example
 *   virtualbox.addSharedFolder($vb, "web", "site", "/srv/site", true, true);
 */
export func addSharedFolder(
    h as Host,
    vm as string,
    name as string,
    hostPath as string,
    readOnly as bool,
    autoMount as bool) {
    checkVm($vm);
    checkName($name, "the folder name");
    checkPath($hostPath, "the host directory");
    def args as list of string init [
        "sharedfolder",
        "add",
        $vm,
        "--name",
        $name,
        "--hostpath",
        $hostPath
    ];
    if ($readOnly) {
        $args[] = "--readonly";
    }
    if ($autoMount) {
        $args[] = "--automount";
    }
    call($h, $args, "sharedfolder add " + $vm);
}

/**
 * Stop sharing a folder with a machine.
 *
 * @param h {Host} the host
 * @param vm {string} the machine's name or UUID
 * @param name {string} the folder's name
 * @throws {VirtualboxError} kind "virtualbox" if an argument is unusable or VirtualBox refuses
 */
export func removeSharedFolder(h as Host, vm as string, name as string) {
    checkVm($vm);
    checkName($name, "the folder name");
    call($h, ["sharedfolder", "remove", $vm, "--name", $name], "sharedfolder remove " + $vm);
}
