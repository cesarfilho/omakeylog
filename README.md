# omakeylog

An Omarchy bar widget that measures **how often you press each key and each
adjacent key-pair**, so you can design a better QMK keymap — home-row
placement, thumb/layer keys, and fewer awkward same-finger moves.

It records **aggregate counts only**. It keeps one tally of how many times each
key was pressed, and one tally of how many times each pair of keys was pressed
back-to-back. It never stores the order you typed in, never timestamps
individual keys, and never records which window had focus — so the text you
type (passwords, messages, anything) **cannot be reconstructed** from its data.

## How it works

Two cooperating parts:

- **`engine/omakeylog`** — a small Python/evdev program that reads the keyboard
  and keeps the tallies. It runs as a separate process so recording survives a
  shell reload, and so it can use your own `input`-group access rather than
  anything privileged in the shell.
- **The bar widget** (`BarWidget.qml` + `Panel.qml`) — shows how many keys are
  on record, starts/stops the engine, and renders the analysis: ranked keys,
  hand and finger load, same-finger bigrams, and QMK suggestions.

## Prerequisites (one-time)

```bash
# 1. the evdev Python binding
sudo pacman -S --needed python-evdev        # or: omarchy pkg add python-evdev

# 2. read access to the keyboard devices (/dev/input/event*)
sudo usermod -aG input "$USER"              # then LOG OUT and back in
```

The engine runs under `/usr/bin/python3` (the system interpreter), not whatever
`python3` your shell resolves to — on this machine a mise-managed Python shadows
it and wouldn't see the pacman-installed `evdev`.

Until you have re-logged-in after step 2, the panel shows the exact fix and
recording stays off.

## Install

```bash
omarchy plugin add https://github.com/cesarfilho/omakeylog.git --enable
```

Or by hand: clone this repository into
`~/.config/omarchy/plugins/io.github.cesarfilho.omakeylog/`, then run
`omarchy plugin enable io.github.cesarfilho.omakeylog`.

After updating the plugin, run `omarchy restart shell`: the running shell keeps
the old widget in memory until it restarts.

## Remove

Stop recording first (the **Stop** button, or the CLI below), then:

```bash
~/.config/omarchy/plugins/io.github.cesarfilho.omakeylog/engine/omakeylog stop
omarchy plugin remove io.github.cesarfilho.omakeylog
rm -rf ~/.local/share/omakeylog          # optional: delete the recorded counts
```

## Use

- Click the keyboard icon on the bar to open the panel; **Start** to record,
  **Stop** when done. Middle-click the bar icon toggles recording directly.
- Recording accumulates across sessions. Type normally for a few days for the
  most representative data, then read the suggestions.
- **Reset** (twice to confirm) backs up the current counts and starts fresh.

## Engine CLI

```bash
engine/omakeylog record [--device /dev/input/eventN] [--foreground]
engine/omakeylog stop
engine/omakeylog status
engine/omakeylog report              # human-readable, with QMK suggestions
engine/omakeylog report --json       # writes report.json (the panel reads this)
engine/omakeylog report --csv        # ranked keys, for oxeylyzer/genkey etc.
engine/omakeylog reset
```

Data lives in `~/.local/share/omakeylog/` (`stats.json` = the raw counts,
`report.json` = the derived analysis). `stats.json` is yours to inspect — it
holds only the two count dictionaries.

## What the suggestions mean

- **Most-pressed keys** are your prime real estate — they deserve the easiest
  positions (home row, strong fingers, thumb keys).
- **Same-finger bigrams (SFBs)** are pairs typed by moving one finger twice;
  they're the main thing an optimized layout reduces. The list shows your worst.
- **Finger load** flags fingers doing too much or too little, to help you
  rebalance.

Author: cesarfilho · MIT
