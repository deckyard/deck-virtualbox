# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# virtualbox - white-box tests for the parse topic. Spliced into
# virtualbox_test.j via include.

func testPairsUndoTheEscapes() {
    def m as map of string to string init pairMap(pairs(fixture("showvminfo-web.out")));
    testing.assertEqual(
        $m["description"],
        "line one\nCurrentSnapshotName=\"evil\"\nline \"two\" \\ end \"\nlast line \\");
    testing.assertEqual($m["CurrentSnapshotName"], "patched");
    testing.assertEqual($m["SnapshotName-2"], "say \"hi\" \\o/");
    testing.assertEqual($m["SATA-0-0"], "/home/ada/VirtualBox VMs/web/web.vdi");
    testing.assertEqual($m["memory"], "2048");
    testing.assertEqual($m["GuestAdditionsFacility_VirtualBox Base Driver"], "50,1731484900000");
}

func testPairsKeepRepeatedKeysInOrder() {
    def keys as list of string init [];
    for (def p in pairs(fixture("showvminfo-web.out"))) {
        if (strings.startsWith($p.key, "Forwarding(")) {
            $keys[] = $p.key + "=" + $p.value;
        }
    }
    testing.assertEqual(
        strings.join($keys, ";"),
        "Forwarding(0)=ssh,tcp,,2222,,22;Forwarding(1)=http,tcp,127.0.0.1,8080,,80;" +
            "Forwarding(0)=dns,udp,,5353,10.0.2.15,53");
    testing.assertEqual(pairMap(pairs("mtu=1\nmtu=2\n"))["mtu"], "1");
}

func testPairsSkipWhatIsNoPair() {
    testing.assertEqual(
        len(pairs("Encryption:     disabled\n=value\n\"\"=value\n\n\"open=x\n")),
        0);
    testing.assertEqual(text(pairs("\"a=b\"=\"c\"")), "a=b|c");
    testing.assertEqual(text(pairs("\"a\\\"b=\"=1")), "a\"b=|1");
    testing.assertEqual(text(pairs("k=")), "k|");
    testing.assertEqual(text(pairs("k=\"\"")), "k|");
    testing.assertEqual(text(pairs("k=\"v\"\r\nn=2\r\n")), "k|v;n|2");
    testing.assertEqual(text(pairs("k=\"\nsecond\"")), "k|\nsecond");
    testing.assertEqual(text(pairs("k=\"open\nmore")), "k|open\nmore");
    testing.assertEqual(text(pairs("k=\"a\\\"\"\nn=1")), "k|a\";n|1");
}

/**
 * Pairs as `key|value` joined by `;`, for comparing.
 *
 * @param found {list of Pair} the pairs
 * @return {string} the text
 */
func text(found as list of Pair) {
    def out as list of string init [];
    for (def p in $found) {
        $out[] = $p.key + "|" + $p.value;
    }
    return strings.join($out, ";");
}

func testUnescapedUndoesOnlyVBoxManagesEscapes() {
    testing.assertEqual(unescaped("plain"), "plain");
    testing.assertEqual(unescaped("a\\\\b\\\"c\\n\\"), "a\\b\"c\\n\\");
    testing.assertEqual(unescaped("ü\\\"ö"), "ü\"ö");
}

func testParsingALongLineIsLinear() {
    def big as string init "description=\"" + strings.replicate("abc\\\"", 500000) +
        "\"\nVMState=\"poweroff\"\n";
    def started as time.Time init time.now();
    def m as map of string to string init pairMap(pairs($big));
    testing.assertEqual(len($m["description"]), 2000000);
    testing.assertEqual($m["VMState"], "poweroff");
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 20000);
}

func testBlocksSplitOnBlankLines() {
    def b as list of map of string to string init blocks(fixture("list-natnets.out"));
    testing.assertEqual(len($b), 3);
    testing.assertEqual($b[0]["NAT Networks"], "");
    testing.assertEqual($b[1]["Name"], "NatNetwork");
    testing.assertFalse(maps.has($b[1], "127.0.0.1=2"));
    testing.assertEqual($b[2]["IPv6 Prefix"], "fd17:625c:f037:9::/64");
    testing.assertFalse(maps.has($b[2], "2 networks found"));
    testing.assertEqual(len(blocks("\n\n")), 0);
}

func testFieldsNumbersAndFlags() {
    def m as map of string to string init {"New": "1", "Old": "2"};
    testing.assertEqual(field($m, "Gone"), "");
    testing.assertEqual(fieldOf($m, ["Gone", "Old", "New"]), "2");
    testing.assertEqual(fieldOf($m, ["Gone"]), "");
    testing.assertEqual(number("20480 MBytes"), 20480);
    testing.assertEqual(number(" -3"), -3);
    testing.assertEqual(number("n/a"), 0);
    testing.assertEqual(number("9999999999999999999999"), 0);
    for (def yes in ["on", "Yes", "TRUE", "enabled", "1"]) {
        testing.assertTrue(isYes($yes));
    }
    for (def no in ["off", "No", "", "disabled", "2"]) {
        testing.assertFalse(isYes($no));
    }
}
