# Changelog

Notable changes to Before Sunset.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.3] - 2026-08-22

### Changed

- **Removal takes the config entry with it, and the readme now says so.** The
  section had claimed the entry in `shell.json` was left behind and handed over
  a `jq` line to remove it. It is not left behind: `omarchy plugin remove`
  disables the plugin first, and disabling splices the entry — slots, schedule,
  levels and all — straight out of the bar layout or the plugins list. The `jq`
  line stays as the fallback for the one case where it does survive, which is
  removing the plugin while the shell is not running.

  What actually remains is one file, `before-sunset.json`, and it is not deleted
  for you because it holds choices somebody made. Also named the one thing that
  genuinely stays changed: the bar's `transparent` flag, a bar setting rather
  than a plugin one, left wherever the schedule last put it.

- **The night light stops asking every three seconds when nobody is looking.**
  Each probe is a shell script, an `hyprctl` round trip and a `jq` — thirty-two
  milliseconds measured, which at three seconds is twenty-eight thousand runs a
  day for a value that only changes when somebody presses a key. Three seconds
  is kept for when it earns it: the panel open, a ramp in flight, or a write
  still settling. Otherwise fifteen, which is still well inside the minute the
  schedule itself runs on.

- **The light sensor is read only when its reading is on screen.** "No reason to
  read a sensor nobody is looking at" was the intent; "the panel is open" was
  too loose a reading of it. One raw read blocks in the driver for about six
  hundred milliseconds while the sensor wakes and integrates — twice over on a
  machine with two of them — so an open panel spent a second in every three
  reading a sensor, and holding it awake, on desktops where the number was not
  visible and the schedule was not using it. It now also wants the schedule
  section unfolded and the sensor actually selected.

- **The retry that waits for the service gives up.** Where the service never
  arrives, it was two wake-ups a second for the length of the session, asking a
  question that had already been answered. Twenty attempts, then it stops.

### Added

- **The panel's icon is drawn, not typed.** A braille cell is a grid of 2x4
  dots, so six characters across three lines give a canvas twelve dots square —
  enough for a disc that reads as round, which a drawing made of block elements
  at this size cannot manage.

  By day the sun's rays turn slowly. The disc itself holds still: what moves is
  the light coming off it. Only while the panel is open, so a closed panel costs
  nothing.

  By night it is the moon, at **tonight's real phase**. Counted from a known new
  moon through the mean synodic month, which is a picture rather than an
  ephemeris — it drifts a few hours against the sky and under a day across a
  century, and nobody can see that in twelve dots. The terminator is drawn as an
  ellipse, which is what makes a crescent a crescent rather than a bitten
  circle, and the unlit part is a rim rather than nothing, so a new moon is
  still a moon and not an empty square.

  The moon does not animate. It is the one thing in the icon that is measured
  rather than drawn, and spinning it would be a lie about that.

  The bar keeps its single glyph, because a bar cell is one character wide.

## [0.7.2] - 2026-08-22

### Added

- **The screens slide rather than step.** A hardware brightness change is a
  step: DDC and `asdcontrol` take one value and the screen is at it. Stepping
  the whole desktop at dusk is the thing this plugin exists not to do — but
  writing a hundred intermediate values is worse, because DDC brightness lives
  in the monitor's own memory and some panels have a finite number of writes in
  them.

  So the slide is drawn in gamma and the hardware moves once. `hyprsunset`
  already holds a gamma table for every output — it is what the night light
  drives — and takes a percentage over the same socket, at about four
  milliseconds a write and nothing at all in the monitor.

  At dusk gamma slides down to the ratio between where a screen is and where it
  is going, and at the bottom the hardware takes the real value while gamma
  returns to full. At dawn the two happen together, so nothing jumps, and gamma
  slides back up afterwards. Both swaps are ordered so the gap reads as a
  momentary dip rather than a flash.

  Gamma is one table for the whole session, so with several displays the slide
  follows the shallowest of them: nothing is ever darker on the way than it will
  be at the end.

  The fade is clock-driven rather than counted in steps, so it takes the seconds
  it was given whatever the machine costs per write — the first draft asked for
  four seconds and took eight. Touch the brightness keys mid-slide and it stops.
  Without `hyprsunset`, or with the fade set to zero, the hardware steps exactly
  as it did in 0.7.0.

- **A Fade (s) field**, beside the night level, where the volume has had one all
  along.

### Changed

- **The readme says which version it is**, at the top, next to a link to this
  file. It is the third place the number lives, and the three are expected to
  agree.

- **The heading screenshot was retaken.** It still showed a two-item line under
  a heading with no pill in it, while the caption underneath had been rewritten
  in 0.7.1 to promise three items and the caption was the only thing telling the
  truth.

## [0.7.1] - 2026-08-22

### Added

- **The dim joins the heading line.** The temperature and the volume were
  already there; the dim sat one section further down for no reason. All three
  now read at a glance.

- **The levels name the half they belong to.** They read the night value and
  said "at night" whatever the hour, which was unreadable at four in the
  afternoon once a day level could be set too. Now the line shows the half that
  is running — `80% at day` — and falls back to the half that is coming when
  the one running has no level of its own.

- **The dim and the volume leave the line when they have stood down.** Pinned,
  or under the light sensor, neither of them moves; a line promising 40% at
  night was promising something nobody was going to do. The night light stays
  put, because it keeps its own hours whatever the mode.

- **What the day is doing moved to the corner of the heading**, into a pill —
  `DAY → 19:50`, an arrow rather than a separator, because the time is not a
  property of the half that is running but where that half is going — where it can be read at any moment rather than waited for. It
  had been the whole of the line under the title, which is the one place in the
  panel with nothing to do: the number it carried is already three rows down in
  the schedule section.

- **So that line now says what the plugin is doing to work it out.** Consulting
  the almanac. Reading the twilights. Halving the day. Solving for dusk.

  Two rules. Each has to be true of what the plugin actually does: it really is
  an almanac algorithm, there really are three twilights to read, the terminator
  really is the line it chases, and dusk really is solved for rather than asked
  after. And none of them borrows a verb from the other panels that do this —
  Omarchy has five such lists, and between them they have already taken sorting,
  counting, watching and thirty more. Sounding like the network panel with
  different nouns would be the joke wearing someone else's coat.

  Only in Auto does it cycle. Pinned it reads "Holding the night" and stays
  there — holding a half is a state worth naming once, and a line that kept
  changing under a pinned desktop would suggest the plugin is up to something it
  is deliberately not up to.

## [0.7.0] - 2026-08-22

### Added

- **The screens dim at night.** A night level and a day level, and every
  display that can be driven moves to them when the day turns over — the same
  shape the volume has, with the same one-directional rule. Night dims and
  never brightens, day brightens and never dims, so a screen turned down by
  hand in the afternoon is still where it was left at dusk. A floor of a few
  percent sits under every target, because a screen at zero is a screen nobody
  can find the setting on again.

  One pair of numbers covers most setups, so that is what the section shows.
  **Per display** folds open a row for each display that answered, each
  starting on the pair above — taking one off the pair never changes what the
  screen is doing, only what moves it next time. Overrides are keyed by EDID
  serial rather than by connector, so a display keeps its numbers across a
  replug, and keeps them while it is unplugged.

  Displays that answer nothing are not listed and not reported. Where none
  answers, the section is not drawn at all, the same way the light sensor is
  absent on machines without one.

  No notification: this is the one scheduled change nobody can fail to notice.

### Changed

- **A pinned theme keeps the schedule on screen.** Pinning Day or Night removed
  the whole section, which left two separators stacked with a gap between them
  — and told a lie on the way out. The schedule keeps running while a theme is
  pinned: the night light, the brightness and the volume all still follow it,
  and only turning the plugin off stops any of that. So the section stays, at
  full strength and fully adjustable, and says what it is still driving.

  The line under the mode buttons said "the schedule is not running", which was
  the same lie in fewer words. It now says the theme is not following it.

- **A pinned half stops the volume and the brightness.** Pinning Day or Night
  is an instruction to hold that half's settings, and neither of those two has
  hours of its own to fall back on — they only ever ride the schedule. So the
  schedule stands down with the pin and they stand down with it, rather than
  moving the room on a timetable the desktop has been taken off.

  The night light is the exception, and on purpose: it has its own hours, so it
  keeps them. Pinning a theme says something about colours on screen, not about
  whether your eyes want a warmer picture at midnight.

- **Handing control back lands the room where the schedule says it is.** A
  machine pinned to Day all evening would otherwise sit on daylight levels until
  tomorrow's dusk — the schedule quietly not running for a whole night. Auto now
  means now, which is how the theme has always behaved: it repaints the moment
  it is handed the wheel rather than waiting for the next turn. A fresh session
  is still not a hand-back and still fades nothing.

- **Dimming a section means one thing: nothing here is being driven.** The
  schedule, the volume and the brightness dim while a half is pinned, and the
  volume and the brightness dim under the light sensor too — it answers whether
  the room is dark, not when it turned, and a fade has to happen at the turn.
  Each says which of the two it is. Everything stays adjustable while dimmed:
  setting up the night levels in the middle of the afternoon is the normal way
  round.

- **Apple's displays are driven per device.** `omarchy-brightness-display
  --monitor DP-2` takes the monitor name and then hands the work to a helper
  that ignores it, driving whichever Apple display it detected first. With two
  Studio Displays connected, every write lands on the same panel and the other
  never moves — so those are addressed directly, for the same reason the night
  light drives `hyprsunset` rather than Omarchy's toggle.

  Which one is on which connector is not knowable: a display's EDID serial and
  its USB serial have nothing in common. So they are listed as displays rather
  than as monitors, and the live reading in each row is what tells two
  identical panels apart.

## [0.6.4] - 2026-08-22

### Added

- **The command line reaches the other two mode groups.** `schedule` picks what
  auto follows — sun, fixed hours, or the light sensor — and `nightlight` takes
  off, auto or always, the same three words the panel puts on its buttons.
  `off` stands the plugin down, and day, night or auto starts it again with
  every slot, background and remembered transparency still in place.

  Each answers with the value it settled on, so a key binding can act on the
  result rather than asking twice. Handed an empty string, both report the mode
  in force and change nothing.

  Deliberately no numbers: temperatures, offsets, thresholds and volumes stay
  in the panel, where the day is drawn while you choose them. A number typed
  blind at a prompt is the one kind of setting this plugin cannot show you the
  consequence of.

### Changed

- **The readme says how to update.** `omarchy plugin update` on this plugin
  fetches, shows the diff, fast-forwards and re-validates — with the two limits
  worth knowing before you meet them: it never prompts for credentials, and it
  never merges over local edits.

- **A fresh night light screenshot**, matching the panel as it stands.

## [0.6.3] - 2026-08-22

### Added

- **A machine waking up is already in the right half of the day.** The minute
  tick is monotonic — it does not run while the machine is suspended — so a
  laptop that slept through the night could sit on the night theme for the
  better part of a minute after being opened, and turn over while its owner
  watched. logind announces a resume on the system bus at the moment it
  happens, before the lock screen has asked for a password; the schedule is now
  evaluated there, so the day theme is already on screen behind the prompt.

  A second pass follows three seconds later, because Hyprland is still coming
  back at the instant the announcement arrives and `hyprctl` can refuse a call
  that would have worked a moment afterwards.

  It is a shortcut rather than a new mechanism: where there is no `gdbus`, or
  the bus goes away, the tick still corrects everything exactly as it did
  before, just later.

- **`omarchy-shell before-sunset refresh`** re-evaluates on demand — the same
  nudge a resume gives, for anyone who would rather hang it off their own hook
  than rely on the bus.

## [0.6.2] - 2026-08-21

### Added

- **The schedule bar shades the twilight.** Either side of the day block, the
  bar now fades out across the real span of twilight — from the boundary to
  where the sky finally runs out of light, eighteen degrees down. Today at
  this latitude that is two and a half hours the bar previously drew as flat
  night.

  It makes the Boundary control explain itself: the shading is the range the
  turn can be moved across, so switching from Horizon to Civil visibly steps
  the line along a span you can already see.

  The day block keeps its hard edges. A theme switch is a step — everything
  repaints at once — and softening that edge would draw a fade that does not
  happen. What is gradual is the light, which is what the shading shows.

  Where there is no astronomical twilight, which at these latitudes means
  midsummer, the shading simply is not drawn.

## [0.6.1] - 2026-08-21

### Added

- **The night light can keep its own hours.** Following the theme schedule is
  still the default, but the two are not always the same wish: a theme can turn
  at sunset while the screen has no business warming until the evening proper.
  Its own hours also give it a timetable under the light sensor, which has none,
  so the day strip can be drawn there too.

### Changed

- **The schedule bar matches the night light strip.** Both describe the same
  midnight-to-midnight axis and sat one above the other looking like they came
  from different panels — one a rounded pill, the other a flat block. Same
  height, same corners, same marker now, and more contrast between the halves.
- **Omarchy's toggle registers in two or three seconds** instead of five to ten.
  A toggle value still has to survive a second look, but that look now happens
  immediately rather than on the next round of polling: the wait exists to
  outlast a stale reading, which takes a moment, not five seconds.

## [0.6.0] - 2026-08-21

### Changed

- **Renamed to Before Sunset.** "Auto Theme" said what it did in the flattest
  possible way, and said it in a catalogue that already has a Darky and a Dusk.

  The rename is complete rather than cosmetic, so it moves things that were
  addressable from outside:

  | | was | is |
  |---|---|---|
  | plugin id | `priard.auto-theme` | `priard.before-sunset` |
  | CLI | `omarchy-shell auto-theme …` | `omarchy-shell before-sunset …` |
  | repository | `omarchy-auto-theme` | `omarchy-before-sunset` |
  | remembered state | `settings/auto-theme.json` | `settings/before-sunset.json` |

  An existing install needs its id updated in `~/.config/omarchy/shell.json`,
  and the state file renamed if the remembered wallpapers and bar transparency
  are worth keeping.

## [0.5.1] - 2026-08-21

### Fixed

- **The night light buttons work again.** Pressing Omarchy's toggle set a hold
  that nothing in the panel could clear, so Off, Auto and Always all appeared
  dead until the day next turned over, and the heading kept reporting "held"
  while the mode said Auto. Choosing a mode is an instruction and now outranks
  the hold.
- **Our own write is no longer mistaken for someone pressing the toggle.**
  hyprctl does not report a change the instant it is made, so the reading left
  over from just before one of our writes looked exactly like the toggle being
  pressed — and acting on it rewrote the setting that had caused it, flipping
  the mode back moments after it was chosen. A toggle value now has to survive
  a second look before it counts; a stale reading does not.
- **Switching to Off hands the screen back** instead of walking away from it
  still warm. We are the reason it is warm; leaving it that way and stopping
  was the one outcome nobody asked for.

## [0.5.0] - 2026-08-21

### Fixed

- **Omarchy's night light toggle is registered again.** Switching it on while
  the plugin was already in auto did nothing at all: a leftover two-state test
  read "already agrees" and returned before doing anything, and the next tick
  quietly pulled the screen back. Both directions now register.
- **Within seconds rather than up to a minute.** The toggle sits on the bar and
  in the menu; a minute of the panel disagreeing with the screen reads as the
  plugin being broken. Detection is now three to four seconds.

### Added

- **The day drawn in its own colours.** The night light section shows the whole
  day as a strip tinted with the temperature the screen will actually be, with a
  marker for now. It comes from the same function that drives hyprsunset, so the
  picture cannot drift from what happens. It also answers the question the
  numbers could not: switching to auto in the afternoon appears to do nothing
  because the marker is still in the neutral stretch, and the strip shows that
  at a glance.
- **A line under the panel heading** carrying the temperature on screen, in a
  swatch of that colour, and the night volume — both visible without opening
  either section.
- Pressing Omarchy's toggle now says so in the panel, with the moment the
  schedule takes over again.

## [0.4.0] - 2026-08-21

### Added

- **The night light follows the day, gradually.** Omarchy ships an on/off
  toggle with two fixed temperatures and nothing in between. The screen now
  eases from neutral to warm across the turn of the day — three quarters of an
  hour by default, smoothstepped so neither end arrives with a visible corner.
  No step of it is large enough to notice.
- **Three modes of its own: off, auto, always.** Deliberately separate from the
  theme's mode, because warming the screen after dark and pinning a theme are
  different wishes. Pinning the theme to Day no longer keeps the screen cold all
  night. `off` leaves Omarchy's toggle behaving exactly as it always has.
- **Shared with Omarchy's toggle, both ways.** Switching the night light on
  there hands the schedule the wheel; switching it off takes it back. Our ramp
  drives the same hyprsunset the toggle does, and the bar indicator is refreshed
  after each step so its icon never lies about what is on screen.
- Pressing that toggle at a time the schedule disagrees with holds your choice
  until the day next turns over, rather than being undone a minute later.
- Configurable warmth, span, and how far ahead of the turn to begin.

### Changed

- The schedule is now computed whether or not the theme follows it, so the
  night light and the night volume keep working while a theme is pinned.

## [0.3.0] - 2026-08-21

### Added

- **The volume can ease down at nightfall.** Set a level and the output volume
  slides to it when the schedule turns the day over — no jump, no on-screen
  display, just the room getting quieter. An optional counterpart eases it back
  up at daybreak.
- Night never raises the volume and day never lowers it, so a machine you
  deliberately hushed stays hushed.
- Reaching for the volume mid-fade stops the fade. Someone pressing the volume
  keys has an opinion about the volume, and it outranks the schedule's.
- Only the sun and fixed hours move it, and only on their own transitions —
  never when you pin a half yourself. Under the light sensor a lamp being
  switched on is not the morning.

### Fixed

- **A wallpaper changed outside the plugin now shows up in the panel.** Two
  faults, both the same shape. The remembered wallpaper was published to the
  panel before it was written to the state file the panel reads, so the panel
  was handed the value being replaced. And both the panel and the service
  dropped a refresh that arrived while one was already running — which is
  precisely the request carrying the change that just happened. Requests now
  queue, the file is written first, and opening the panel re-reads everything
  regardless.

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
- Bar widget, settings panel, and an `omarchy-shell before-sunset` CLI.
