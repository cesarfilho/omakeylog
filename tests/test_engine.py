"""Unit tests for engine/omakeylog. They exercise the counting, the analysis
and the layout import without a keyboard or python-evdev:

    python3 -m unittest discover -s tests
"""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE = os.path.join(ROOT, "engine", "omakeylog")


def load_engine():
    loader = importlib.machinery.SourceFileLoader("omakeylog_engine", ENGINE)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    loader.exec_module(mod)
    return mod


E = load_engine()


def typed(tally, text, start=0.0, step=0.1, hold=0.08):
    """Type text one key at a time, each released before the next."""
    t = start
    for ch in text:
        label = "SPACE" if ch == " " else ch.upper()
        tally.press(label, t)
        tally.release(label, t + hold)
        t += step
    return t


class TallyTest(unittest.TestCase):
    def test_counts_keys_and_sequences(self):
        t = E.Tally()
        typed(t, "the")
        self.assertEqual(t.keys, {"T": 1, "H": 1, "E": 1})
        self.assertEqual(t.bigrams, {"T>H": 1, "H>E": 1})
        self.assertEqual(t.skipgrams, {"T>E": 1})
        self.assertEqual(t.trigrams, {"T>H>E": 1})

    def test_pause_breaks_the_sequence(self):
        t = E.Tally()
        end = typed(t, "ab")
        typed(t, "c", start=end + E.SEQUENCE_GAP + 1)
        self.assertEqual(t.bigrams, {"A>B": 1})
        self.assertEqual(t.trigrams, {})

    def test_shortcut_is_a_chord_not_a_pair(self):
        t = E.Tally()
        typed(t, "a")
        t.press("LEFTCTRL", 0.2)
        t.press("C", 0.25)
        t.release("C", 0.3)
        t.release("LEFTCTRL", 0.35)
        self.assertEqual(t.chords, {"LEFTCTRL+C": 1})
        self.assertNotIn("A>C", t.bigrams)
        self.assertNotIn("LEFTCTRL>C", t.bigrams)
        self.assertEqual(t.keys["LEFTCTRL"], 1)

    def test_shift_stays_in_the_sequence(self):
        t = E.Tally()
        t.press("LEFTSHIFT", 0.0)
        t.press("T", 0.05)
        t.release("T", 0.1)
        t.release("LEFTSHIFT", 0.12)
        typed(t, "he", start=0.2)
        self.assertEqual(t.bigrams, {"T>H": 1, "H>E": 1})
        self.assertEqual(t.chords, {})
        self.assertEqual(t.shifted, 1)

    def test_hold_histogram_and_rolls(self):
        t = E.Tally()
        t.press("A", 0.0)
        t.press("S", 0.05)    # S goes down while A is still held: a roll
        t.release("A", 0.09)  # overlap 40 ms
        t.release("S", 0.15)
        self.assertEqual(t.rolls, 1)
        self.assertEqual(t.overlaps, {"40": 1})
        self.assertEqual(sum(t.holds.values()), 2)
        self.assertEqual(t.key_holds["A"], [90, 1])

    def test_repeat_presses_and_unknown_release(self):
        t = E.Tally()
        t.release("A", 1.0)  # released without a press: ignored
        self.assertEqual(t.holds, {})

    def test_round_trip(self):
        t = E.Tally()
        typed(t, "hello world")
        again = E.Tally(json.loads(json.dumps(t.to_dict())))
        self.assertEqual(again.keys, t.keys)
        self.assertEqual(again.trigrams, t.trigrams)
        self.assertEqual(again.key_holds, t.key_holds)

    def test_old_stats_load(self):
        t = E.Tally({"version": 1, "keys": {"A": 3}, "bigrams": {"A>A": 2}})
        self.assertEqual(t.keys, {"A": 3})
        self.assertEqual(t.chords, {})


class ReportTest(unittest.TestCase):
    def stats(self, text="the quick brown fox jumps over the lazy dog " * 20):
        t = E.Tally()
        typed(t, text)
        return t.to_dict()

    def test_empty(self):
        rep = E.build_report(stats={}, layout=E.default_layout())
        self.assertEqual(rep["total"], 0)
        self.assertEqual(rep["suggestions"][0][:10], "No data ye")

    def test_shape(self):
        rep = E.build_report(stats=self.stats(), layout=E.default_layout())
        self.assertGreater(rep["total"], 0)
        self.assertAlmostEqual(sum(f["pct"] for f in rep["fingers"]),
                               100 - rep["hands"]["other"], delta=0.5)
        self.assertEqual(rep["top_keys"][0]["label"], "SPACE")
        kinds = rep["trigrams"]["kinds"]
        self.assertAlmostEqual(sum(kinds.values()), 100, delta=0.5)
        self.assertEqual(len(rep["heatmap"]), 5)
        self.assertIsNone(rep["compare"])
        json.dumps(rep)  # serializable

    def test_sfb_detected(self):
        # E then D: both left middle on QWERTY
        rep = E.build_report(stats=self.stats("ed ed ed "), layout=E.default_layout())
        pairs = [r["pair"] for r in rep["sfb"]["top"]]
        self.assertIn("E D", pairs)

    def test_compare(self):
        before = self.stats("ed ed ed ed ")
        after = self.stats("the cat sat ")
        rep = E.build_report(stats=after, layout=E.default_layout(),
                             baseline=before, baseline_name="old")
        self.assertEqual(rep["compare"]["against"], "old")
        self.assertLess(rep["compare"]["sfb_delta"], 0)
        self.assertIsNotNone(rep["fingers"][0]["delta"])

    def test_tapping_term(self):
        t = E.Tally()
        typed(t, "asdf jkl; " * 40, hold=0.12)
        rep = E.build_report(stats=t.to_dict(), layout=E.default_layout())
        tt = rep["timing"]["tapping_term"]
        self.assertIsNotNone(tt)
        self.assertTrue(150 <= tt <= 300)
        self.assertGreater(tt, rep["timing"]["hold_p95"])

    def test_trigram_kinds(self):
        L = E.default_layout()
        f = lambda keys: E._trigram_kind([L.finger(k)[:2] for k in keys])
        self.assertEqual(f(["A", "J", "S"]), "alternate")
        self.assertEqual(f(["A", "S", "J"]), "roll")
        self.assertEqual(f(["A", "S", "D"]), "onehand")
        self.assertEqual(f(["A", "D", "S"]), "redirect")
        self.assertEqual(f(["E", "D", "J"]), "sfb")


class LayoutTest(unittest.TestCase):
    def test_qmk_labels(self):
        self.assertEqual(E.qmk_label("KC_A"), ("A", None))
        self.assertEqual(E.qmk_label("LSFT_T(KC_A)"), ("A", "LEFTSHIFT"))
        self.assertEqual(E.qmk_label("MT(MOD_RCTL, KC_SCLN)"), ("SEMICOLON", "RIGHTCTRL"))
        self.assertEqual(E.qmk_label("LT(1, KC_SPC)"), ("SPACE", None))
        self.assertEqual(E.qmk_label("MO(1)"), (None, None))
        self.assertEqual(E.qmk_label(-1), (None, None))
        self.assertEqual(E.qmk_label("KC_F12"), ("F12", None))

    def corne(self):
        left = [
            ["KC_TAB", "KC_Q", "KC_W", "KC_E", "KC_R", "KC_T"],
            ["KC_LCTL", "LGUI_T(KC_A)", "KC_S", "KC_D", "KC_F", "KC_G"],
            ["KC_LSFT", "KC_Z", "KC_X", "KC_C", "KC_V", "KC_B"],
            [-1, -1, -1, "KC_LGUI", "MO(1)", "KC_SPC"],
        ]
        right = [
            ["KC_BSPC", "KC_P", "KC_O", "KC_I", "KC_U", "KC_Y"],
            ["KC_QUOT", "KC_SCLN", "KC_L", "KC_K", "KC_J", "KC_H"],
            ["KC_ESC", "KC_SLSH", "KC_DOT", "KC_COMM", "KC_M", "KC_N"],
            [-1, -1, -1, "KC_RALT", "MO(2)", "KC_ENT"],
        ]
        return {"layout": [left + right]}

    def test_vil_import(self):
        data = E.layout_from_vil(self.corne())
        keys = data["keys"]
        self.assertEqual(keys["A"], ["L", "pinky", 1])
        self.assertEqual(keys["F"], ["L", "index", 1])
        self.assertEqual(keys["G"], ["L", "index", 1])
        self.assertEqual(keys["D"], ["L", "middle", 1])
        self.assertEqual(keys["J"], ["R", "index", 1])
        self.assertEqual(keys["SEMICOLON"], ["R", "pinky", 1])
        self.assertEqual(keys["Q"], ["L", "pinky", 2])
        self.assertEqual(keys["Z"], ["L", "pinky", 0])
        self.assertEqual(keys["SPACE"], ["L", "thumb", -1])
        self.assertEqual(keys["ENTER"], ["R", "thumb", -1])
        self.assertEqual(keys["LEFTMETA"][1], "thumb")  # the plain key wins over the mod-tap
        self.assertEqual(len(data["grid"]), 4)
        # the grid reads left to right: right half's outer column comes last
        self.assertEqual(data["grid"][1][-1][0], "APOSTROPHE")

    def test_vil_right_inner_first(self):
        vil = self.corne()
        right = vil["layout"][0][4:]
        vil["layout"][0][4:] = [list(reversed(r)) for r in right]
        data = E.layout_from_vil(vil, right_inner_first=True)
        self.assertEqual(data["keys"]["J"], ["R", "index", 1])
        self.assertEqual(data["keys"]["SEMICOLON"], ["R", "pinky", 1])

    def test_load_layout_file(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "layout.json")
            with open(path, "w") as fh:
                json.dump(E.layout_from_vil(self.corne()), fh)
            layout = E.load_layout(path)
            self.assertEqual(layout.source, path)
            self.assertEqual(layout.finger("SPACE"), ("L", "thumb", -1))
            self.assertIn("A", layout.home())
            rep = E.build_report(stats={"keys": {"SPACE": 5, "A": 3}}, layout=layout)
            self.assertEqual(rep["hands"]["thumb"], 62.5)
            names = [f["finger"] for f in rep["fingers"]]
            self.assertIn("L-thumb", names)
            self.assertNotIn("T-thumb", names)

    def test_bad_layout_falls_back(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "layout.json")
            with open(path, "w") as fh:
                fh.write("{not json")
            self.assertEqual(E.load_layout(path).source, "default")

    def test_vil_rejects_garbage(self):
        with self.assertRaises(ValueError):
            E.layout_from_vil({"nope": 1})


class SessionTest(unittest.TestCase):
    def test_session_active_parsing(self):
        real, real_lock = E._loginctl, E.screen_locked
        E.screen_locked = lambda: False
        try:
            E._loginctl = lambda *a: "Active=yes\nLockedHint=no"
            self.assertTrue(E.session_active("2"))
            E._loginctl = lambda *a: "Active=no\nLockedHint=no"
            self.assertFalse(E.session_active("2"))
            E._loginctl = lambda *a: "Active=yes\nLockedHint=yes"
            self.assertFalse(E.session_active("2"))
            E._loginctl = lambda *a: None  # logind unreachable: fail closed
            self.assertFalse(E.session_active("2"))
            self.assertFalse(E.session_active(None))
            # Omarchy's lock screen does not set LockedHint: asked directly
            E._loginctl = lambda *a: "Active=yes\nLockedHint=no"
            E.screen_locked = lambda: True
            self.assertFalse(E.session_active("2"))
        finally:
            E._loginctl, E.screen_locked = real, real_lock

    def test_screen_locked_asks_the_lockers(self):
        real = E._run_quiet
        try:
            E._run_quiet = lambda cmd: "true" if cmd[0] == "omarchy-shell" else None
            self.assertTrue(E.screen_locked())
            E._run_quiet = lambda cmd: "4242" if cmd[0] == "pgrep" else "false"
            self.assertTrue(E.screen_locked())
            E._run_quiet = lambda cmd: "false" if cmd[0] == "omarchy-shell" else None
            self.assertFalse(E.screen_locked())
            # Omarchy's lock does not set LockedHint, so a lock status that
            # cannot be read must count as locked, not unlocked.
            E._run_quiet = lambda cmd: None  # failed or timed out
            self.assertTrue(E.screen_locked())
            E._run_quiet = lambda cmd: "" if cmd[0] == "omarchy-shell" else None
            self.assertTrue(E.screen_locked())
        finally:
            E._run_quiet = real


class PendingKeysTest(unittest.TestCase):
    """Keys wait for the next session check before they are counted."""

    def type(self, pending, text, t=0.0):
        for ch in text:
            pending.add(ch.upper(), True, t)
            pending.add(ch.upper(), False, t + 0.05)
            t += 0.1

    def test_counted_when_still_active(self):
        tally = E.Tally()
        pending = E.PendingKeys(tally)
        self.type(pending, "ab")
        self.assertEqual(sum(tally.keys.values()), 0)  # nothing before the check
        self.assertTrue(pending.settle(True, True))
        self.assertEqual(tally.keys, {"A": 1, "B": 1})

    def test_discarded_after_switch_or_lock(self):
        tally = E.Tally()
        pending = E.PendingKeys(tally)
        self.type(pending, "secret")  # typed after the lock, before the check
        pending.settle(True, False)
        self.assertEqual(sum(tally.keys.values()), 0)
        self.type(pending, "secret", t=5.0)  # inactive at both checks
        self.assertFalse(pending.settle(False, False))
        self.type(pending, "pw", t=9.0)  # read while the unlock was unseen
        pending.settle(False, True)
        self.assertEqual(sum(tally.keys.values()), 0)

    def test_unplugged_keyboard_drops_held_keys(self):
        tally = E.Tally()
        pending = E.PendingKeys(tally)
        pending.add("A", True, 0.0)
        pending.device_gone()
        pending.add("B", True, 0.5)
        pending.add("B", False, 0.6)
        pending.settle(True, True)
        self.assertEqual(tally.keys, {"A": 1, "B": 1})
        self.assertNotIn("A", tally.down)

    def test_full(self):
        pending = E.PendingKeys(E.Tally())
        for i in range(E.PENDING_MAX):
            self.assertFalse(pending.full())
            pending.add("A", i % 2 == 0, i * 0.1)
        self.assertTrue(pending.full())


class TimelineTest(unittest.TestCase):
    """Keys, characters and active time per hour, for the history and WPM."""

    def setUp(self):
        # a fixed local hour, so bucket keys do not depend on when tests run
        self.t0 = time.mktime((2026, 10, 9, 10, 0, 0, 0, 0, -1))

    def test_typing_speed(self):
        tl = E.Timeline()
        tally = E.Tally(timeline=tl)
        # 60 characters, one every 0.2 s: 12 s of typing, 60 chars = 12 words
        typed(tally, "the quick brown fox jumps over the lazy dog and keeps going on", start=self.t0, step=0.2)
        b = tl.hours["2026-10-09T10"]
        self.assertEqual(b[0], b[1])  # every key typed a character
        self.assertAlmostEqual(b[2], (b[0] - 1) * 200, delta=5)
        self.assertIsNone(E.wpm(b[1], b[2]))  # under 20 s of typing: no speed yet
        self.assertEqual(E.wpm(100, 60000), 20.0)

    def test_idle_and_shortcuts_do_not_count(self):
        tl = E.Timeline()
        tally = E.Tally(timeline=tl)
        tally.press("A", self.t0)
        tally.press("B", self.t0 + 10)  # a long pause is not typing time
        tally.press("LEFTCTRL", self.t0 + 10.1)
        tally.press("C", self.t0 + 10.2)  # Ctrl+C: a key, not a character
        tally.press("BACKSPACE", self.t0 + 10.3)
        self.assertEqual(tl.hours["2026-10-09T10"], [5, 2, 300])

    def test_reset_keeps_the_timeline(self):
        tl = E.Timeline()
        tally = E.Tally({"keys": {"A": 3}}, tl)
        tally.press("A", self.t0)
        tally.clear()
        self.assertEqual(tally.keys, {})
        self.assertIs(tally.timeline, tl)
        self.assertEqual(tl.hours["2026-10-09T10"][0], 1)

    def test_history_rollups(self):
        tl = E.Timeline({"hours": {
            "2026-10-09T10": [600, 500, 300000],   # 500 chars in 5 min: 20 wpm
            "2026-10-08T22": [100, 100, 60000],
            "2025-03-01T09": [50, 40, 10000],
        }})
        now = self.t0 + 1800
        h = E.build_history(tl, now=now, since=self.t0 + 60)
        self.assertEqual(len(h["hours"]), 24)
        self.assertEqual(h["hours"][-1]["keys"], 600)
        self.assertEqual(h["hours"][-1]["wpm"], 20.0)
        self.assertEqual(len(h["days"]), 30)
        self.assertEqual([d["keys"] for d in h["days"][-2:]], [100, 600])
        self.assertEqual(len(h["months"]), 12)
        self.assertEqual(h["months"][-1]["keys"], 700)
        self.assertEqual([y["label"] for y in h["years"]], ["2025", "2026"])
        self.assertEqual([y["keys"] for y in h["years"]], [50, 700])
        self.assertEqual(len(h["session"]), 1)
        self.assertEqual(h["today"], {"keys": 600, "wpm": 20.0})
        self.assertEqual(h["summary"]["days"]["keys"], 700)
        self.assertEqual(h["summary"]["days"]["peak_wpm"], 20.0)
        self.assertEqual(E.build_history(E.Timeline(), now=now)["session"], [])


class SeatTest(unittest.TestCase):
    """Multiseat: only keyboards on the recorder's own seat are read."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.saved = E.UDEV_DATA
        E.UDEV_DATA = self.dir.name
        rdev = os.stat("/dev/null").st_rdev  # any character device will do
        self.data = os.path.join(self.dir.name, "c%d:%d" % (os.major(rdev), os.minor(rdev)))

    def tearDown(self):
        E.UDEV_DATA = self.saved
        self.dir.cleanup()

    def tag(self, *lines):
        with open(self.data, "w") as fh:
            fh.write("\n".join(("I:1", "E:ID_INPUT=1") + lines) + "\n")

    def test_untagged_device_is_seat0(self):
        self.tag()
        self.assertEqual(E.device_seat("/dev/null"), "seat0")

    def test_tagged_device(self):
        self.tag("E:ID_SEAT=seat1")
        self.assertEqual(E.device_seat("/dev/null"), "seat1")

    def test_missing_device(self):
        self.assertIsNone(E.device_seat("/dev/input/does-not-exist"))

    @unittest.skipUnless(importlib.util.find_spec("evdev"), "python-evdev not installed")
    def test_other_seat_is_rejected_unopened(self):
        self.tag("E:ID_SEAT=seat1")
        devices, denied, rejected = E.open_keyboards(["/dev/null"], True, seat="seat0")
        self.assertEqual((devices, denied, rejected), ([], False, ["/dev/null"]))


class ProcessTest(unittest.TestCase):
    def test_pid_alive_rejects_other_processes(self):
        self.assertFalse(E.pid_alive(0))
        self.assertFalse(E.pid_alive(os.getpid()))  # alive, but not omakeylog
        self.assertFalse(E.pid_alive(2 ** 22 + 1))

    def test_cli_in_a_scratch_home(self):
        with tempfile.TemporaryDirectory() as d:
            env = dict(os.environ, XDG_DATA_HOME=d, XDG_CONFIG_HOME=d)

            def run(*args):
                return subprocess.run([sys.executable, ENGINE] + list(args), env=env,
                                      capture_output=True, text=True)

            os.makedirs(os.path.join(d, "omakeylog"), mode=0o755)
            loose = os.path.join(d, "omakeylog", "stats.json")
            with open(loose, "w") as fh:
                fh.write("{}")
            os.chmod(loose, 0o644)  # as 1.0 left it
            status = json.loads(run("status").stdout)
            self.assertEqual(os.stat(loose).st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(os.path.join(d, "omakeylog")).st_mode & 0o777, 0o700)
            self.assertEqual(os.stat(os.path.join(d, "omakeylog", "status.json")).st_mode & 0o777, 0o600)
            self.assertFalse(status["recording"])
            self.assertFalse(status["wanted"])
            self.assertEqual(run("report", "--json").returncode, 0)
            self.assertEqual(run("resume").returncode, 0)  # not wanted: no-op
            self.assertEqual(run("layout", "reset").returncode, 0)
            self.assertEqual(run("nope").returncode, 2)


class FakeDevice:
    """Stands in for evdev.InputDevice: readable through a pipe, and raises
    OSError on read once 'unplugged', like a removed keyboard does."""

    def __init__(self, path, events=()):
        self.path = path
        self.name = "fake " + path
        self.r, self.w = os.pipe()
        self.events = list(events)
        self.unplugged = False
        self.reads = 0
        os.write(self.w, b"x")

    def fileno(self):
        return self.r

    def read(self):
        self.reads += 1
        if self.unplugged:
            raise OSError(19, "No such device")
        os.read(self.r, 1)
        events, self.events = self.events, []
        return events

    def close(self):
        for fd in (self.r, self.w):
            try:
                os.close(fd)
            except OSError:
                pass


class FakeEvent:
    def __init__(self, code, value, t):
        self.type, self.code, self.value, self.t = 1, code, value, t

    def timestamp(self):
        return self.t


@unittest.skipUnless(importlib.util.find_spec("evdev"), "python-evdev not installed")
class RecordLoopTest(unittest.TestCase):
    def setUp(self):
        import evdev
        self.ecodes = evdev.ecodes
        self.dir = tempfile.TemporaryDirectory()
        self.saved = {}
        for name in ("DATA_DIR", "STATS", "STATUS", "STATE", "PIDFILE", "REPORT", "HISTORY"):
            self.saved[name] = getattr(E, name)
            setattr(E, name, os.path.join(self.dir.name, os.path.basename(getattr(E, name))))
        self.saved["RESCAN_SECONDS"] = E.RESCAN_SECONDS
        self.saved["session_active"] = E.session_active
        E.session_active = lambda sid: True

    def tearDown(self):
        for name, value in self.saved.items():
            setattr(E, name, value)
        self.dir.cleanup()

    def run_loop(self, devices, seconds, during=None, **kw):
        import signal
        import threading

        def stopper():
            if during:
                during()
            import time
            time.sleep(seconds)
            os.kill(os.getpid(), signal.SIGTERM)

        old = signal.getsignal(signal.SIGTERM)
        threading.Thread(target=stopper, daemon=True).start()
        try:
            E._run_loop(devices, **kw)
        finally:
            signal.signal(signal.SIGTERM, old)
        with open(E.STATS) as fh:
            return json.load(fh)

    def test_unplugged_keyboard_does_not_spin(self):
        k = self.ecodes
        dev = FakeDevice("/dev/input/event90",
                         [FakeEvent(k.KEY_A, 1, 0.0), FakeEvent(k.KEY_A, 0, 0.05)])
        other = FakeDevice("/dev/input/event91")

        def unplug():
            import time
            time.sleep(0.3)
            dev.unplugged = True
            os.write(dev.w, b"x")  # wake the selector with the dead device

        stats = self.run_loop([dev, other], 1.5, during=unplug, hotplug=False)
        self.assertEqual(stats["keys"], {"A": 1})
        self.assertLessEqual(dev.reads, 3)  # dropped after the first error
        other.close()

    def test_inactive_session_counts_nothing(self):
        # another user's session in front, or the screen locked
        k = self.ecodes
        E.session_active = lambda sid: False
        dev = FakeDevice("/dev/input/event90",
                         [FakeEvent(k.KEY_A, 1, 0.0), FakeEvent(k.KEY_A, 0, 0.05)])
        seen = {}

        def peek():
            import time
            time.sleep(0.3)
            with open(E.STATUS) as fh:
                seen.update(json.load(fh))

        stats = self.run_loop([dev], 0.5, during=peek, hotplug=False)
        self.assertEqual(stats["keys"], {})
        self.assertTrue(seen["recording"])
        self.assertTrue(seen["paused"])
        dev.close()

    def test_files_are_private(self):
        dev = FakeDevice("/dev/input/event90")
        old = os.umask(0o022)
        try:
            self.run_loop([dev], 0.5, hotplug=False)
        finally:
            os.umask(old)
        for name in (E.STATS, E.STATUS):
            self.assertEqual(os.stat(name).st_mode & 0o777, 0o600, name)
        dev.close()

    def test_hotplugged_keyboard_is_picked_up(self):
        k = self.ecodes
        first = FakeDevice("/dev/input/event90")
        late = FakeDevice("/dev/input/event92",
                          [FakeEvent(k.KEY_B, 1, 0.0), FakeEvent(k.KEY_B, 0, 0.05)])
        E.RESCAN_SECONDS = 0.2
        real_glob, real_open = E.glob.glob, E.open_keyboards
        E.glob.glob = lambda pattern: ["/dev/input/event90", "/dev/input/event92"]
        E.open_keyboards = lambda paths, explicit, skip=(), seat=None: (
            [late] if "/dev/input/event92" in paths else [], False, [])
        try:
            stats = self.run_loop([first], 1.2, hotplug=True)
        finally:
            E.glob.glob, E.open_keyboards = real_glob, real_open
        self.assertEqual(stats["keys"], {"B": 1})
        with open(E.STATUS) as fh:
            self.assertEqual(len(json.load(fh)["devices"]), 2)
        first.close()
        late.close()


if __name__ == "__main__":
    unittest.main()
