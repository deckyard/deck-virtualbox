# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# virtualbox - parse: the two output forms VBoxManage has. `--machinereadable`
# prints `key="value"` lines; `list` prints blocks of `Key:   value` lines
# separated by blank lines. Spliced into virtualbox.j via include.

/**
 * One `key=value` line of `--machinereadable` output.
 *
 * @field key {string} the key
 * @field value {string} the value, its escapes undone
 */
def struct Pair {
    key as string,
    value as string
};

/**
 * Parse `--machinereadable` output into its `key=value` pairs, in order.
 *
 * VBoxManage escapes `"` and `\` in a quoted value as `\"` and `\\`, and
 * writes a newline as it is, so a value (a description) can run over several
 * lines; it ends at an unescaped `"` at the end of a line. A key that holds
 * `=` is quoted the same way. The snapshot keys (`SnapshotName...`,
 * `SnapshotDescription...`, `CurrentSnapshot...`) are printed unescaped, so
 * their values are taken as they are and end at any `"` at the end of a
 * line. A bare value runs to the end of its line; a line that is no pair
 * (`Encryption:     disabled`) is skipped. Keys repeat: each NIC numbers its
 * `Forwarding(N)` rules from 0.
 *
 * @param text {string} the output
 * @return {list of Pair} the pairs
 */
func pairs(text as string) {
    def out as list of Pair init [];
    def key as string init "";
    def raw as bool init false;
    def parts as list of string init [];
    def inValue as bool init false;
    for (def whole in strings.split($text, "\n")) {
        def line as string init $whole;
        if (strings.endsWith($line, "\r")) {
            $line = $line[..len($line) - 1];
        }
        if ($inValue) {
            if (closes($line, $raw)) {
                $parts[] = $line[..len($line) - 1];
                $out[] = Pair{key: $key, value: valueOf(strings.join($parts, "\n"), $raw)};
                $parts = [];
                $inValue = false;
            } else {
                $parts[] = $line;
            }
            continue;
        }
        def rest as string init "";
        if (strings.startsWith($line, "\"")) {
            def end as int init closingQuote($line, 1);
            if ($end < 0) {
                continue;
            }
            $key = unescaped($line[1..$end]);
            $rest = $line[$end + 1..];
            if (not strings.startsWith($rest, "=")) {
                continue;
            }
            $rest = $rest[1..];
        } else {
            def k as int init strings.indexOf($line, "=");
            if ($k <= 0) {
                continue;
            }
            $key = $line[..$k];
            $rest = $line[$k + 1..];
        }
        if ($key == "") {
            continue;
        }
        if (not strings.startsWith($rest, "\"")) {
            $out[] = Pair{key: $key, value: $rest};
            continue;
        }
        $raw = unescapedKey($key);
        def body as string init $rest[1..];
        if (closes($body, $raw)) {
            $out[] = Pair{key: $key, value: valueOf($body[..len($body) - 1], $raw)};
        } else {
            $parts = [$body];
            $inValue = true;
        }
    }
    if ($inValue) {
        $out[] = Pair{key: $key, value: valueOf(strings.join($parts, "\n"), $raw)};
    }
    return $out;
}

/**
 * Whether VBoxManage prints a key's value without escaping it.
 *
 * @param key {string} the key
 * @return {bool} whether it does: the snapshot keys
 */
func unescapedKey(key as string) {
    return strings.startsWith($key, "SnapshotName") or strings.startsWith($key, "SnapshotUUID") or
        strings.startsWith($key, "SnapshotDescription") or
        strings.startsWith($key, "CurrentSnapshot");
}

/**
 * Whether a line ends a quoted value: it ends in `"`, and for an escaped
 * value that `"` is not escaped (an even number of `\` before it).
 *
 * @param line {string} the line
 * @param raw {bool} whether the value is unescaped
 * @return {bool} whether it ends the value
 */
func closes(line as string, raw as bool) {
    if (not strings.endsWith($line, "\"")) {
        return false;
    }
    return $raw or backslashesBefore($line, len($line) - 1) % 2 == 0;
}

/**
 * The index of the first unescaped `"` from a position.
 *
 * @param line {string} the line
 * @param from {int} where to look from
 * @return {int} its index, -1 if there is none
 */
func closingQuote(line as string, from as int) {
    def at as int init strings.indexOf($line, "\"", $from);
    while ($at >= 0) {
        if (backslashesBefore($line, $at) % 2 == 0) {
            return $at;
        }
        $at = strings.indexOf($line, "\"", $at + 1);
    }
    return -1;
}

/**
 * How many `\` directly precede a position.
 *
 * @param s {string} the text
 * @param at {int} the position
 * @return {int} the count
 */
func backslashesBefore(s as string, at as int) {
    def n as int init 0;
    def i as int init $at - 1;
    while ($i >= 0 and $s[$i..$i + 1] == "\\") {
        $n = $n + 1;
        $i = $i - 1;
    }
    return $n;
}

/**
 * A quoted value's text: as it is for an unescaped key, else unescaped.
 *
 * @param text {string} the text between the quotes
 * @param raw {bool} whether the key is printed unescaped
 * @return {string} the value
 */
func valueOf(text as string, raw as bool) {
    if ($raw) {
        return $text;
    }
    return unescaped($text);
}

/**
 * Undo VBoxManage's escapes: `\\` to `\` and `\"` to `"`; any other `\`
 * stays.
 *
 * @param s {string} the escaped text
 * @return {string} the text
 */
func unescaped(s as string) {
    if (not strings.contains($s, "\\")) {
        return $s;
    }
    # NUL cannot occur in VBoxManage's output, so it stands in for `\\`
    # while `\"` is replaced
    def held as string init strings.replace($s, "\\\\", "\u0000");
    return strings.replace(strings.replace($held, "\\\"", "\""), "\u0000", "\\");
}

/**
 * `--machinereadable` output as a map; of a repeated key the first value
 * counts.
 *
 * @param lines {list of Pair} the lines, from `pairs`
 * @return {map of string to string} the keys and values
 */
func pairMap(lines as list of Pair) {
    def out as map of string to string init {};
    for (def p in $lines) {
        if (not maps.has($out, $p.key)) {
            $out[$p.key] = $p.value;
        }
    }
    return $out;
}

/**
 * Parse `list` output into blocks: each run of `Key: value` lines between
 * blank lines is one map. The key is the text before the first `:`, the
 * value the trimmed rest. Indented lines (sub-lists such as NAT loopback
 * mappings) and lines without a `:` are skipped.
 *
 * @param text {string} the output
 * @return {list of map of string to string} the blocks, in order
 */
func blocks(text as string) {
    def out as list of map of string to string init [];
    def current as map of string to string init {};
    for (def line in strings.split($text, "\n")) {
        def bare as string init strings.trimRight($line);
        if (strings.trim($bare) == "") {
            if (len($current) > 0) {
                $out[] = $current;
                $current = {};
            }
            continue;
        }
        if (strings.startsWith($bare, " ") or strings.startsWith($bare, "\t")) {
            continue;
        }
        def k as int init strings.indexOf($bare, ":");
        if ($k <= 0) {
            continue;
        }
        def key as string init strings.trim($bare[..$k]);
        if (not maps.has($current, $key)) {
            $current[$key] = strings.trim($bare[$k + 1..]);
        }
    }
    if (len($current) > 0) {
        $out[] = $current;
    }
    return $out;
}

/**
 * A value from a parsed map.
 *
 * @param m {map of string to string} the map
 * @param key {string} the key
 * @return {string} its value, `""` when it is missing
 */
func field(m as map of string to string, key as string) {
    if (maps.has($m, $key)) {
        return $m[$key];
    }
    return "";
}

/**
 * The first of several keys a map has, for a field VBoxManage names in more
 * than one way.
 *
 * @param m {map of string to string} the map
 * @param keys {list of string} the keys, newest name first
 * @return {string} the value of the first one present, `""` when none is
 */
func fieldOf(m as map of string to string, keys as list of string) {
    for (def k in $keys) {
        if (maps.has($m, $k)) {
            return $m[$k];
        }
    }
    return "";
}

/**
 * A whole number from VirtualBox's output.
 *
 * @param s {string} the text, such as `2048` or `20480 MBytes`
 * @return {int} the leading number, 0 when there is none
 */
func number(s as string) {
    def m as regex.Match init regex.find('^-?[0-9]+', strings.trim($s));
    if ($m.start < 0 or len($m.text) > 18) {
        return 0;
    }
    return convert.toInt($m.text);
}

/**
 * A yes / no value from VirtualBox's output: `on`, `yes`, `true`, `enabled`
 * and `1` are true, whatever the case.
 *
 * @param s {string} the text
 * @return {bool} whether it says yes
 */
func isYes(s as string) {
    return lists.contains(["on", "yes", "true", "enabled", "1"], strings.lower(strings.trim($s)));
}
