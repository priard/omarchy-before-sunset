import QtQuick
import Quickshell
import Quickshell.Io
import "Sun.js" as Sun

// Keeps the Omarchy theme in step with the sun: one theme for the day half,
// another for the night half. Either slot may hold any theme — two light
// themes is a legitimate setup, which is why the slots are named for the half
// of the day they cover rather than for a colour.
//
// The service holds no countdown. Every tick recomputes, from scratch, which
// half of the day the current instant falls in and compares that to the theme
// actually on screen. That is what makes it survive suspend, hibernate, clock
// changes and daylight saving: a laptop opened after two days asleep corrects
// itself on the next tick instead of waiting out a timer that never ran.
//
// The resume is not waited for, though: logind announces it on the system bus,
// and the correction lands before the lock screen has been answered.
Item {
  id: root

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "priard.before-sunset"
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy"
  readonly property string themeNamePath: stateDir + "/current/theme.name"
  readonly property string currentDir: stateDir + "/current"
  readonly property string backgroundLink: stateDir + "/current/background"
  // Written by omarchy-weather-location, and shared with the weather widget so
  // a location only ever has to be set once.
  readonly property string locationPath: stateDir + "/settings/weather.json"
  readonly property string memoryPath: stateDir + "/settings/before-sunset.json"

  function pluginFile(name) {
    var url = String(Qt.resolvedUrl(name))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    // Qt percent-encodes the URL, so a home directory containing a space would
    // arrive as %20 and the command would not be found.
    return decodeURIComponent(url)
  }

  // ---------------------------------------------------------------- config

  // This plugin's own entry in shell.json. Re-evaluates whenever the shell
  // reloads its config, so edits take effect without restarting anything.
  readonly property var settings: shell && shell.shellConfig ? findSettings(shell.shellConfig) : ({})

  // Precedence deliberately matches shell.updateEntryInline, which is what both
  // the panel and this service write through: it targets the bar layout entry
  // when the widget is on the bar and only falls back to `plugins[]`. Reading in
  // the other order would leave writes going to one place and reads coming from
  // another.
  function findSettings(config) {
    var layout = config && config.bar ? config.bar.layout : null
    if (layout) {
      var regions = ["left", "center", "right"]
      for (var i = 0; i < regions.length; i++) {
        var inBar = findInList(layout[regions[i]])
        if (inBar) return inBar
      }
    }

    var inPlugins = findInList(config ? config.plugins : null)
    return inPlugins ? inPlugins : ({})
  }

  function findInList(entries) {
    if (!Array.isArray(entries)) return null
    for (var i = 0; i < entries.length; i++)
      if (entries[i] && String(entries[i].id) === pluginId) return entries[i]
    return null
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function numberSetting(name) {
    var value = settings ? settings[name] : undefined
    if (value === undefined || value === null || value === "") return NaN
    var parsed = parseFloat(String(value))
    return isNaN(parsed) ? NaN : parsed
  }

  // lightTheme/darkTheme are the names this plugin used before the slots were
  // reframed as day/night. Read as fallbacks so an existing config keeps working.
  readonly property string dayTheme: String(setting("dayTheme", setting("lightTheme", "")))
  readonly property string nightTheme: String(setting("nightTheme", setting("darkTheme", "")))

  // What the user is asking for: "auto" follows a schedule, "day" and "night"
  // pin one slot, "off" parks the plugin without unloading it.
  readonly property string configMode: {
    var value = String(setting("mode", "auto")).toLowerCase()
    // Earlier versions put the schedule kind in `mode`, and named the pinned
    // modes after colours.
    if (value === "sun" || value === "fixed") return "auto"
    if (value === "light") return "day"
    if (value === "dark") return "night"
    if (value === "day" || value === "night" || value === "off") return value
    return "auto"
  }

  // Which schedule "auto" follows.
  readonly property string configAutoMode: {
    var value = String(setting("autoMode", "")).toLowerCase()
    if (value === "sun" || value === "fixed" || value === "sensor") return value
    if (String(setting("mode", "")).toLowerCase() === "fixed") return "fixed"
    return "sun"
  }

  // "official" is the visible horizon. "civil" is the more useful setting for
  // most people: it turns over about half an hour after sunset, which is much
  // closer to when a room actually feels dark.
  readonly property var twilight: setting("twilight", "official")

  // Minutes relative to each event, negative meaning earlier. For nudging one
  // side only; `twilight` is the better knob for shifting both.
  readonly property int sunriseOffsetMinutes: Math.round(numberSetting("sunriseOffsetMinutes") || 0)
  readonly property int sunsetOffsetMinutes: Math.round(numberSetting("sunsetOffsetMinutes") || 0)

  readonly property var fixedTimes: setting("fixed", ({}))
  readonly property string fixedDay: String((fixedTimes && (fixedTimes.day || fixedTimes.light)) || "07:00")
  readonly property string fixedNight: String((fixedTimes && (fixedTimes.night || fixedTimes.dark)) || "19:00")

  readonly property bool notifyOnChange: setting("notify", false) === true

  // ---------------------------------------------------------- night light

  readonly property var nightlightSettings: setting("nightlight", ({}))

  // "off" leaves the screen alone and lets Omarchy's toggle behave exactly as
  // it always has. "auto" follows the day. "on" holds the warm temperature
  // around the clock. Deliberately separate from the theme's own mode: warming
  // the screen after dark and pinning a theme are different wishes.
  readonly property string nightlightMode: {
    var value = String(nightlightSettings ? (nightlightSettings.mode || "") : "").toLowerCase()
    if (value === "auto" || value === "on" || value === "off") return value
    // Older configs carried a plain on/off flag.
    if (nightlightSettings && nightlightSettings.enabled === true) return "auto"
    return "off"
  }

  readonly property bool nightlightEnabled: nightlightMode !== "off"

  // Whether the warming follows the same schedule the themes do, or keeps its
  // own hours. They are not always the same wish: a theme can turn at sunset
  // while the screen has no business warming until the evening proper.
  readonly property string nightlightSource: {
    var value = String(nightlightSettings ? (nightlightSettings.source || "") : "").toLowerCase()
    return value === "fixed" ? "fixed" : "schedule"
  }

  readonly property var nightlightFixed: nightlightSettings && nightlightSettings.fixed
    ? nightlightSettings.fixed : ({})
  readonly property string nightlightFixedDay: String(nightlightFixed.day || "07:00")
  readonly property string nightlightFixedNight: String(nightlightFixed.night || "21:00")

  function nightlightKelvin(key, fallback) {
    var value = nightlightSettings ? parseInt(nightlightSettings[key], 10) : NaN
    if (isNaN(value)) return fallback
    return Math.max(1000, Math.min(20000, value))
  }

  // 6500 K is hyprsunset's neutral and 4000 K is what omarchy-toggle-nightlight
  // means by "on". Matching both means our warmest looks exactly like theirs,
  // and the bar indicator — which calls anything under 6000 K enabled — agrees
  // with us without being told.
  readonly property int nightlightDay: nightlightKelvin("day", 6500)
  readonly property int nightlightNight: nightlightKelvin("night", 4000)

  // Long enough that the change is never a step you notice. Three quarters of
  // an hour puts each minute's move around fifty kelvin, which is below what
  // the eye picks up against a slowly darkening room.
  readonly property int nightlightTransitionMinutes: {
    var value = nightlightSettings ? parseInt(nightlightSettings.transitionMinutes, 10) : NaN
    return isNaN(value) || value < 1 ? 45 : Math.min(360, value)
  }

  // How far ahead of the turn the warming starts. Zero means it begins as the
  // day turns over and finishes later; raise it to be already warm by then.
  readonly property int nightlightLeadMinutes: {
    var value = nightlightSettings ? parseInt(nightlightSettings.leadMinutes, 10) : NaN
    return isNaN(value) || value < 0 ? 0 : Math.min(360, value)
  }

  // Last value we wrote, so a temperature that does not match is someone else's
  // doing — the bar toggle, the menu, or hyprctl by hand.
  property int nightlightPushed: -1
  property int nightlightActual: -1
  property bool nightlightRamping: false

  // Reaching for the night light toggle is a statement about right now, not
  // about the schedule. Turning it on in the afternoon and watching it undo
  // itself a minute later would make the toggle look broken, so the schedule
  // stands aside until the day next turns over — the same bargain the rest of
  // this plugin strikes with a manual choice.
  property real nightlightHoldUntil: 0

  // A toggle value seen once and awaiting confirmation. See reconcileNightlight.
  property int nightlightExternalCandidate: -1

  // Re-evaluated on the tick, so the panel can show the hold and see it end.
  property real nightlightHeldUntil: 0

  // When the current side began, for the cases the schedule cannot date:
  // a pinned mode and the light sensor have no transition instant to speak of.
  property real sideChangedAt: 0

  onAutoSideChanged: sideChangedAt = Date.now()

  // Smoothstep rather than a straight line: the ends taper, so the ramp does
  // not start or stop with a visible corner.
  function easeProgress(progress) {
    var p = Math.max(0, Math.min(1, progress))
    return p * p * (3 - 2 * p)
  }

  function mixKelvin(from, to, progress) {
    return Math.round(from + (to - from) * easeProgress(progress))
  }

  // The temperature the schedule calls for at an arbitrary instant. Pure, so the
  // panel can walk it across a whole day to draw the curve, and so the value on
  // screen and the value in the picture can never disagree.
  //
  // Returns -1 where the schedule has no opinion.
  function nightlightTemperatureAt(instant) {
    if (nightlightMode === "off") return -1
    if (nightlightMode === "on") return nightlightNight

    var schedule
    if (nightlightSource === "fixed") {
      schedule = Sun.fixedSchedule(new Date(instant), nightlightFixedDay, nightlightFixedNight)
    } else {
      // The sensor has no timetable, so there is no curve to place an arbitrary
      // instant on. Only the here and now is answerable.
      schedule = autoSource === "sensor" ? autoSchedule : scheduleAt(instant)
    }
    if (!schedule) return -1

    var side = String(schedule.mode)
    var since = schedule.since ? schedule.since : sideChangedAt
    var next = schedule.next ? schedule.next : 0

    var lead = nightlightLeadMinutes * 60000
    var ramp = nightlightTransitionMinutes * 60000
    var span = lead + ramp

    var settled = side === "night" ? nightlightNight : nightlightDay
    var previous = side === "night" ? nightlightDay : nightlightNight

    // Approaching the next turn with a lead configured: already moving toward
    // what that turn will bring.
    if (lead > 0 && next > 0 && next - instant <= lead && instant <= next)
      return mixKelvin(settled, previous, (lead - (next - instant)) / span)

    // Just past a turn: still arriving at this half's temperature.
    if (since > 0 && instant >= since && instant - since < ramp)
      return mixKelvin(previous, settled, (lead + (instant - since)) / span)

    return settled
  }

  // -1 means "leave the screen alone".
  function nightlightTarget() {
    var value = nightlightTemperatureAt(Date.now())
    if (value < 0) {
      nightlightRamping = false
      return -1
    }

    var settled = autoSide === "night" ? nightlightNight : nightlightDay
    nightlightRamping = nightlightMode === "auto" && Math.abs(value - settled) >= 8
    return value
  }

  // Choosing a mode in the panel is an instruction, and it outranks a hold that
  // came from the toggle. Without this the hold sat there until the day turned,
  // and every button in the section looked dead.
  onNightlightModeChanged: {
    nightlightHoldUntil = 0
    nightlightHeldUntil = 0
    Qt.callLater(releaseNightlight)
  }

  // Switching off has to hand the screen back, not walk away from it. We are
  // the reason it is warm; leaving it warm and stopping is the one outcome
  // nobody asked for.
  function releaseNightlight() {
    if (nightlightMode !== "off") {
      applyNightlight()
      return
    }

    if (nightlightPushed < 0 || nightlightActual === nightlightDay) return

    nightlightPushed = nightlightDay
    nightlightExternalCandidate = -1
    nightlightApply.command = [pluginFile("bin/before-sunset-nightlight"), String(nightlightDay)]
    nightlightApply.running = true
  }

  function applyNightlight() {
    if (nightlightHoldUntil > 0) {
      if (Date.now() < nightlightHoldUntil) {
        nightlightHeldUntil = nightlightHoldUntil
        return
      }
      nightlightHoldUntil = 0
    }

    nightlightHeldUntil = 0

    var target = nightlightTarget()
    if (target < 0) return

    // A whole ramp is only a couple of thousand kelvin; writing every few of
    // them would be pure chatter for a change nobody can see.
    if (nightlightPushed >= 0 && Math.abs(target - nightlightPushed) < 8) return

    nightlightPushed = target
    nightlightExternalCandidate = -1
    nightlightApply.command = [pluginFile("bin/before-sunset-nightlight"), String(target)]
    nightlightApply.running = true
  }

  // The bar indicator and the menu toggle both read the live temperature and
  // call anything under 6000 K "on". They only re-read when told to, so a ramp
  // they were not asked about would leave their icon lying.
  Process {
    id: nightlightApply
    onExited: Quickshell.execDetached(["omarchy-shell", "-q", "nightlight", "refresh"])
  }

  Process {
    id: nightlightProbe
    command: [root.pluginFile("bin/before-sunset-nightlight")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reading
        try {
          reading = JSON.parse(String(text || "{}"))
        } catch (e) {
          return
        }
        if (reading.temperature === null || reading.temperature === undefined) return

        root.nightlightActual = Number(reading.temperature)
        root.reconcileNightlight()
        // Keeps the hold state and the target moving at the probe's rhythm
        // rather than the minute tick's, so the panel never lags the screen.
        Qt.callLater(root.applyNightlight)
      }
    }
  }

  // Someone reaching for the night light toggle is stating a preference, and it
  // should mean the same thing here as it does there: turning it on hands us
  // the wheel, turning it off takes it back. Their toggle only knows two
  // values, so those two are the tell.
  readonly property int nightlightIdentity: 6000

  // omarchy-toggle-nightlight only ever writes these two. A ramp of ours passes
  // through hundreds of values and lands on whatever the user configured, so a
  // reading that is exactly one of these, and not what we last wrote, is the
  // toggle and nothing else. Without this test our own in-flight write reads
  // back as somebody switching the night light off, which cancels the very ramp
  // that produced it.
  readonly property int nightlightToggleOff: 6500
  readonly property int nightlightToggleOn: 4000

  function reconcileNightlight() {
    if (nightlightActual < 0) return

    // Nothing of ours on screen yet: adopt what is there as the starting point
    // rather than reading it as a decision.
    if (nightlightPushed < 0) {
      nightlightPushed = nightlightActual
      return
    }

    // A write of ours may still be settling; the value on screen is ours, just
    // not yet the one we recorded.
    if (nightlightApply.running) return

    if (Math.abs(nightlightActual - nightlightPushed) < 8) {
      nightlightExternalCandidate = -1
      return
    }

    if (nightlightActual !== nightlightToggleOff && nightlightActual !== nightlightToggleOn) {
      // Not the toggle. Something else moved it, or our own write is still
      // catching up: re-baseline and carry on rather than guess.
      nightlightExternalCandidate = -1
      nightlightPushed = nightlightActual
      return
    }

    // The value is one the toggle writes — but so is the value we are on our
    // way to, and hyprctl does not report a write the instant we make it. A
    // reading left over from just before our own change looks exactly like
    // somebody pressing the toggle, and acting on it rewrites the very setting
    // that caused it. A real press is still there on the next look; a stale
    // reading is not.
    if (nightlightExternalCandidate !== nightlightActual) {
      nightlightExternalCandidate = nightlightActual
      // Confirm straight away rather than on the next round. The wait exists to
      // outlast a stale reading, which takes a moment, not five seconds.
      nightlightConfirmTimer.restart()
      return
    }

    nightlightExternalCandidate = -1

    nightlightPushed = nightlightActual

    if (nightlightActual === nightlightToggleOff) {
      // "Off, now." Nothing to hold: not driving is the whole request.
      nightlightHoldUntil = 0
      if (nightlightMode !== "off") persist({ nightlight: nightlightConfig({ mode: "off" }) })
      return
    }

    // "Warm, now." Which is a statement about this minute, not about the
    // schedule — pressing it at noon means warm at noon. So the schedule stands
    // aside until the day next turns over, and only then takes the wheel back.
    // Without the hold the next tick would drag the screen back to whatever the
    // hour called for, and the toggle would look broken while we were in auto.
    nightlightHoldUntil = autoNext > 0 ? autoNext : Date.now() + 43200000
    if (nightlightMode === "off") persist({ nightlight: nightlightConfig({ mode: "auto" }) })
  }

  function nightlightConfig(changes) {
    var next = ({
      mode: nightlightMode,
      source: nightlightSource,
      fixed: { day: nightlightFixedDay, night: nightlightFixedNight },
      day: nightlightDay,
      night: nightlightNight,
      transitionMinutes: nightlightTransitionMinutes,
      leadMinutes: nightlightLeadMinutes
    })
    for (var change in changes) next[change] = changes[change]
    return next
  }

  function probeNightlight() {
    if (!nightlightProbe.running) nightlightProbe.running = true
  }

  // Mid-ramp the minute tick would move the temperature in fifty-kelvin steps.
  // Ten seconds makes each step small enough to be invisible.
  Timer {
    interval: 10000
    repeat: true
    running: root.nightlightEnabled && root.nightlightRamping
    onTriggered: root.applyNightlight()
  }

  // The night light toggle lives on the bar and in the menu, and pressing it
  // should register here in a moment, not on the next minute boundary. A
  // hyprctl query is cheap enough to ask this often; a minute of the panel
  // disagreeing with the screen is not.
  Timer {
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.probeNightlight()
  }

  Timer {
    id: nightlightConfirmTimer
    interval: 400
    repeat: false
    onTriggered: root.probeNightlight()
  }

  // --------------------------------------------------------- night volume

  readonly property var volumeSettings: setting("volume", ({}))

  // -1 means "leave the volume alone", which is not the same as 0: silence is a
  // legitimate target for someone who wants the machine mute after dark.
  function volumeLevel(key) {
    var value = volumeSettings ? volumeSettings[key] : undefined
    if (value === undefined || value === null || value === "") return -1

    var parsed = parseInt(value, 10)
    return isNaN(parsed) || parsed < 0 || parsed > 100 ? -1 : parsed
  }

  readonly property int nightVolume: volumeLevel("night")
  readonly property int dayVolume: volumeLevel("day")

  readonly property int volumeFadeSeconds: {
    var value = volumeSettings ? parseInt(volumeSettings.fadeSeconds, 10) : NaN
    return isNaN(value) || value < 0 ? 20 : Math.min(300, value)
  }

  // The side the clock last put us on. Kept apart from `side` so a restart, a
  // pin, or a switch between schedules cannot be mistaken for dusk falling.
  property string lastScheduledSide: ""

  // Which mode the last evaluation ran under. A start has no last evaluation,
  // and that is the whole difference between beginning a session and handing
  // control back: one must not touch the room, the other must.
  property string scheduledUnder: ""

  // Pinning a half is an instruction to hold the settings for that half, and
  // the volume and the brightness have no hours of their own to fall back on —
  // they only ever ride this schedule. So a pin stops them: nothing should move
  // on a timetable the desktop has been taken off.
  //
  // The light sensor stops them too, for a different reason. It answers whether
  // the room is dark, not when it turned, and a fade has to happen at the turn.
  // A lamp switched on is not the morning.
  function noteScheduledSide() {
    var wasUnder = scheduledUnder
    scheduledUnder = configMode

    if (configMode !== "auto" || (autoSource !== "sun" && autoSource !== "fixed")) {
      lastScheduledSide = ""
      return
    }

    if (autoSide === "") return

    // First evaluation after a start or a schedule change establishes where we
    // are; it is not a transition and must not fade anything.
    if (lastScheduledSide === "") {
      lastScheduledSide = autoSide

      // Unless control is being handed back. A machine pinned to Day all
      // evening would otherwise sit on daylight levels until tomorrow's dusk,
      // which is the schedule quietly not running for a whole night. Auto means
      // now, and the theme has always behaved that way: it repaints the moment
      // it is handed the wheel rather than waiting for the next turn.
      if (wasUnder !== "" && wasUnder !== "auto") {
        fadeVolumeFor(autoSide)
        applyBrightnessFor(autoSide)
      }
      return
    }

    if (autoSide === lastScheduledSide) return

    lastScheduledSide = autoSide
    fadeVolumeFor(autoSide)
    applyBrightnessFor(autoSide)
  }

  function fadeVolumeFor(newSide) {
    var target = newSide === "night" ? nightVolume : dayVolume
    if (target < 0) return

    // Detached rather than held in a Process: the fade outlives the call by
    // design, and the script serialises overlapping runs through its own lock.
    Quickshell.execDetached([
      pluginFile("bin/before-sunset-volume"),
      String(target),
      String(volumeFadeSeconds),
      newSide === "night" ? "down" : "up"
    ])

    if (notifyOnChange)
      notify(newSide === "night" ? "Quieting down" : "Back up", "Volume easing to " + target + "%")
  }

  // ----------------------------------------------------------- brightness

  readonly property var brightnessSettings: setting("brightness", ({}))

  // Same convention the volume uses: -1 means "leave this alone". Unlike the
  // volume there is no level that means off — a screen at zero is a screen
  // nobody can find the setting on — so the script keeps a floor under it.
  function brightnessLevel(value) {
    if (value === undefined || value === null || value === "") return -1

    var parsed = parseInt(value, 10)
    return isNaN(parsed) || parsed < 0 || parsed > 100 ? -1 : parsed
  }

  readonly property int nightBrightness: brightnessLevel(brightnessSettings ? brightnessSettings.night : undefined)
  readonly property int dayBrightness: brightnessLevel(brightnessSettings ? brightnessSettings.day : undefined)

  readonly property int brightnessFadeSeconds: {
    var value = brightnessSettings ? parseInt(brightnessSettings.fadeSeconds, 10) : NaN
    return isNaN(value) || value < 0 ? 20 : Math.min(300, value)
  }

  readonly property var brightnessOverrides: {
    var value = brightnessSettings ? brightnessSettings.displays : null
    return value && typeof value === "object" ? value : ({})
  }

  // One entry per display that answers, which is not one per monitor: two
  // Studio Displays are two entries with no connector between them, and a
  // monitor with no DDC is no entry at all. See bin/before-sunset-brightness.
  property var brightnessTargets: []
  property bool brightnessProbed: false

  readonly property bool brightnessAvailable: brightnessTargets.length > 0

  // An override that names a half wins for that half; one that does not name it
  // falls back to the pair everything else follows. Naming it as null is how a
  // display says "not me" — the same null the top pair uses for the same thing.
  function brightnessFor(id, side) {
    var own = brightnessOverrides ? brightnessOverrides[id] : null
    if (own && own.hasOwnProperty(side)) return brightnessLevel(own[side])
    return side === "night" ? nightBrightness : dayBrightness
  }

  // Every display goes in one call rather than one call each. The slide is drawn
  // in gamma, and gamma is one table for the whole session — two ramps running
  // at once would be two hands on the same dial.
  function applyBrightnessFor(newSide) {
    var command = [
      pluginFile("bin/before-sunset-brightness"),
      "--ramp",
      String(brightnessFadeSeconds),
      newSide === "night" ? "down" : "up"
    ]

    var moved = false

    for (var i = 0; i < brightnessTargets.length; i++) {
      var id = String(brightnessTargets[i].id || "")
      if (id === "") continue

      var level = brightnessFor(id, newSide)
      if (level < 0) continue

      command.push(id)
      command.push(String(level))
      moved = true
    }

    if (!moved) return

    // Detached, like the volume fade: the ramp outlives the call by design and
    // the script serialises overlapping runs through its own lock.
    Quickshell.execDetached(command)

    // No notification. This is the one thing on the schedule nobody can fail to
    // notice, and saying so in a popup would be telling someone what they are
    // looking at.
    brightnessSettle.restart()
  }

  // The panel's numbers are re-read once the ramp has finished, not while it is
  // still sliding: mid-ramp the hardware has not moved yet and the reading would
  // be the old one presented as the new.
  Timer {
    id: brightnessSettle
    interval: (root.brightnessFadeSeconds + 3) * 1000
    onTriggered: root.probeBrightness()
  }

  Process {
    id: brightnessProbeProcess
    command: [root.pluginFile("bin/before-sunset-brightness")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reading
        try {
          reading = JSON.parse(String(text || "{}"))
        } catch (e) {
          return
        }

        root.brightnessTargets = Array.isArray(reading.targets) ? reading.targets : []
        root.brightnessProbed = true
      }
    }
  }

  function probeBrightness() {
    if (!brightnessProbeProcess.running) brightnessProbeProcess.running = true
  }

  // A display arriving or leaving changes the list, and nobody should have to
  // reopen the panel for it to notice.
  Connections {
    target: Quickshell
    function onScreensChanged() { Qt.callLater(root.probeBrightness) }
  }

  // ------------------------------------------------------- light sensor

  readonly property var sensorSettings: setting("sensor", ({}))

  // Raw sensor counts, not lux: meaningless until calibrated against a
  // particular machine's sensor, so zero means "not set up yet" rather than
  // "pitch dark". See bin/before-sunset-sensor.
  readonly property real sensorThreshold: {
    var value = sensorSettings ? parseFloat(sensorSettings.threshold) : NaN
    return isNaN(value) || value <= 0 ? 0 : value
  }

  // Fraction either side of the threshold where the sensor is not allowed an
  // opinion. Without it a reading hovering on the line flips the desktop back
  // and forth all evening.
  readonly property real sensorHysteresis: {
    var value = sensorSettings ? parseFloat(sensorSettings.hysteresis) : NaN
    return isNaN(value) || value < 0 ? 0.15 : value
  }

  // How long a changed reading has to hold before it counts. A hand passing
  // over the sensor is not dusk.
  readonly property int sensorDwellSeconds: {
    var value = sensorSettings ? parseFloat(sensorSettings.dwellSeconds) : NaN
    return isNaN(value) || value < 0 ? 45 : Math.round(value)
  }

  // Empty means "average whatever is there". A machine can carry more than one
  // sensor — one per screen corner, say — and they disagree by design, so the
  // mean is the steadier signal until someone knows better than the default.
  readonly property string sensorDevice: {
    var value = sensorSettings ? sensorSettings.device : undefined
    return value === undefined || value === null ? "" : String(value)
  }

  property bool sensorAvailable: false
  property real sensorValue: 0
  property bool sensorRead: false
  property var sensorDevices: []

  // The side the sensor has committed to, and the one it is currently arguing
  // for but has not held long enough.
  property string sensorSide: ""
  property string sensorCandidate: ""
  property real sensorCandidateSince: 0

  readonly property bool sensorConfigured: sensorAvailable && sensorThreshold > 0
  readonly property bool sensorUsable: sensorConfigured && sensorSide !== ""

  function probeSensor() {
    if (!sensorProbe.running) sensorProbe.running = true
  }

  function applySensorReading() {
    if (!sensorConfigured) return

    var high = sensorThreshold * (1 + sensorHysteresis)
    var low = sensorThreshold * (1 - sensorHysteresis)
    var candidate = sensorValue >= high ? "day" : (sensorValue <= low ? "night" : "")

    // Inside the band the sensor has no opinion and whatever is running stays,
    // which is the entire point of the band.
    if (candidate === "") {
      sensorCandidate = ""
      return
    }

    // The first reading commits at once: there is nothing to flap away from
    // yet, and waiting would leave the desktop undecided for no reason.
    if (sensorSide === "") {
      sensorSide = candidate
      sensorCandidate = ""
      return
    }

    if (candidate === sensorSide) {
      sensorCandidate = ""
      return
    }

    if (candidate !== sensorCandidate) {
      sensorCandidate = candidate
      sensorCandidateSince = Date.now()
      return
    }

    if (Date.now() - sensorCandidateSince >= sensorDwellSeconds * 1000) {
      sensorSide = candidate
      sensorCandidate = ""
    }
  }

  Process {
    id: sensorProbe
    command: [root.pluginFile("bin/before-sunset-sensor")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reading
        try {
          reading = JSON.parse(String(text || "{}"))
        } catch (e) {
          return
        }

        root.sensorAvailable = reading.available === true
        root.sensorDevices = Array.isArray(reading.devices) ? reading.devices : []
        if (!root.sensorAvailable) return

        var value = null

        // A named device that is no longer there falls back to the average
        // rather than going blind: sensors can vanish across a suspend, and a
        // stale name should not take the schedule down with it.
        if (root.sensorDevice !== "") {
          for (var i = 0; i < root.sensorDevices.length; i++) {
            var device = root.sensorDevices[i]
            if (String(device.path) === root.sensorDevice || String(device.id) === root.sensorDevice) {
              value = Number(device.value)
              break
            }
          }
        }

        if (value === null && reading.value !== null) value = Number(reading.value)
        if (value === null) return

        root.sensorValue = value
        root.sensorRead = true
        root.applySensorReading()
      }
    }
  }

  // Faster than the minute tick the schedule runs on: light changes on a scale
  // of seconds, and the dwell timer is what stops that becoming twitchy.
  Timer {
    interval: 10000
    repeat: true
    running: root.configMode === "auto" && root.configAutoMode === "sensor"
    triggeredOnStart: true
    onTriggered: root.probeSensor()
  }

  onSensorSideChanged: Qt.callLater(evaluate)

  // ------------------------------------------------------------- location

  property var storedLocation: ({ name: "", latitude: null, longitude: null })

  readonly property real configuredLatitude: numberSetting("latitude")
  readonly property real configuredLongitude: numberSetting("longitude")
  readonly property bool hasConfiguredCoordinates: !isNaN(configuredLatitude) && !isNaN(configuredLongitude)

  readonly property real latitude: hasConfiguredCoordinates ? configuredLatitude
    : (storedLocation && storedLocation.latitude !== null ? storedLocation.latitude : NaN)
  readonly property real longitude: hasConfiguredCoordinates ? configuredLongitude
    : (storedLocation && storedLocation.longitude !== null ? storedLocation.longitude : NaN)
  readonly property bool hasLocation: !isNaN(latitude) && !isNaN(longitude)
  readonly property string locationName: hasConfiguredCoordinates
    ? String(setting("locationName", ""))
    : String(storedLocation && storedLocation.name ? storedLocation.name : "")

  // ----------------------------------------------------------------- state

  // Theme slug currently on screen, as recorded by omarchy-theme-set.
  property string currentTheme: ""
  // Slug this service asked for and has not yet seen land. Distinguishes our
  // own switch from one the user made by hand.
  property string pendingTheme: ""
  property string queuedTheme: ""
  // A theme just adopted into a slot, held until the config write comes back
  // round. Without it a timer tick landing in that gap would read the old slot
  // value and switch the user's pick straight back out.
  property string adopting: ""

  property var schedule: null
  // "sun", "fixed", "pinned", or "" when there is nothing to follow at all.
  property string scheduleSource: ""
  // "day" or "night" — the half of the day in force, never a colour.
  readonly property string side: schedule ? String(schedule.mode) : ""
  readonly property real nextTransition: schedule && schedule.next ? schedule.next : 0

  // Today's events, for display. Computed whenever a location is known, so the
  // panel can show them even while running on fixed times.
  property real todaySunrise: 0
  property real todaySunset: 0

  // The far edge of twilight, where the sun is 18 degrees down and the sky is
  // finally out of light. Together with the effective boundary these bracket
  // the span the Boundary control can move the turn across — which is what the
  // schedule bar shades, so the choice is visible before it is made.
  //
  // Zero where there is none: inside the polar circles, and at these latitudes
  // around midsummer, astronomical twilight simply does not end.
  property real astronomicalDawn: 0
  property real astronomicalDusk: 0

  property bool started: false

  // Every installed theme with the half of the day it reads as. Only needed to
  // seed empty slots and to badge them in the panel.
  property var themes: []

  readonly property bool configured: dayTheme !== "" && nightTheme !== ""
  readonly property bool running: configured && configMode !== "off" && scheduleSource !== ""
  readonly property string scheduledTheme: side === "day" ? dayTheme : (side === "night" ? nightTheme : "")
  readonly property string activeSlot: side === "day" ? "dayTheme" : (side === "night" ? "nightTheme" : "")

  // Mirrors the slugging omarchy-theme-set does, so a display name in the
  // config ("Tokyo Night") compares equal to what lands in theme.name.
  function canonical(name) {
    return String(name || "").replace(/<[^>]+>/g, "").trim().toLowerCase().replace(/\s+/g, "-")
  }

  function themeMode(slug) {
    var key = canonical(slug)
    for (var i = 0; i < themes.length; i++)
      if (String(themes[i].slug) === key) return String(themes[i].mode)
    return ""
  }

  // ------------------------------------------------------------- scheduling

  // What the schedule says, always — even while the theme is pinned to one half
  // or switched off entirely. Pinning the theme is a statement about the theme;
  // it should not decide whether the screen warms up after dark or whether the
  // volume comes down at night. Those follow the day itself.
  property var autoSchedule: null
  property string autoSource: ""

  readonly property string autoSide: autoSchedule ? String(autoSchedule.mode) : ""
  readonly property real autoNext: autoSchedule && autoSchedule.next ? autoSchedule.next : 0
  readonly property real autoSince: autoSchedule && autoSchedule.since ? autoSchedule.since : 0

  // The clock-driven schedule for any instant, which is what lets the panel draw
  // a whole day of it. Pure: no properties written, nothing cached.
  function scheduleAt(instant) {
    var when = new Date(instant)

    if (configAutoMode !== "fixed" && hasLocation) {
      var sun = Sun.sunSchedule(when, latitude, longitude, {
        twilight: twilight,
        sunriseOffsetMinutes: sunriseOffsetMinutes,
        sunsetOffsetMinutes: sunsetOffsetMinutes
      })
      if (sun) return sun
    }

    return Sun.fixedSchedule(when, fixedDay, fixedNight)
  }

  function computeAutoSchedule() {
    var now = new Date()

    if (configAutoMode === "sensor" && sensorUsable) {
      autoSource = "sensor"
      return { mode: sensorSide, since: null, next: null }
    }

    // Sensor mode asked for but not usable — no sensor, or no threshold set
    // yet. Fall through rather than freeze: an unconfigured preference should
    // not take the desktop down with it.
    if (configAutoMode !== "fixed" && hasLocation) {
      var sun = Sun.sunSchedule(now, latitude, longitude, {
        twilight: twilight,
        sunriseOffsetMinutes: sunriseOffsetMinutes,
        sunsetOffsetMinutes: sunsetOffsetMinutes
      })
      if (sun) {
        autoSource = "sun"
        return sun
      }
      // Inside the polar circles there are stretches with no sunrise or sunset
      // at all. Fall through to the clock so the desktop keeps some rhythm
      // instead of freezing on one theme for weeks.
    }

    var fixed = Sun.fixedSchedule(now, fixedDay, fixedNight)
    autoSource = fixed ? "fixed" : ""
    return fixed
  }

  // What the theme follows, which is the schedule unless the user has pinned a
  // half or turned the plugin off.
  function computeSchedule() {
    if (configMode === "off") {
      scheduleSource = ""
      return null
    }

    if (configMode === "day" || configMode === "night") {
      scheduleSource = "pinned"
      return { mode: configMode, since: null, next: null }
    }

    scheduleSource = autoSource
    return autoSchedule
  }

  function refreshSunTimes() {
    if (!hasLocation) {
      todaySunrise = 0
      todaySunset = 0
      return
    }

    var now = new Date()
    var zenith = Sun.zenithFor(twilight)
    var up = Sun.sunrise(now, latitude, longitude, zenith)
    var down = Sun.sunset(now, latitude, longitude, zenith)

    todaySunrise = up ? up.getTime() + (sunriseOffsetMinutes * 60000) : 0
    todaySunset = down ? down.getTime() + (sunsetOffsetMinutes * 60000) : 0

    var deep = Sun.zenithFor("astronomical")
    var dawn = Sun.sunrise(now, latitude, longitude, deep)
    var dusk = Sun.sunset(now, latitude, longitude, deep)

    astronomicalDawn = dawn ? dawn.getTime() : 0
    astronomicalDusk = dusk ? dusk.getTime() : 0
  }

  function evaluate() {
    refreshSunTimes()
    autoSchedule = computeAutoSchedule()
    schedule = computeSchedule()
    if (!schedule) {
      lastScheduledSide = ""
      scheduledUnder = configMode
      return
    }

    noteScheduledSide()
    probeNightlight()
    applyNightlight()

    // theme.name has not been read yet; acting now would fight whatever is on
    // screen without knowing what that is.
    if (currentTheme === "") return

    if (!configured) {
      seedSlots()
      return
    }

    var desired = canonical(scheduledTheme)

    // An adoption is in flight: the slot on screen is the one the user just
    // chose, the config simply has not caught up yet.
    if (adopting !== "") {
      if (desired === adopting) adopting = ""
      else if (currentTheme === adopting) return
    }

    if (!started) {
      started = true
      // Nothing to correct if the theme on screen is already the scheduled one;
      // and if it is not, adopting it would be wrong, because a theme that
      // outlived the last session was chosen under whatever slot was in force
      // then. Applying the schedule is the honest move.
    }

    if (desired === "" || currentTheme === desired) return

    applyTheme(scheduledTheme)
  }

  // Fill empty slots from what is already on screen: the running theme takes
  // the slot matching its own light/dark reading, and the other slot gets a
  // stock counterpart. The point is that the plugin works the moment it is
  // installed without changing the desktop out from under anyone.
  readonly property var preferredDark: ["tokyo-night", "catppuccin", "nord", "gruvbox", "matte-black"]
  readonly property var preferredLight: ["catppuccin-latte", "flexoki-light", "white", "rose-pine"]

  function firstAvailable(preferred, wantedMode, exclude) {
    var i
    for (i = 0; i < preferred.length; i++)
      if (themeMode(preferred[i]) === wantedMode && preferred[i] !== exclude) return preferred[i]
    for (i = 0; i < themes.length; i++) {
      var slug = String(themes[i].slug)
      if (String(themes[i].mode) === wantedMode && slug !== exclude) return slug
    }
    return ""
  }

  function seedSlots() {
    if (configured || currentTheme === "" || themes.length === 0) return

    var mode = themeMode(currentTheme)
    if (mode !== "light" && mode !== "dark") mode = "dark"

    var changes = ({})
    var mine = mode === "light" ? "dayTheme" : "nightTheme"
    var other = mine === "dayTheme" ? "nightTheme" : "dayTheme"

    if (String(setting(mine, setting(mine === "dayTheme" ? "lightTheme" : "darkTheme", ""))) === "")
      changes[mine] = currentTheme

    if (String(setting(other, setting(other === "dayTheme" ? "lightTheme" : "darkTheme", ""))) === "") {
      var counterpart = mode === "light"
        ? firstAvailable(preferredDark, "dark", currentTheme)
        : firstAvailable(preferredLight, "light", currentTheme)
      if (counterpart !== "") changes[other] = counterpart
    }

    if (Object.keys(changes).length > 0) persist(changes)
  }

  // ------------------------------------------------------------- switching

  function persist(changes) {
    if (!shell || typeof shell.updateEntryInline !== "function") {
      console.warn("before-sunset: no shell to persist through")
      return
    }

    var base = settings || ({})
    var entry = ({ id: pluginId })
    for (var key in base) if (key !== "id") entry[key] = base[key]
    for (var change in changes) entry[change] = changes[change]

    shell.updateEntryInline(pluginId, entry)
  }

  function applyTheme(name) {
    var slug = canonical(name)
    if (slug === "") return

    // omarchy-theme-set serialises itself with a lock, but queueing here keeps
    // a second switch from piling up behind a slow retint.
    if (themeProcess.running) {
      queuedTheme = slug
      return
    }

    pendingTheme = slug
    themeProcess.command = [pluginFile("bin/before-sunset-apply"), slug, rememberedBackground(slug)]
    themeProcess.running = true

    if (notifyOnChange) notify(side === "day" ? "Day theme" : "Night theme", slug)
  }

  function notify(title, body) {
    notifyProcess.command = ["omarchy-notification-send", title, body, "-t", "2000"]
    notifyProcess.running = true
  }

  // A theme changed by anything other than this service — the menu, the theme
  // switcher, a keybinding, the CLI — is a statement about the slot in force:
  // "this is what I want at this time of day". Record it there instead of
  // fighting it or letting it evaporate at the next transition.
  function adopt(slug) {
    if (configMode === "off") return
    if (activeSlot === "") return
    if (!configured) return

    var currentSlotValue = canonical(activeSlot === "dayTheme" ? dayTheme : nightTheme)
    if (currentSlotValue === slug) return

    adopting = slug
    var changes = ({})
    changes[activeSlot] = slug
    persist(changes)

    if (notifyOnChange)
      notify(activeSlot === "dayTheme" ? "Day theme set" : "Night theme set", slug)
  }

  // Pinning is the honest way to override a schedule: it is visible in the
  // panel and it stays until changed, rather than silently expiring at a
  // transition the user cannot see coming.
  function pin(target) {
    var wanted = String(target).toLowerCase()
    if (wanted !== "day" && wanted !== "night" && wanted !== "auto" && wanted !== "off")
      return "unknown mode: " + target

    persist({ mode: wanted })
    return wanted
  }

  function toggle() {
    if (!configured) return "not configured"
    // From the schedule, pin the other half; from a pin, hand control back.
    if (configMode === "auto") return pin(side === "day" ? "night" : "day")
    return pin("auto")
  }

  // The panel's two other button groups, said in words. An empty mode changes
  // nothing and reports the one in force, which is the honest answer to being
  // asked for a mode and handed none.
  function chooseSchedule(wanted) {
    var mode = String(wanted || "").toLowerCase()
    if (mode === "") return configAutoMode
    if (mode !== "sun" && mode !== "fixed" && mode !== "sensor")
      return "unknown schedule: " + wanted

    persist({ autoMode: mode })
    return mode
  }

  // "always" is the word on the button; "on" is the word in the file. Both are
  // accepted rather than making anyone learn which is which.
  function chooseNightlight(wanted) {
    var mode = String(wanted || "").toLowerCase()
    if (mode === "") return nightlightMode
    if (mode === "always") mode = "on"
    if (mode !== "off" && mode !== "auto" && mode !== "on")
      return "unknown night light mode: " + wanted

    persist({ nightlight: nightlightConfig({ mode: mode }) })
    return mode
  }

  // ------------------------------------------------------- background memory

  property var backgroundMemory: ({})
  property var transparencyMemory: ({})

  // False when the current wallpaper's format has no decoder in this Qt build.
  // The file is still on disk and every ImageMagick-based tool reads it fine;
  // it simply never reaches the screen.
  property bool wallpaperRenderable: true

  // Takes the maps explicitly so a caller can persist a value before publishing
  // it. The panel resolves a slot's wallpaper by reading this file and refreshes
  // the instant the property changes: assign first and it reads the value that
  // is being replaced.
  function saveMemoryAs(backgrounds, transparency) {
    memoryFile.setText(JSON.stringify({
      version: 1,
      backgrounds: backgrounds,
      transparency: transparency
    }, null, 2) + "\n")
  }

  function rememberedBackground(slug) {
    var value = backgroundMemory ? backgroundMemory[canonical(slug)] : undefined
    return value === undefined || value === null ? "" : String(value)
  }

  function rememberBackground(slug, filename) {
    var key = canonical(slug)
    if (key === "" || filename === "") return
    if (backgroundMemory && backgroundMemory[key] === filename) return

    var next = ({})
    for (var k in backgroundMemory) next[k] = backgroundMemory[k]
    next[key] = filename
    saveMemoryAs(next, transparencyMemory)
    backgroundMemory = next
  }

  // null when the theme has no stored preference, so the current bar setting
  // stands rather than being overwritten by a default nobody chose.
  function rememberedTransparency(slug) {
    var value = transparencyMemory ? transparencyMemory[canonical(slug)] : undefined
    return value === undefined || value === null ? null : value === true
  }

  function rememberTransparency(slug, value) {
    var key = canonical(slug)
    if (key === "") return
    if (transparencyMemory && transparencyMemory[key] === value) return

    var next = ({})
    for (var k in transparencyMemory) next[k] = transparencyMemory[k]
    next[key] = value === true
    saveMemoryAs(backgroundMemory, next)
    transparencyMemory = next
  }

  // A background chosen for a slot: always remembered, and applied right away
  // only when that slot is the one on screen. Applying the night wallpaper in
  // the middle of the afternoon would be exactly wrong.
  function setBackgroundFor(slug, path) {
    var file = String(path || "").split("/").pop()
    if (file === "") return

    rememberBackground(slug, file)

    if (canonical(slug) === currentTheme) {
      backgroundApply.command = ["omarchy-theme-bg-set", String(path)]
      backgroundApply.running = true
    }
  }

  Process {
    id: backgroundApply
    onExited: Qt.callLater(root.probeBackground)
  }

  Process {
    id: backgroundProbe
    onExited: if (root.backgroundProbePending) Qt.callLater(root.probeBackground)
    command: [root.pluginFile("bin/before-sunset-bg-state")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var state
        try {
          state = JSON.parse(String(text || "{}"))
        } catch (e) {
          return
        }
        if (!state || !state.file) return

        root.wallpaperRenderable = state.renderable === true
        root.rememberBackground(root.currentTheme, String(state.file))
        Qt.callLater(root.applyBarTransparency)
      }
    }
  }

  // ------------------------------------------------- bar transparency

  property bool settingBarTransparency: false
  // Whether the bar's transparency has been observed once this session. Until
  // it has, the value in shell.json is just whatever was left there — quite
  // possibly an override this plugin wrote before the last restart.
  property bool barBaselineKnown: false

  readonly property bool barTransparent: shell && shell.shellConfig && shell.shellConfig.bar
    ? shell.shellConfig.bar.transparent === true : false

  // A transparent bar is transparent *to something*. When the wallpaper cannot
  // be painted, that something is black, while the bar's contrast helper reads
  // the image file and confidently picks the colour that contrasts with the
  // picture nobody can see. Painting the theme's own bar colours is the only
  // reading of "match what is behind the bar" that survives a wallpaper that
  // is not there. The preference is kept, not discarded: it comes back by
  // itself once the format can be decoded.
  function effectiveTransparency() {
    if (!wallpaperRenderable) return false

    var remembered = rememberedTransparency(currentTheme)
    return remembered === null ? barTransparent : remembered
  }

  function applyBarTransparency() {
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    if (currentTheme === "") return

    // Capture what the bar was set to before the guard overrides it. Without
    // this the override becomes the new normal: the preference would be gone by
    // the time the wallpaper can render again, and transparency would never
    // come back.
    if (!wallpaperRenderable && rememberedTransparency(currentTheme) === null)
      rememberTransparency(currentTheme, barTransparent)

    var want = effectiveTransparency()
    if (want === barTransparent) {
      barBaselineKnown = true
      return
    }

    barBaselineKnown = true
    settingBarTransparency = true
    shell.mutateShellConfig(function(config) {
      if (!config.bar) config.bar = ({})
      config.bar.transparent = want
    })
  }

  onBarTransparentChanged: {
    if (settingBarTransparency) {
      settingBarTransparency = false
      return
    }

    // The first value of the session is not a decision, it is a leftover: the
    // guard persists its override to shell.json, so after a restart that
    // override is sitting there looking exactly like a user preference.
    // Recording it would launder one into the other and the real preference
    // would be lost for good.
    if (!barBaselineKnown) {
      barBaselineKnown = true
      return
    }

    // Someone toggled it themselves — the menu, a keybinding, a hand edit.
    // That is a preference for the theme on screen. Not recorded while the
    // wallpaper cannot render, because the value then is ours, not theirs.
    if (currentTheme !== "" && wallpaperRenderable)
      rememberTransparency(currentTheme, barTransparent)
  }

  onWallpaperRenderableChanged: Qt.callLater(applyBarTransparency)

  // Flipping the switch on the half of the day that is running should change
  // the bar there and then. Without this the preference was only stored and
  // took effect at the next theme switch, which reads as the switch being
  // broken. Slots that are not running are stored and left alone, as before.
  onTransparencyMemoryChanged: Qt.callLater(applyBarTransparency)

  // A probe request arriving while one is in flight is the one that matters —
  // it carries the change that just happened. Dropping it leaves the remembered
  // wallpaper a step behind until something else disturbs the directory.
  property bool backgroundProbePending: false

  function probeBackground() {
    if (backgroundProbe.running) {
      backgroundProbePending = true
      return
    }

    backgroundProbePending = false
    backgroundProbe.running = true
  }

  FileView {
    id: memoryFile
    path: root.memoryPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(String(text() || "{}"))
        root.backgroundMemory = data && data.backgrounds ? data.backgrounds : ({})
        root.transparencyMemory = data && data.transparency ? data.transparency : ({})
      } catch (e) {
        root.backgroundMemory = ({})
        root.transparencyMemory = ({})
      }
    }
    onLoadFailed: {
      root.backgroundMemory = ({})
      root.transparencyMemory = ({})
    }
  }

  // The current/ directory changes whenever the theme or the background does.
  // Watching it is how a wallpaper picked in the background switcher gets
  // noticed without polling the symlink.
  FileView {
    path: root.currentDir
    watchChanges: true
    printErrors: false
    onFileChanged: Qt.callLater(root.probeBackground)
  }

  // ------------------------------------------------------------ watchers

  function onThemeNameRead(text) {
    var name = canonical(String(text || ""))
    if (name === "") return

    var previous = currentTheme
    currentTheme = name

    // FileView re-reads the file on any touch, and fires onLoaded again with
    // identical content. Nothing changed, so nobody switched anything.
    if (name === previous) {
      if (name === pendingTheme) pendingTheme = ""
      return
    }

    Qt.callLater(probeBackground)

    // Our own switch landing, not a user action.
    if (name === pendingTheme) {
      pendingTheme = ""
      return
    }

    // First read of the session establishes the baseline; evaluate() decides
    // what to do about it.
    if (previous === "") {
      Qt.callLater(evaluate)
      return
    }

    adopt(name)
  }

  FileView {
    id: themeNameFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.onThemeNameRead(text())
  }

  FileView {
    id: locationFile
    path: root.locationPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.storedLocation = root.parseLocation(text())
    onLoadFailed: root.storedLocation = ({ name: "", latitude: null, longitude: null })
  }

  // Same shape omarchy-weather-location writes: {"name", "latitude", "longitude"}.
  // A name without coordinates is valid for the weather panel but useless here,
  // and reads as no location at all.
  function parseLocation(raw) {
    var unset = ({ name: "", latitude: null, longitude: null })
    try {
      var data = JSON.parse(String(raw || ""))
      if (!data || typeof data !== "object") return unset

      var lat = parseFloat(data.latitude)
      var lon = parseFloat(data.longitude)
      var hasCoordinates = !isNaN(lat) && !isNaN(lon)

      return {
        name: typeof data.name === "string" ? data.name.trim() : "",
        latitude: hasCoordinates ? lat : null,
        longitude: hasCoordinates ? lon : null
      }
    } catch (e) {
      return unset
    }
  }

  Process {
    id: themesProcess
    command: [root.pluginFile("bin/before-sunset-themes")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "[]"))
          if (Array.isArray(parsed)) {
            root.themes = parsed
            Qt.callLater(root.evaluate)
          }
        } catch (e) {
          console.warn("before-sunset: could not parse theme list:", e)
        }
      }
    }
  }

  function loadThemes() {
    if (!themesProcess.running) themesProcess.running = true
  }

  Process {
    id: themeProcess
    // pendingTheme is deliberately left alone on success: the apply writes
    // theme.name well before it exits, but the FileView read that confirms it
    // can still land afterwards, and clearing early would make our own switch
    // look like the user's. A failed run never writes the file, so that flag
    // has to be dropped here or it would shadow a later manual pick of the
    // same theme.
    onExited: function(exitCode) {
      if (exitCode !== 0) root.pendingTheme = ""
      Qt.callLater(root.probeBackground)

      if (root.queuedTheme !== "") {
        var next = root.queuedTheme
        root.queuedTheme = ""
        // A switch that piled up while another was draining is often already
        // satisfied by the time the first one lands. Retinting the whole
        // desktop to the theme it is already showing is pure noise.
        if (next !== root.currentTheme) root.applyTheme(next)
      }
    }
  }

  Process {
    id: notifyProcess
  }

  // A minute is well under the resolution anyone perceives in a sunset, and
  // cheap: the whole evaluation is arithmetic on three days of events.
  Timer {
    interval: 60000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.evaluate()
  }

  // ------------------------------------------------------------------ wake

  // That tick is monotonic: it does not run while the machine is suspended, so
  // a laptop opened in the morning can sit on last night's theme for the
  // better part of a minute before the tick that corrects it comes round.
  // Long enough to watch the desktop turn over, which is the one thing a
  // plugin about the sun should never make anyone see.
  //
  // logind announces the resume on the system bus at the moment it happens,
  // ahead of the lock screen asking for a password. Evaluating there means the
  // right half of the day is already on screen behind the password prompt.
  Process {
    id: wakeWatch
    command: [root.pluginFile("bin/before-sunset-wake")]
    running: true
    stdout: SplitParser {
      onRead: root.wake()
    }
    // The watcher is a shortcut, not the mechanism: the minute tick still
    // corrects everything, just late. So a machine with no gdbus, or a bus
    // that went away, costs a retry every half minute and nothing else.
    onExited: wakeRetry.restart()
  }

  Timer {
    id: wakeRetry
    interval: 30000
    onTriggered: if (!wakeWatch.running) wakeWatch.running = true
  }

  // Hyprland is still coming back at the instant logind announces the resume,
  // and hyprctl can refuse a call that would have worked a second later. The
  // second pass is what makes the theme and the screen temperature stick when
  // the first one arrived too early to land.
  Timer {
    id: wakeSettle
    interval: 3000
    onTriggered: root.evaluate()
  }

  function wake() {
    // A sensor reading taken before the suspend describes a room that has had
    // all night to change, and the schedule is about to be computed from it.
    if (configMode === "auto" && configAutoMode === "sensor") probeSensor()
    probeBrightness()
    evaluate()
    wakeSettle.restart()
  }

  // Probed once at startup even when the sensor is not in use, so the panel can
  // offer the option only on machines that actually have one.
  Component.onCompleted: { loadThemes(); probeSensor(); probeBrightness() }

  onSettingsChanged: Qt.callLater(evaluate)
  onStoredLocationChanged: Qt.callLater(evaluate)

  // ------------------------------------------------------------------ IPC

  IpcHandler {
    target: "before-sunset"

    function status(): string {
      return JSON.stringify({
        configured: root.configured,
        running: root.running,
        mode: root.configMode,
        autoMode: root.configAutoMode,
        side: root.side,
        source: root.scheduleSource,
        autoSide: root.autoSide,
        autoSource: root.autoSource,
        currentTheme: root.currentTheme,
        scheduledTheme: root.canonical(root.scheduledTheme),
        dayTheme: root.canonical(root.dayTheme),
        nightTheme: root.canonical(root.nightTheme),
        fixed: { day: root.fixedDay, night: root.fixedNight },
        nextTransition: root.nextTransition ? new Date(root.nextTransition).toISOString() : null,
        sunrise: root.todaySunrise ? new Date(root.todaySunrise).toISOString() : null,
        sunset: root.todaySunset ? new Date(root.todaySunset).toISOString() : null,
        twilight: {
          dawn: root.astronomicalDawn ? new Date(root.astronomicalDawn).toISOString() : null,
          dusk: root.astronomicalDusk ? new Date(root.astronomicalDusk).toISOString() : null
        },
        location: root.hasLocation
          ? { name: root.locationName, latitude: root.latitude, longitude: root.longitude }
          : null,
        backgrounds: root.backgroundMemory,
        transparency: root.transparencyMemory,
        barTransparent: root.barTransparent,
        wallpaperRenderable: root.wallpaperRenderable,
        nightlight: {
          mode: root.nightlightMode,
          day: root.nightlightDay,
          night: root.nightlightNight,
          transitionMinutes: root.nightlightTransitionMinutes,
          leadMinutes: root.nightlightLeadMinutes,
          source: root.nightlightSource,
          fixed: { day: root.nightlightFixedDay, night: root.nightlightFixedNight },
          target: root.nightlightTarget(),
          actual: root.nightlightActual,
          ramping: root.nightlightRamping,
          heldUntil: root.nightlightHeldUntil > 0
            ? new Date(root.nightlightHeldUntil).toISOString() : null
        },
        brightness: {
          night: root.nightBrightness,
          day: root.dayBrightness,
          fadeSeconds: root.brightnessFadeSeconds,
          displays: root.brightnessTargets,
          overrides: root.brightnessOverrides
        },
        volume: {
          night: root.nightVolume,
          day: root.dayVolume,
          fadeSeconds: root.volumeFadeSeconds,
          lastScheduledSide: root.lastScheduledSide
        },
        sensor: {
          available: root.sensorAvailable,
          value: root.sensorRead ? root.sensorValue : null,
          threshold: root.sensorThreshold,
          hysteresis: root.sensorHysteresis,
          dwellSeconds: root.sensorDwellSeconds,
          side: root.sensorSide,
          pending: root.sensorCandidate,
          device: root.sensorDevice,
          devices: root.sensorDevices
        }
      })
    }

    // Pin the other half from the schedule, or hand control back from a pin.
    function toggle(): string {
      return root.toggle()
    }

    function day(): string {
      return root.pin("day")
    }

    function night(): string {
      return root.pin("night")
    }

    function auto(): string {
      return root.pin("auto")
    }

    // The way back out. day/night/auto all start it again, so nothing is lost
    // by using it — the slots, the backgrounds and the remembered transparency
    // are all still there when it comes back.
    function off(): string {
      return root.pin("off")
    }

    // Which schedule "auto" follows: sun, fixed, or the light sensor.
    function schedule(mode: string): string {
      return root.chooseSchedule(mode)
    }

    // off, auto, or always — the same three the panel offers.
    function nightlight(mode: string): string {
      return root.chooseNightlight(mode)
    }

    // The same nudge a resume gives, for anyone who would rather hang it off
    // their own hook — hypridle's after_sleep_cmd, a lid script — than rely on
    // the bus, and for seeing the wake path work without suspending a machine.
    function refresh(): string {
      root.wake()
      return root.side === "" ? "off" : root.side
    }
  }
}
