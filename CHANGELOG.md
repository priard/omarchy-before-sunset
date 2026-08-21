# Changelog

Notable changes to Auto Theme.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-08-21

### Fixed

- **The transparency switch now takes effect immediately** on the half of the
  day that is running. It only stored the preference before, applying it at the
  next theme switch, which reads as a switch that does nothing. Slots that are
  not running are still stored and left alone — changing the night theme's bar
  in the middle of the afternoon should not touch the desktop.

### Added

- **A sensor picker when the machine has more than one.** Laptops often carry
  two, and they disagree by design, so the default remains their average. The
  labels carry each sensor's live reading, because two devices both reporting
  themselves as `als` are otherwise impossible to tell apart. A named sensor
  that disappears — across a suspend, say — falls back to the average rather
  than going blind.

## [0.2.0] - 2026-08-21

More ways to decide which half of the day it is, and a panel that shows what
the settings do instead of describing it.

### Added

- **Light sensor schedule.** Machines with an ambient light sensor can decide
  from the room rather than the clock — useful behind heavy blinds, or where
  the sun gets no say. The sensor is read straight from the kernel's IIO files,
  so it needs nothing installed; where no sensor exists the option does not
  appear at all.
- **Calibration from the live reading.** Sensor readings are raw counts, not
  lux, and differ by orders of magnitude between machines, so no shipped
  threshold could mean anything. The panel shows what the sensor says right now
  and turns it into the threshold on request.
- **Hysteresis and a dwell timer** on the sensor, so a hand passing over it is
  not mistaken for dusk and a reading sitting on the threshold does not
  oscillate.
- **The day, drawn.** The sun schedule now shows the day as a strip — night,
  the lit stretch, night again — with a marker for now, built from the
  effective switch points rather than the raw sunrise and sunset.
- **Boundary and offsets in the panel.** Choosing between the visible horizon
  and the three twilights, and nudging either side by minutes, already worked;
  both were reachable only by hand-editing `shell.json`, and their effect had
  to be imagined. The strip above them redraws as they change.
- **Theme and wallpaper previews.** Each slot shows the two pictures that
  actually decide how that half of the day looks. Both are clickable: the theme
  opens Omarchy's theme picker, the wallpaper opens the image picker over that
  theme's backgrounds.
- **Wallpaper picking for the half of the day that is not running.** Omarchy's
  own background switcher only ever offers the theme currently applied, so it
  could not set the other slot's wallpaper.

### Changed

- **The panel is organised by how often you touch things.** The mode and the
  two slots are always there; the schedule sits behind a heading that
  summarises itself — `SCHEDULE  Sun · 05:27 – 19:54` — and opens when you want
  it. Settings you set once no longer claim permanent height, and everything
  that stayed got more room around it.
- **The panel scrolls when it does not fit.** Its height is clamped to the
  screen and the content did not scroll, so on a short display the bottom was
  simply cut off with no way to reach it. Now it flicks — but only when there
  is something to reach.
- The transparency switch rides on its slot's heading row instead of taking a
  row of its own.
- Both pickers open with *that slot's* current choice selected rather than
  whatever is on screen. Those differ precisely when you are setting up the
  half of the day that is not running.
- The transparency control is a caption and a switch instead of a full-width
  bordered row.
- A schedule that cannot run — sensor mode without a threshold, sun without a
  location — falls back rather than freezing, and the panel shows what is
  actually in force.

## [0.1.0] - 2026-08-21

First working version.

### Added

- Two theme slots, **day** and **night**, named for the half of the day they
  cover rather than for a colour, so two light themes is a legitimate setup.
- Sunrise and sunset computed locally with the US Naval Observatory almanac
  algorithm, cross-checked against an independent NOAA implementation and
  agreeing to within a minute. No network calls.
- Fixed clock times as an alternative, and as the fallback during polar day and
  polar night.
- Pinning either half, from the panel, a right-click on the bar icon, or the
  CLI.
- **Adoption:** a theme picked anywhere — the theme switcher, the Omarchy menu,
  `omarchy theme set`, a keybinding — lands in the slot currently in force, so
  the schedule learns from what you do instead of fighting it.
- **A background remembered per theme,** restored on every switch.
  `omarchy theme set` otherwise picks a theme's first background each time it
  enters that theme, quietly discarding the wallpaper you chose.
- **Bar transparency remembered per theme,** with a guard: when a wallpaper's
  format has no decoder on the system it is never painted, the desktop shows
  black, and the bar colours itself for a picture nobody can see. Transparency
  is held off until the format can be decoded, and the preference is captured
  first so it comes back by itself.
- Seeding on first run from the theme already on screen, so the plugin works
  immediately without changing the desktop out from under you.
- Bar widget, settings panel, and an `omarchy-shell auto-theme` CLI.
