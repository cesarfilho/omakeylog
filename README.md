# Omakeylog

An Omarchy bar widget that measures **how often you press each key and each
adjacent key-pair**, so you can design a better QMK keymap: what deserves the
home row, what to move onto a thumb key or a layer, and which awkward
same-finger moves your current layout forces on you.

It records **aggregate counts only**, never the text you type.

<p align="center">
  <img src="preview.png" alt="The Omakeylog panel: finger load bars, top key-pairs and the controls" width="419">
</p>

## Contents

- [Features](#features)
- [Privacy](#privacy)
- [Requirements](#requirements)
- [Install](#install)
- [Use](#use)
- [Settings](#settings)
- [Reading the analysis](#reading-the-analysis)
- [From the numbers to a QMK keymap](#from-the-numbers-to-a-qmk-keymap)
- [Engine CLI](#engine-cli)
- [Data files](#data-files)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Update](#update)
- [Remove](#remove)
- [License](#license)

## Features

- **Per-key counts** for every key on every keyboard attached, including
  modifiers, arrows, Enter, Backspace and the Super key.
- **Bigram counts**: how often each key follows another (for example `T → H`),
  the raw input every layout optimizer works from.
- **Hand balance**: left, right and thumb share of all presses.
- **Finger load**: the share carried by each of the eight fingers plus the
  thumbs, based on standard QWERTY touch-typing fingering.
- **Row usage**: home, top, bottom, number row and thumb.
- **Same-finger bigrams (SFBs)**: the pairs your current layout makes you type
  with one finger twice, and what share of all pairs they are.
- **QMK suggestions** in plain language: frequent keys off the home row,
  overloaded fingers, underused fingers, and a high SFB rate.
- **Recording that survives shell reloads**: the counter is a separate
  background process, started and stopped from the bar.
- **CSV export** for external layout tools (oxeylyzer, genkey and similar).
- **Safe reset**: resetting backs the old counts up instead of deleting them.

## Privacy

A key logger is sensitive software, so here is exactly what this one keeps.

- One dictionary of **key → number of presses**.
- One dictionary of **key pair → number of times typed back-to-back**. A pair
  only counts when the second key comes within 1.5 seconds of the first.

It never keeps the order of your keypresses, never stores a timestamp per key,
never records which window had focus, and never sends anything over the
network. Only key-down events are counted; auto-repeat and releases are
ignored. Totals like "E was pressed 4,812 times" and "T → H happened 610 times"
cannot be turned back into the passwords or messages you typed.

All data stays in `~/.local/share/omakeylog/` as plain JSON you can open and
read yourself (see [Data files](#data-files)). Recording is **off** until you
press **Start**, and the bar icon lights up whenever it is on.

## Requirements

Omakeylog reads the keyboard through Linux evdev (`/dev/input/event*`), which
needs two things that Omarchy does not set up by default. Do this once:

1. **The evdev Python binding**

   ```bash
   omarchy pkg add python-evdev
   ```

2. **Read access to the keyboard devices**: add your user to the `input`
   group, then **log out and back in** (group changes only apply to new
   sessions).

   ```bash
   sudo usermod -aG input "$USER"
   ```

   Check it took effect after logging back in: `id -nG | grep -w input`.

The engine always runs under the system interpreter `/usr/bin/python3`. That
matters if you use mise, pyenv or asdf: their `python3` comes first on your
`PATH` and would not see the `python-evdev` package from pacman.

Until both steps are done, the panel shows what is missing and how to fix it,
and recording stays off.

## Install

```bash
omarchy plugin add https://github.com/cesarfilho/omakeylog.git --enable
```

Or by hand: clone this repository into
`~/.config/omarchy/plugins/io.github.cesarfilho.omakeylog/`, then run
`omarchy plugin enable io.github.cesarfilho.omakeylog`.

The widget goes to the right side of the bar. Move it with
`omarchy bar move io.github.cesarfilho.omakeylog --section left`.

## Use

| Action | What it does |
|---|---|
| Left-click the keyboard icon | Open or close the panel |
| Middle-click the keyboard icon | Start or stop recording without opening the panel |
| **Start recording** / **Stop** | Start or stop the background counter |
| **Refresh** | Recompute the analysis now |
| **Reset**, then **Confirm reset** | Back up the current counts and start from zero |

Keyboard shortcuts while the panel is open: `S` start/stop, `R` refresh, `X`
reset, `Esc` close.

The icon is dimmed when nothing has been recorded yet and highlighted while
recording. Hover it for the current total.

Counts accumulate across sessions and reboots. Short samples are skewed by
whatever you happened to be doing (an afternoon of Vim leans heavily on
`J`/`K`; a day of chat leans on Space and Enter), so **record normal work for a
few days** before drawing conclusions. After a reboot, press **Start** again:
the counter does not start on its own.

## Settings

Change these from the Omarchy settings panel, or in the widget's entry in
`~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `showLabel` | `false` | Show a number next to the bar icon |
| `labelMode` | `Total` | `Total`: keypresses on record. `Top key`: your most-pressed key |
| `topKeys` | `12` | Keys listed in the panel (5–40) |
| `topBigrams` | `10` | Key-pairs listed in the panel (5–30) |
| `refreshIntervalSec` | `3` | How often the open panel refreshes (1–30 s) |

When the panel is closed, the widget checks the engine every 8 seconds so the
icon reflects whether recording is on.

## Reading the analysis

The panel shows these sections, top to bottom:

- **Most-pressed keys**: your keys ranked by count and share. The top of this
  list is your prime real estate and belongs on the strongest, easiest
  positions: home row, index and middle fingers, thumb keys.
- **Hand balance**: left vs right vs thumb. Around 50/50 between the hands is
  comfortable; a big skew means one hand is doing the work.
- **Finger load**: share per finger. Pinkies and ring fingers are weak, so a
  pinky above roughly 10% is a classic target for a fix (Backspace, Enter and
  Shift usually cause it).
- **Top key-pairs**: the most common back-to-back pairs, including modifiers
  (`LEFTCTRL → C`) and editing pairs (`BACKSPACE → BACKSPACE`).
- **Same-finger bigrams**: pairs typed by one finger twice, such as `E → D` or
  `R → T` on QWERTY. They are slow and tiring, and the main thing an optimized
  layout reduces. Repeats of the same key (`L → L`) are not counted.
- **QMK suggestions**: short, plain-language takeaways from all of the above.

Fingering assumes standard QWERTY touch typing on a row-staggered keyboard:
Space is the thumb, and keys outside the main block (arrows, F-keys, Super)
show up in the key ranking but not in the finger or row breakdown.

## From the numbers to a QMK keymap

Some common ways to act on what you see:

- **A frequent key sits off the home row** (Backspace, Enter, a bracket): put
  it on a thumb key, or behind a layer key held by the thumb.
- **A modifier is near the top of the ranking** (Ctrl, Shift, Super): try
  [home-row mods](https://docs.qmk.fm/mod_tap), so `A S D F` double as
  modifiers when held.
- **A pinky carries too much**: move Backspace and Enter to thumbs; Escape can
  go on a tap-dance or a combo.
- **High same-finger rate**: consider an alternative alpha layout (Colemak-DH,
  Graphite, or one generated from your own data). Export the counts with
  `engine/omakeylog report --csv` and feed them to an optimizer.
- **Repeated `BACKSPACE → BACKSPACE`**: a word-delete key (`C(KC_BSPC)`) on a
  layer saves a lot of presses.

Re-record after each change. Comparing the before and after finger load and SFB
rate shows whether the change helped.

## Engine CLI

The panel drives a small command-line program you can also run directly. From
the installed plugin folder
(`~/.config/omarchy/plugins/io.github.cesarfilho.omakeylog/`):

```bash
engine/omakeylog record                 # start counting in the background
engine/omakeylog record --foreground    # count in this terminal (Ctrl+C stops)
engine/omakeylog record --device /dev/input/event3   # only this device (repeatable)
engine/omakeylog stop                   # stop the background counter
engine/omakeylog status                 # JSON: recording, pid, devices, error, totals
engine/omakeylog report                 # readable report with QMK suggestions
engine/omakeylog report --json          # same analysis as JSON (what the panel reads)
engine/omakeylog report --csv           # key,count,percent - for layout optimizers
engine/omakeylog reset                  # back up stats.json and start from zero
```

Without `--device`, it picks up every device that has letter keys and a space
bar, so mice, power buttons and lid switches are skipped, and laptop and
external keyboards are counted together. Use `--device` to count only one of
them; `ls -l /dev/input/by-id/` shows which `eventN` is which keyboard.

## Data files

Everything lives in `~/.local/share/omakeylog/`, or under `$XDG_DATA_HOME` if
you set it:

| File | Contents |
|---|---|
| `stats.json` | The raw counts: `keys` (`"E": 4812`) and `bigrams` (`"T>H": 610`) |
| `report.json` | The derived analysis the panel displays |
| `status.json` | Whether recording is on, which devices, last error, totals |
| `omakeylog.pid` | Process ID of the running counter (only while recording) |
| `stats.json.YYYYMMDD-HHMMSS.bak` | Backups made by **Reset** |

Counts are saved every 5 seconds while you type, and once more when recording
stops, so at most a few seconds are lost if the machine loses power.

## How it works

Two parts cooperate:

- **`engine/omakeylog`**: a single-file Python program, no dependencies beyond
  `python-evdev`. It reads key-down events from the keyboard devices, keeps the
  two tallies in memory, writes them to disk, and computes the analysis. It
  runs as your own user, detached from the shell, so a shell reload or a
  `omarchy restart shell` doesn't stop recording.
- **The bar widget** (`BarWidget.qml`, `Panel.qml`, `Model.js`): starts and
  stops the engine, polls its status, and renders `report.json`. The QML only
  displays; all counting and analysis happen in the engine.

No root privileges, system services or network access are involved.

## Troubleshooting

**The panel says "no read access to /dev/input".** You are not in the `input`
group in this session. Run the `usermod` command from
[Requirements](#requirements), then log out and back in; a new terminal is not
enough.

**The panel says "python-evdev is not installed".** Install it with
`omarchy pkg add python-evdev`. If it is already installed, check that the
system interpreter sees it: `/usr/bin/python3 -c 'import evdev'`.

**"No keyboard devices found".** No device reported letter keys and a space
bar. List them with `ls -l /dev/input/by-id/` and pass yours explicitly:
`engine/omakeylog record --device /dev/input/eventN`.

**Recording stopped after a reboot.** That is by design; press **Start**
again. The counts from before are kept.

**The bar shows an old version after updating.** Run `omarchy restart shell`;
the running shell keeps the previous widget in memory.

**Counts look wrong for a remapped keyboard.** evdev reports the key codes the
keyboard sends. On a QMK board, a key on a layer reports the code it produces
(for example `LEFT`), not the physical position you pressed.

## Update

```bash
omarchy plugin update io.github.cesarfilho.omakeylog
omarchy restart shell
```

Your recorded counts are kept across updates.

## Remove

Stop recording first, with the **Stop** button or:

```bash
~/.config/omarchy/plugins/io.github.cesarfilho.omakeylog/engine/omakeylog stop
```

Then remove the plugin:

```bash
omarchy plugin remove io.github.cesarfilho.omakeylog
```

The recorded counts are left in place in case you reinstall. Delete them with
`rm -rf ~/.local/share/omakeylog`. If you added yourself to the `input` group
only for Omakeylog, undo it with `sudo gpasswd -d "$USER" input` and log out
and back in.

## License

[MIT](LICENSE) © cesarfilho
