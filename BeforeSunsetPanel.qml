import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar button plus the settings popup for Before Sunset.
//
// Every setting lives in shell.json and is read back by the service, so the
// panel, the CLI and a hand-edited config can never disagree. The panel writes
// through shell.updateEntryInline and then gets out of the way: it holds no
// copy of the state it edits.
Panel {
  id: root
  moduleName: "priard.before-sunset"
  ipcTarget: "priard.before-sunset"

  // Resolved rather than bound: the service is created by the shell's service
  // loader, which may finish after the bar has already built its widgets.
  property var service: null

  function resolveService() {
    if (service) return
    if (!bar || !bar.shell || typeof bar.shell.serviceFor !== "function") return
    service = bar.shell.serviceFor(moduleName)
  }

  // ------------------------------------------------------------ state view

  readonly property string configMode: service ? String(service.configMode) : "auto"
  readonly property string autoMode: service ? String(service.configAutoMode) : "sun"
  readonly property string side: service ? String(service.side) : ""
  readonly property bool hasLocation: service ? service.hasLocation === true : false
  readonly property string locationName: service ? String(service.locationName) : ""
  readonly property real nextTransition: service ? service.nextTransition : 0
  readonly property string dayTheme: service ? String(service.dayTheme) : ""
  readonly property string nightTheme: service ? String(service.nightTheme) : ""
  readonly property string fixedDay: service ? String(service.fixedDay) : "07:00"
  readonly property string fixedNight: service ? String(service.fixedNight) : "19:00"
  readonly property bool wallpaperRenderable: service ? service.wallpaperRenderable === true : true
  readonly property real twilightDawn: service ? service.astronomicalDawn : 0
  readonly property real twilightDusk: service ? service.astronomicalDusk : 0

  readonly property string twilight: service ? String(service.twilight) : "official"
  readonly property int sunriseOffsetMinutes: service ? service.sunriseOffsetMinutes : 0
  readonly property int sunsetOffsetMinutes: service ? service.sunsetOffsetMinutes : 0

  readonly property string autoSource: service ? String(service.autoSource) : ""

  // Dimming a section means one thing and only one: nothing here is being driven
  // right now. Pinning a half is an instruction to hold that half's settings, so
  // the schedule stands down and everything riding it stands down with it. The
  // light sensor stops the fades for a different reason: it answers whether the
  // room is dark without answering when it turned, and a fade has to happen at
  // the turn.
  readonly property bool scheduleRunning: configMode === "auto"

  readonly property bool onATimetable: scheduleRunning
    && (autoSource === "sun" || autoSource === "fixed")

  readonly property string timetableNote: {
    if (configMode === "off") return "The plugin is off, so nothing moves this."
    if (!scheduleRunning)
      return "A half is pinned, so the schedule is not running and this does not move. "
        + "Switch back to Auto and it lands on the half of the day that is running, "
        + "without waiting for the next turn."
    if (onATimetable) return ""
    return "The light sensor says whether the room is dark, not when it will turn. "
      + "With no turn to move on, this stays where you leave it."
  }

  readonly property bool sensorAvailable: service ? service.sensorAvailable === true : false
  readonly property bool sensorRead: service ? service.sensorRead === true : false
  readonly property real sensorValue: service ? service.sensorValue : 0
  readonly property real sensorThreshold: service ? service.sensorThreshold : 0
  readonly property int sensorDwellSeconds: service ? service.sensorDwellSeconds : 45
  readonly property string sensorPending: service ? String(service.sensorCandidate) : ""
  readonly property var sensorDevices: service && service.sensorDevices ? service.sensorDevices : []
  readonly property string sensorDevice: service ? String(service.sensorDevice) : ""

  // Live values in the labels on purpose: two sensors both called "als" are
  // otherwise indistinguishable, and what they currently read is the only thing
  // that tells them apart.
  readonly property var sensorDeviceOptions: {
    var options = [{ value: "", label: "Average of all sensors" }]
    for (var i = 0; i < sensorDevices.length; i++) {
      var device = sensorDevices[i]
      options.push({
        value: String(device.path),
        label: String(device.name) + " (" + String(device.id) + ") — " + device.value
      })
    }
    return options
  }

  // A chosen schedule that cannot run falls back rather than freezing the
  // desktop, and the panel shows what is actually in force. The service
  // resolves it the same way.
  readonly property string effectiveAutoMode: {
    if (autoMode === "sensor" && sensorAvailable) return "sensor"
    if (autoMode !== "fixed" && hasLocation) return "sun"
    return "fixed"
  }

  readonly property var scheduleOptions: {
    var options = []
    if (hasLocation) options.push({ value: "sun", label: "Sun" })
    options.push({ value: "fixed", label: "Fixed hours" })
    if (sensorAvailable) options.push({ value: "sensor", label: "Light sensor" })
    return options
  }

  // updateEntryInline replaces the whole entry, and the sensor block is a
  // nested object, so a change to one key has to carry the others.
  function sensorConfig(changes) {
    var current = service && service.sensorSettings ? service.sensorSettings : ({})
    var next = ({
      threshold: Math.round(sensorThreshold),
      hysteresis: service ? service.sensorHysteresis : 0.15,
      dwellSeconds: sensorDwellSeconds,
      device: sensorDevice
    })
    for (var key in current) if (next[key] === undefined) next[key] = current[key]
    for (var change in changes) next[change] = changes[change]
    return next
  }

  // What the collapsed schedule heading says, so the section can stay shut
  // without hiding which schedule is actually running.
  readonly property string scheduleSummary: {
    if (!service) return ""

    if (effectiveAutoMode === "sun")
      return "Sun · " + clockOf(service.todaySunrise) + " – " + clockOf(service.todaySunset)

    if (effectiveAutoMode === "fixed")
      return "Fixed · " + fixedDay + " – " + fixedNight

    if (effectiveAutoMode === "sensor")
      return sensorThreshold > 0 ? "Light sensor · above " + Math.round(sensorThreshold)
        : "Light sensor · not calibrated"

    return ""
  }

  readonly property string nightlightMode: service ? String(service.nightlightMode) : "off"
  readonly property bool nightlightEnabled: nightlightMode !== "off"
  readonly property int nightlightDay: service ? service.nightlightDay : 6500
  readonly property int nightlightNight: service ? service.nightlightNight : 4000
  readonly property int nightlightTransitionMinutes: service ? service.nightlightTransitionMinutes : 45
  readonly property int nightlightLeadMinutes: service ? service.nightlightLeadMinutes : 0
  readonly property int nightlightActual: service ? service.nightlightActual : -1
  readonly property string nightlightSource: service ? String(service.nightlightSource) : "schedule"
  readonly property string nightlightFixedDay: service ? String(service.nightlightFixedDay) : "07:00"
  readonly property string nightlightFixedNight: service ? String(service.nightlightFixedNight) : "21:00"

  function setNightlightTime(which, text) {
    var value = String(text || "").trim()
    if (!/^([0-9]{1,2}):([0-9]{2})$/.test(value)) return false

    var parts = value.split(":")
    if (parseInt(parts[0], 10) > 23 || parseInt(parts[1], 10) > 59) return false

    persist({ nightlight: nightlightConfig({ fixed: {
      day: which === "day" ? value : nightlightFixedDay,
      night: which === "night" ? value : nightlightFixedNight
    } }) })
    return true
  }
  readonly property bool nightlightHeld: service ? service.nightlightHeldUntil > 0 : false

  function nightlightConfig(changes) {
    return service ? service.nightlightConfig(changes) : ({})
  }

  readonly property string nightlightSummary: {
    if (nightlightMode === "off") return "Off"
    if (nightlightMode === "on") return "Always " + nightlightNight + " K"
    if (nightlightSource === "fixed")
      return nightlightNight + " K from " + nightlightFixedNight
    return nightlightNight + " K over " + nightlightTransitionMinutes + " min"
  }

  // A rough guide, because kelvin means nothing to most people until they have
  // seen it on their own screen.
  readonly property string nightlightStrength: {
    var k = nightlightNight
    if (k >= 5500) return "barely there"
    if (k >= 4500) return "gentle"
    if (k >= 3800) return "comfortable"
    if (k >= 3000) return "strong"
    return "very strong"
  }

  readonly property int nightVolume: service ? service.nightVolume : -1
  readonly property int dayVolume: service ? service.dayVolume : -1
  readonly property int volumeFadeSeconds: service ? service.volumeFadeSeconds : 20

  // Same shape as sensorConfig: a nested object, so one changed key has to
  // carry the rest. null turns a side off; 0 is a real target, meaning silence.
  function volumeConfig(changes) {
    var next = ({
      night: nightVolume < 0 ? null : nightVolume,
      day: dayVolume < 0 ? null : dayVolume,
      fadeSeconds: volumeFadeSeconds
    })
    for (var change in changes) next[change] = changes[change]
    return next
  }

  readonly property int nightBrightness: service ? service.nightBrightness : -1
  readonly property int dayBrightness: service ? service.dayBrightness : -1
  readonly property var brightnessTargets: service && service.brightnessTargets ? service.brightnessTargets : []
  readonly property var brightnessOverrides: service && service.brightnessOverrides ? service.brightnessOverrides : ({})
  readonly property int brightnessFadeSeconds: service ? service.brightnessFadeSeconds : 20
  readonly property bool brightnessAvailable: service ? service.brightnessAvailable === true : false

  function brightnessLevelOf(value) {
    if (value === undefined || value === null || value === "") return -1
    var parsed = parseInt(value, 10)
    return isNaN(parsed) || parsed < 0 || parsed > 100 ? -1 : parsed
  }

  function brightnessConfig(changes) {
    var next = ({
      night: nightBrightness < 0 ? null : nightBrightness,
      day: dayBrightness < 0 ? null : dayBrightness,
      fadeSeconds: brightnessFadeSeconds,
      displays: brightnessOverrides
    })
    for (var change in changes) next[change] = changes[change]
    return next
  }

  // Overrides are rewritten whole, and a display that is not on screen keeps
  // its entry: the list below is what answered this minute, the file is every
  // display that ever did. Unplugging a monitor should not forget its numbers.
  function brightnessDisplays(id, changes) {
    var next = ({})
    for (var key in brightnessOverrides) next[key] = brightnessOverrides[key]

    if (changes === null) {
      delete next[id]
      return next
    }

    var own = ({})
    if (next[id]) for (var field in next[id]) own[field] = next[id][field]
    for (var change in changes) own[change] = changes[change]
    next[id] = own
    return next
  }

  function brightnessOverrideFor(id) {
    return brightnessOverrides && brightnessOverrides[id] ? brightnessOverrides[id] : null
  }

  readonly property string brightnessSummary: {
    if (!brightnessAvailable) return "No display answers"
    if (nightBrightness < 0 && dayBrightness < 0) return "Off"
    if (nightBrightness >= 0 && dayBrightness >= 0) return "Night " + nightBrightness + "% · day " + dayBrightness + "%"
    if (nightBrightness >= 0) return "Night · " + nightBrightness + "%"
    return "Day · " + dayBrightness + "%"
  }

  // Which level is worth a line: the one in force now if it is set, and the one
  // that is coming if it is not. Naming the half it belongs to matters once both
  // can be set — "40%" alone is unreadable at four in the afternoon.
  function levelNote(nightLevel, dayLevel) {
    var atNight = side === "night"

    var here = atNight ? nightLevel : dayLevel
    if (here >= 0) return here + (atNight ? "% at night" : "% at day")

    var coming = atNight ? dayLevel : nightLevel
    if (coming >= 0) return coming + (atNight ? "% at day" : "% at night")

    return ""
  }

  readonly property string brightnessNote: levelNote(nightBrightness, dayBrightness)
  readonly property string volumeNote: levelNote(nightVolume, dayVolume)

  readonly property string volumeSummary: {
    if (nightVolume < 0 && dayVolume < 0) return "Off"
    if (nightVolume >= 0 && dayVolume >= 0) return "Night " + nightVolume + "% · day " + dayVolume + "%"
    if (nightVolume >= 0) return "Night · " + nightVolume + "%"
    return "Day · " + dayVolume + "%"
  }

  readonly property string sensorExplanation: {
    if (!sensorRead) return "Waiting for the first reading."
    if (sensorThreshold <= 0)
      return "No threshold set, so the sun or fixed hours are running instead. "
        + "Cover the sensor until it reads dark, then press Set from now."
    if (sensorPending !== "")
      return "Reading suggests " + sensorPending + "; holding until it stays there."
    var side = service ? String(service.sensorSide) : ""
    if (side === "") return "Undecided — the reading sits inside the neutral band."
    return "Above " + Math.round(sensorThreshold) + " is day, below is night. Currently " + side + "."
  }

  // Redrawn every half minute while the panel is open: the timeline's "now"
  // marker is the only thing here that moves on its own.
  property real nowMs: 0

  // Weather Icons' clear-day and clear-night, the same pair the Omarchy weather
  // widget already renders, so the bar font is known to cover them. Written as
  // escapes rather than literal glyphs: private-use characters do not survive
  // every editor and transport, and one that gets eaten leaves a blank button
  // with nothing to indicate what went wrong.
  readonly property string sunGlyph: "\ue30d"
  readonly property string moonGlyph: "\ue32b"
  readonly property string barIcon: side === "day" ? sunGlyph : moonGlyph

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string face: bar ? bar.fontFamily : Style.font.family

  function clockOf(instant) {
    return instant ? Qt.formatDateTime(new Date(instant), "HH:mm") : ""
  }

  function canonical(name) {
    return String(name || "").replace(/<[^>]+>/g, "").trim().toLowerCase().replace(/\s+/g, "-")
  }

  function displayName(slug) {
    var words = String(slug || "").split("-")
    for (var i = 0; i < words.length; i++)
      words[i] = words[i].charAt(0).toUpperCase() + words[i].substring(1)
    return words.join(" ")
  }

  readonly property string sunLine: {
    if (!service || !hasLocation) return ""
    var rise = clockOf(service.todaySunrise)
    var set = clockOf(service.todaySunset)
    if (rise === "" || set === "") return locationName + " — no sunrise or sunset today"
    return (locationName !== "" ? locationName + " — " : "") + "sunrise " + rise + ", sunset " + set
  }

  // Other Omarchy panels put a rotating line where a status would be redundant,
  // and under the heading is that place — as long as the fact it was carrying
  // has somewhere better to be. It does: the corner of the heading row, in a
  // pill, where it can be read at any moment rather than waited for.
  //
  // Two rules. Each phrase has to be true of what the plugin is actually doing —
  // it really does run an almanac algorithm, there really are three twilights,
  // and the terminator really is the line it follows. And none of them borrows a
  // verb from the other panels that do this: Omarchy has five such lists and
  // between them they have already taken sorting, counting, watching, polishing
  // and thirty more. Sounding like the network panel with different nouns would
  // be the joke wearing someone else's coat.
  readonly property var idlePhrases: [
    "Consulting the almanac",
    "Reading the twilights",
    "Reckoning the hours",
    "Halving the day",
    "Chasing the terminator",
    "Solving for dusk",
    "Minding the horizon"
  ]

  property int phraseIndex: 0

  // The badge is the terse version, because it sits beside a title and has to
  // leave room for it. The full sentence stays on the bar widget's tooltip.
  readonly property string heroBadge: {
    if (!service) return "NO SERVICE"
    if (!service.configured) return "SETTING UP"
    if (configMode === "off") return "OFF"
    if (configMode === "day" || configMode === "night") return "PINNED · " + configMode.toUpperCase()
    if (side === "") return "AUTO"
    // An arrow rather than a separator: the time is not a property of the half
    // that is running, it is where the half is going.
    return side.toUpperCase() + (nextTransition ? " \u2192 " + clockOf(nextTransition) : "")
  }

  // Nothing rotates outside Auto: holding a half is a state worth naming once,
  // and a line that keeps changing under a pinned desktop would suggest the
  // plugin is up to something it is deliberately not up to.
  readonly property string heroLine: {
    if (!service) return ""
    if (!service.configured) return "Choosing the slots"
    if (configMode === "off") return "Standing by"
    if (configMode === "day") return "Holding the day"
    if (configMode === "night") return "Holding the night"
    return idlePhrases.length > 0 ? idlePhrases[phraseIndex % idlePhrases.length] : ""
  }

  readonly property string heroMeta: {
    if (!service) return "SERVICE NOT LOADED"
    if (!service.configured) return "SETTING UP"
    if (configMode === "off") return "OFF"
    if (configMode === "day" || configMode === "night") return "PINNED — " + configMode.toUpperCase()

    var until = nextTransition ? " UNTIL " + clockOf(nextTransition) : ""
    return side.toUpperCase() + until
  }

  // --------------------------------------------------------- persistence

  // The entry as it stands in shell.json. updateEntryInline replaces the whole
  // entry, so a write has to carry every key forward or settings this panel does
  // not surface (offsets, twilight) would be erased by a click on a mode button.
  // Read from the live config rather than trusting the injected `settings`: if
  // that injection ever failed, merging into an empty object would quietly wipe
  // the theme names instead of failing loudly.
  function currentEntry() {
    var config = bar && bar.shell ? bar.shell.shellConfig : null
    if (config) {
      var layout = config.bar ? config.bar.layout : null
      if (layout) {
        var regions = ["left", "center", "right"]
        for (var i = 0; i < regions.length; i++) {
          var inBar = entryIn(layout[regions[i]])
          if (inBar) return inBar
        }
      }
      var inPlugins = entryIn(config.plugins)
      if (inPlugins) return inPlugins
    }

    return settings ? settings : ({})
  }

  function entryIn(entries) {
    if (!Array.isArray(entries)) return null
    for (var i = 0; i < entries.length; i++)
      if (entries[i] && String(entries[i].id) === moduleName) return entries[i]
    return null
  }

  function persist(changes) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") {
      console.warn("before-sunset: no shell to persist through")
      return
    }

    var base = currentEntry()
    var entry = ({ id: moduleName })
    for (var key in base) if (key !== "id") entry[key] = base[key]
    for (var change in changes) entry[change] = changes[change]

    bar.shell.updateEntryInline(moduleName, entry)
  }

  function setFixedTime(which, text) {
    var value = String(text || "").trim()
    // Same shape Sun.js parses. Rejecting here keeps an unparseable time from
    // silently disabling the schedule.
    if (!/^([0-9]{1,2}):([0-9]{2})$/.test(value)) return false

    var parts = value.split(":")
    if (parseInt(parts[0], 10) > 23 || parseInt(parts[1], 10) > 59) return false

    persist({ fixed: {
      day: which === "day" ? value : fixedDay,
      night: which === "night" ? value : fixedNight
    } })
    return true
  }

  // ------------------------------------------------------- theme picking

  // Which slot the running theme switcher is choosing for.
  property string pickingSlot: ""

  function pluginFile(name) {
    var url = String(Qt.resolvedUrl(name))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    // Qt percent-encodes the URL, so a home directory containing a space would
    // arrive as %20 and the command would not be found.
    return decodeURIComponent(url)
  }

  Process {
    id: pickerProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var slug = String(text || "").trim().toLowerCase().replace(/\s+/g, "-")
        var slot = root.pickingSlot
        root.pickingSlot = ""
        if (slug === "" || slot === "") return

        var changes = ({})
        changes[slot] = slug
        root.persist(changes)
        // No need to apply it here: if this is the slot in force, the service
        // sees the config change and switches. If it is not, applying would be
        // exactly wrong.
      }
    }
  }

  // Reuses Omarchy's own picker rather than a dropdown of names, so choosing a
  // theme here looks and feels like choosing one anywhere else, previews
  // included. The slot's current theme is what arrives selected — not the one
  // on screen, which is a different question whenever the other slot is running.
  // Browsing applies nothing; only the committed choice is reported back.
  function pickTheme(slot, current) {
    if (pickerProcess.running) return
    pickingSlot = slot
    pickerProcess.command = [pluginFile("bin/before-sunset-pick"), canonical(current)]
    close()
    pickerProcess.running = true
  }

  // Which slot the running background picker is choosing for.
  property string pickingBackgroundFor: ""

  Process {
    id: backgroundPicker
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        var slug = root.pickingBackgroundFor
        root.pickingBackgroundFor = ""
        if (path === "" || slug === "" || !root.service) return

        root.service.setBackgroundFor(slug, path)
      }
    }
  }

  // Omarchy's own background switcher only ever offers the theme on screen, so
  // it cannot set the wallpaper for the other half of the day. Same picker,
  // pointed at the chosen slot's theme instead.
  function pickBackground(slug, currentName) {
    if (slug === "" || backgroundPicker.running) return
    pickingBackgroundFor = slug
    backgroundPicker.command = [pluginFile("bin/before-sunset-bg-pick"), canonical(slug), String(currentName || "")]
    close()
    backgroundPicker.running = true
  }

  // ----------------------------------------------------------- lifecycle

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: resolveService()
  onBarChanged: resolveService()
  // Opening the panel is the moment its contents have to be true. A signal
  // missed while it was shut — or a probe that raced — must not survive being
  // looked at.
  signal refreshRequested()

  onOpenedChanged: {
    if (!opened) {
      // A stopped animation leaves the opacity wherever it got to, and the panel
      // would open on a half-faded line.
      phraseSwap.stop()
      hero.metaOpacity = 1.0
      return
    }
    resolveService()
    if (service) service.probeBackground()
    refreshRequested()
  }

  // Only in Auto, and only with a service behind it. Pinned reads "PINNED —
  // NIGHT" and off reads "OFF"; those are answers to a question someone is
  // about to ask, and covering them with a joke every few seconds would be
  // hiding the one thing worth reading.
  Timer {
    id: phraseTimer
    interval: 2800
    repeat: true
    running: root.opened && root.service !== null && root.configMode === "auto"
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap

    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }

    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.idlePhrases.length
    }

    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // The bar can be built before the service loader has finished; a couple of
  // cheap retries beat leaving the widget permanently inert.
  Timer {
    interval: 500
    repeat: true
    running: root.service === null
    onTriggered: root.resolveService()
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  // While the panel is open the reading is on screen, so it is polled faster
  // than the service needs for switching. Only while open: no reason to read a
  // sensor nobody is looking at.
  Timer {
    interval: 3000
    repeat: true
    running: root.opened && root.sensorAvailable
    triggeredOnStart: true
    onTriggered: if (root.service) root.service.probeSensor()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    tooltipText: root.heroMeta
    onPressed: function(which) {
      // Right-click pins the other half, or hands control back to the schedule,
      // without opening anything.
      if (which === Qt.RightButton) {
        if (root.service) root.service.toggle()
        return
      }
      root.toggle()
    }
  }

  // One row per slot: the label, the theme it holds, and what that theme reads
  // as. Clicking anywhere on it opens the picker for that slot.
  function fileUrl(path) {
    // encodeURI leaves the separators alone and fixes the spaces, which a theme
    // directory is perfectly entitled to contain.
    return String(path || "") === "" ? "" : "file://" + encodeURI(String(path))
  }

  // Planckian locus, Tanner Helland's approximation. Close enough that the
  // strip below reads as the tint the screen actually takes, which is the whole
  // point of showing it rather than printing a number.
  function kelvinColor(kelvin) {
    var t = Math.max(1000, Math.min(20000, kelvin)) / 100
    var r, g, b

    if (t <= 66) {
      r = 255
      g = 99.4708025861 * Math.log(t) - 161.1195681661
    } else {
      r = 329.698727446 * Math.pow(t - 60, -0.1332047592)
      g = 288.1221695283 * Math.pow(t - 60, -0.0755148492)
    }

    if (t >= 66) b = 255
    else if (t <= 19) b = 0
    else b = 138.5177312231 * Math.log(t - 10) - 305.0447927307

    function channel(value) { return Math.max(0, Math.min(255, value)) / 255 }
    return Qt.rgba(channel(r), channel(g), channel(b), 1)
  }

  // The whole day as the screen will look through it, drawn from the same
  // function that drives hyprsunset — so the picture cannot drift from what
  // actually happens.
  component NightlightStrip: Column {
    id: strip

    readonly property int slices: 96
    readonly property real midnight: {
      var moment = new Date(root.nowMs > 0 ? root.nowMs : Date.now())
      return new Date(moment.getFullYear(), moment.getMonth(), moment.getDate()).getTime()
    }

    function sliceColor(index) {
      if (!root.service) return Qt.rgba(0, 0, 0, 0)
      var instant = midnight + ((index + 0.5) * 86400000 / slices)
      var kelvin = root.service.nightlightTemperatureAt(instant)
      return kelvin < 0 ? Qt.rgba(0, 0, 0, 0) : root.kelvinColor(kelvin)
    }

    width: parent.width
    spacing: Style.space(4)

    Item {
      width: strip.width
      height: Style.space(16)

      Row {
        anchors.fill: parent

        Repeater {
          model: strip.slices

          Rectangle {
            required property int index
            width: strip.width / strip.slices
            height: parent.height
            color: strip.sliceColor(index)
          }
        }
      }

      Rectangle {
        width: Math.max(2, Style.space(2))
        height: parent.height + Style.space(8)
        y: -Style.space(4)
        x: Math.max(0, Math.min(parent.width - width,
          parent.width * ((root.nowMs - strip.midnight) / 86400000) - width / 2))
        color: root.fg
      }
    }

    Item {
      width: strip.width
      height: midnightLabel.height

      Text {
        id: midnightLabel
        anchors.left: parent.left
        text: "00:00"
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "12:00"
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        text: "24:00"
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
      }
    }
  }

  // The day laid out end to end: night, the lit stretch, night again, with a
  // marker for now. Drawn from the effective switch points, so the boundary and
  // offset settings show their result instead of describing it.
  component DayTimeline: Column {
    id: timeline

    required property real dayStart
    required property real dayEnd

    readonly property bool valid: dayStart > 0 && dayEnd > 0 && dayEnd > dayStart

    function dayFraction(instant) {
      if (!instant) return 0
      var moment = new Date(instant)
      var midnight = new Date(moment.getFullYear(), moment.getMonth(), moment.getDate()).getTime()
      return Math.max(0, Math.min(1, (instant - midnight) / 86400000))
    }

    visible: valid
    spacing: Style.space(4)

    // Same axis and same geometry as the night light strip below it — both run
    // midnight to midnight, and two bars describing the same day should not
    // look like they came from different panels.
    //
    // The day block keeps hard edges on purpose. A theme switch is a step: at
    // the boundary everything repaints at once, and a soft edge here would
    // draw a fade that does not happen. What does happen gradually is the
    // light itself, and that is the shading either side — twilight, from the
    // boundary out to where the sky finally runs out of it.
    readonly property real nightTone: 0.10
    readonly property real dayTone: 0.42
    // Twilight stops short of the day tone so the boundary still reads as the
    // step it is, rather than being swallowed by the shading.
    readonly property real twilightPeak: 0.27

    readonly property real dawnEdge: root.twilightDawn > 0 && root.twilightDawn < timeline.dayStart
      ? root.twilightDawn : 0
    readonly property real duskEdge: root.twilightDusk > 0 && root.twilightDusk > timeline.dayEnd
      ? root.twilightDusk : 0

    function toneAt(instant) {
      if (instant >= dayStart && instant <= dayEnd) return dayTone

      if (dawnEdge > 0 && instant >= dawnEdge && instant < dayStart)
        return nightTone + (twilightPeak - nightTone) * ((instant - dawnEdge) / (dayStart - dawnEdge))

      if (duskEdge > 0 && instant > dayEnd && instant <= duskEdge)
        return nightTone + (twilightPeak - nightTone) * ((duskEdge - instant) / (duskEdge - dayEnd))

      return nightTone
    }

    readonly property int slices: 96
    readonly property real midnight: {
      var moment = new Date(root.nowMs > 0 ? root.nowMs : Date.now())
      return new Date(moment.getFullYear(), moment.getMonth(), moment.getDate()).getTime()
    }

    Item {
      width: timeline.width
      height: Style.space(16)

      Row {
        anchors.fill: parent

        Repeater {
          model: timeline.slices

          Rectangle {
            required property int index
            width: timeline.width / timeline.slices
            height: parent.height
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b,
              timeline.toneAt(timeline.midnight + ((index + 0.5) * 86400000 / timeline.slices)))
          }
        }
      }

      Rectangle {
        width: Math.max(2, Style.space(2))
        height: parent.height + Style.space(8)
        y: -Style.space(4)
        x: Math.max(0, Math.min(parent.width - width,
          parent.width * timeline.dayFraction(root.nowMs) - width / 2))
        color: root.fg
      }
    }

    Item {
      width: timeline.width
      height: startLabel.height

      Text {
        id: startLabel
        anchors.left: parent.left
        text: root.sunGlyph + "  " + root.clockOf(timeline.dayStart)
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        text: root.clockOf(timeline.dayEnd) + "  " + root.moonGlyph
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
      }
    }
  }

  // A clickable picture with a caption underneath. Themes are not required to
  // ship a preview and plenty do not, so the fallback is a centred label rather
  // than an empty frame.
  component Thumb: Column {
    id: thumb

    required property string source
    required property string caption
    required property string fallback
    property bool hovered: false

    signal activated()

    spacing: Style.space(4)

    Rectangle {
      width: thumb.width
      height: Math.round(thumb.width * 0.58)
      radius: Style.cornerRadius
      clip: true
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
      border.width: 1
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, thumb.hovered ? 0.5 : 0.18)

      Image {
        anchors.fill: parent
        source: root.fileUrl(thumb.source)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(12)
        visible: thumb.source === ""
        text: thumb.fallback
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: thumb.hovered = true
        onExited: thumb.hovered = false
        onClicked: thumb.activated()
      }
    }

    Text {
      width: thumb.width
      text: thumb.caption
      color: root.dim
      font.family: root.face
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  // One half of the day: what it looks like, and the two things you can change
  // about it. Both pictures are live — the theme's own preview and the exact
  // wallpaper this slot will restore.
  // One half of the day: what it looks like, and the three things you can change
  // about it. The transparency switch rides on the heading row because it fits
  // there for free — as its own row it cost two lines and said no more.
  component SlotCard: Column {
    id: card

    required property string label
    required property string slot
    required property string slug

    readonly property string mode: root.service ? root.service.themeMode(slug) : ""
    readonly property bool inForce: root.service && root.service.activeSlot === slot

    // No stored preference means "whatever the bar is doing now", so the switch
    // shows the truth instead of a default the user never picked.
    readonly property bool transparentBar: {
      if (!root.service) return false
      var stored = root.service.rememberedTransparency(slug)
      return stored === null ? root.service.barTransparent : stored === true
    }

    property var info: ({})
    readonly property string previewPath: info && info.preview ? String(info.preview) : ""
    readonly property string backgroundPath: info && info.background ? String(info.background) : ""
    readonly property string backgroundName: info && info.backgroundName ? String(info.backgroundName) : ""

    // A request arriving while one is in flight is the interesting one — it
    // carries the change that just happened. Dropping it leaves the card a step
    // behind for good, so it waits its turn instead.
    property bool refreshPending: false

    function refresh() {
      if (slug === "") return

      if (infoProcess.running) {
        refreshPending = true
        return
      }

      refreshPending = false
      infoProcess.command = [root.pluginFile("bin/before-sunset-slot"), slug]
      infoProcess.running = true
    }

    Process {
      id: infoProcess
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          try {
            card.info = JSON.parse(String(text || "{}"))
          } catch (e) {
            card.info = ({})
          }
        }
      }
      onExited: if (card.refreshPending) Qt.callLater(card.refresh)
    }

    // The wallpaper can change without the theme changing, so the card follows
    // the remembered state rather than only its own slug.
    Connections {
      target: root.service
      enabled: root.service !== null
      function onBackgroundMemoryChanged() { card.refresh() }
    }

    Connections {
      target: root
      function onRefreshRequested() { card.refresh() }
    }

    onSlugChanged: refresh()
    Component.onCompleted: refresh()

    width: parent.width
    spacing: Style.space(8)

    Item {
      width: parent.width
      height: Math.max(heading.height, barSwitch.height)

      Row {
        id: heading
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          text: card.label
          color: root.dim
          font.family: root.face
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          visible: card.mode !== ""
          text: "(" + card.mode + ")"
          color: root.dim
          font.family: root.face
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: card.inForce
          text: "· now"
          color: root.dim
          font.family: root.face
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        id: barLabel
        anchors.right: barSwitch.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "transparent bar"
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
      }

      ToggleSwitch {
        id: barSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: card.transparentBar
        foreground: root.fg
        interactive: card.slug !== ""
        onToggled: if (root.service) root.service.rememberTransparency(card.slug, !card.transparentBar)
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      Thumb {
        width: (parent.width - Style.space(10)) / 2
        source: card.previewPath
        caption: card.slug === "" ? "Choose a theme" : root.displayName(card.slug)
        fallback: card.slug === "" ? "Choose a theme" : root.displayName(card.slug)
        onActivated: root.pickTheme(card.slot, card.slug)
      }

      Thumb {
        width: (parent.width - Style.space(10)) / 2
        source: card.backgroundPath
        caption: card.backgroundName === "" ? "No background" : card.backgroundName
        fallback: "No background"
        onActivated: root.pickBackground(card.slug, card.backgroundName)
      }
    }
  }

  // A heading that hides its own section. Settings you touch once do not earn
  // permanent height, and a panel taller than the screen has no way to show
  // what it is hiding.
  component Disclosure: Column {
    id: disclosure

    required property string title
    property string summary: ""
    property bool expanded: false

    // Quieter, not disabled. A section can stop driving the thing it is named
    // after and still be worth reading and worth changing — the schedule while
    // a theme is pinned is exactly that, so it dims rather than greying out.
    property bool muted: false

    default property alias body: holder.children

    width: parent.width
    spacing: Style.space(12)
    opacity: disclosure.muted ? 0.55 : 1

    Item {
      width: parent.width
      height: Math.max(titleText.height, chevron.height)

      Row {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Text {
          id: titleText
          text: disclosure.title
          color: root.dim
          font.family: root.face
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          visible: !disclosure.expanded && disclosure.summary !== ""
          text: disclosure.summary
          color: root.dim
          font.family: root.face
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        // Nerd Font chevrons, covered by the bar font. Written as escapes so a
        // transport that eats private-use characters cannot leave a blank.
        text: disclosure.expanded ? "\uf078" : "\uf054"
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: disclosure.expanded = !disclosure.expanded
      }
    }

    Column {
      id: holder
      width: parent.width
      spacing: Style.space(12)
      visible: disclosure.expanded
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // fittedContentHeight clamps the card to the screen, and the content
      // holder does not scroll: without this, a short display would simply cut
      // the bottom off with no way to reach it. Interactive only when there is
      // something to reach, so a panel that fits never flicks under the cursor.
      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: Style.space(18)

          PanelHero {
            id: hero

            width: parent.width
            title: "Before Sunset"
            detail: root.heroBadge
            meta: root.heroLine
            foreground: root.fg
            fontFamily: root.face
            iconComponent: Text {
              text: root.barIcon
              color: root.fg
              font.family: root.face
              font.pixelSize: Style.font.display
            }
          }

          // What the schedule is doing to the screen and the speakers right now,
          // where you can see it without opening either section.
          Row {
            // The night light is here whenever it is on, because it keeps its own
            // hours and runs whatever the mode. The other two are only here when
            // they are actually going to move: pinned or under the light sensor
            // they stand down, and a line promising 40% at night would be
            // promising something nobody is going to do.
            visible: root.nightlightEnabled
              || (root.onATimetable && (root.brightnessNote !== "" || root.volumeNote !== ""))
            width: parent.width
            spacing: Style.space(14)

            Row {
              visible: root.nightlightEnabled
              spacing: Style.space(6)

              Rectangle {
                width: Style.space(10)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.nightlightActual > 0 ? root.kelvinColor(root.nightlightActual) : "transparent"
                border.width: 1
                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)
              }

              Text {
                text: root.nightlightHeld ? root.nightlightActual + " K held"
                  : (root.nightlightActual > 0 ? root.nightlightActual + " K" : "night light")
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              visible: root.onATimetable && root.brightnessNote !== ""
              spacing: Style.space(6)

              Text {
                // nf-md-brightness_6, and above the basic plane like the speaker
                // below it, so it is written as a code point rather than an
                // escape that would only cover half of it.
                text: String.fromCodePoint(0xf00e0)
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
              }

              Text {
                text: root.brightnessNote
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              visible: root.onATimetable && root.volumeNote !== ""
              spacing: Style.space(6)

              Text {
                // Above the basic plane, so a four-digit \u escape would take
                // only half of it and print the remainder as a digit.
                text: String.fromCodePoint(0xf0580)
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
              }

              Text {
                text: root.volumeNote
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelSeparator { foreground: root.fg }

          // ------------------------------------------------------- mode

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MODE"
              foreground: root.fg
              fontFamily: root.face
            }

            ButtonGroup {
              width: parent.width
              options: [
                { value: "day", label: "Day" },
                { value: "night", label: "Night" },
                { value: "auto", label: "Auto" }
              ]
              value: root.configMode === "off" ? "" : root.configMode
              foreground: root.fg
              fontFamily: root.face
              onChanged: function(value) { root.persist({ mode: value }) }
            }

            Text {
              visible: root.configMode === "day" || root.configMode === "night"
              width: parent.width
              text: "Pinned. The theme is not following the schedule; switch to Auto to "
                + "hand it back."
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.fg }

          // ----------------------------------------------------- slots

          // No section heading: the two cards already say DAY and NIGHT, and
          // the panel has better uses for the line.
          Column {
            width: parent.width
            spacing: Style.space(16)

            SlotCard { label: "DAY"; slot: "dayTheme"; slug: root.dayTheme }
            SlotCard { label: "NIGHT"; slot: "nightTheme"; slug: root.nightTheme }

            Text {
              visible: !root.wallpaperRenderable
              width: parent.width
              text: "This wallpaper is in a format Qt cannot decode here, so the desktop "
                + "paints black behind a transparent bar. Transparency is held off until "
                + "it can render; the preference above is kept."
              color: root.fg
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.fg; visible: scheduleSection.visible }

          // -------------------------------------------------- schedule

          Disclosure {
            id: scheduleSection

            // Off is the only mode where the schedule genuinely stops. Pinned,
            // it still runs — it just is not the thing repainting the desktop —
            // so it stays on screen and says so rather than disappearing and
            // taking its own explanation with it.
            visible: root.configMode !== "off"
            muted: !root.scheduleRunning
            title: "SCHEDULE"
            summary: root.scheduleSummary

            Text {
              visible: root.configMode === "day" || root.configMode === "night"
              width: parent.width
              text: "Pinned, so the schedule is not running: nothing here moves the "
                + "theme, the brightness or the volume until Auto takes over. The night "
                + "light keeps going, because it has hours of its own."
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            ButtonGroup {
              visible: root.hasLocation || root.sensorAvailable
              width: parent.width
              options: root.scheduleOptions
              value: root.effectiveAutoMode
              foreground: root.fg
              fontFamily: root.face
              onChanged: function(value) { root.persist({ autoMode: value }) }
            }

            Text {
              visible: !root.hasLocation
              width: parent.width
              text: "Sunrise and sunset need a location. Set one in the Weather widget, "
                + "or run:\nomarchy-weather-location --set \"City\" lat,lon"
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            // ---------------------------------------------- sun

            Column {
              visible: root.effectiveAutoMode === "sun" && root.hasLocation
              width: parent.width
              spacing: Style.space(12)

              DayTimeline {
                width: parent.width
                dayStart: root.service ? root.service.todaySunrise : 0
                dayEnd: root.service ? root.service.todaySunset : 0
              }

              Text {
                width: parent.width
                text: root.locationName
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Dropdown {
                width: parent.width
                label: "Boundary"
                options: [
                  { value: "official", label: "Horizon (sunrise/sunset)" },
                  { value: "civil", label: "Civil twilight" },
                  { value: "nautical", label: "Nautical twilight" },
                  { value: "astronomical", label: "Astronomical twilight" }
                ]
                value: root.twilight
                foreground: root.fg
                fontFamily: root.face
                onChanged: function(value) { root.persist({ twilight: value }) }
              }

              // Nudge one side without moving the other. The strip above
              // redraws as these change, so the effect is visible rather than
              // guessed at.
              Row {
                width: parent.width
                spacing: Style.space(12)

                NumberField {
                  label: "Sunrise ± min"
                  value: root.sunriseOffsetMinutes
                  from: -180
                  to: 180
                  stepSize: 5
                  foreground: root.fg
                  fontFamily: root.face
                  onModified: function(value) { root.persist({ sunriseOffsetMinutes: value }) }
                }

                NumberField {
                  label: "Sunset ± min"
                  value: root.sunsetOffsetMinutes
                  from: -180
                  to: 180
                  stepSize: 5
                  foreground: root.fg
                  fontFamily: root.face
                  onModified: function(value) { root.persist({ sunsetOffsetMinutes: value }) }
                }
              }
            }

            // -------------------------------------------- fixed hours

            Row {
              visible: root.effectiveAutoMode === "fixed"
              width: parent.width
              spacing: Style.space(14)

              Column {
                spacing: Style.space(6)

                Text {
                  text: "Day from"
                  color: root.dim
                  font.family: root.face
                  font.pixelSize: Style.font.caption
                }

                TextField {
                  width: Style.space(90)
                  text: root.fixedDay
                  foreground: root.fg
                  font.family: root.face
                  inputMask: "99:99"
                  // Reverting on a rejected value is what tells the user it was
                  // rejected; a field left holding "9:9" would look accepted.
                  onEditingFinished: if (!root.setFixedTime("day", text)) text = root.fixedDay
                }
              }

              Column {
                spacing: Style.space(6)

                Text {
                  text: "Night from"
                  color: root.dim
                  font.family: root.face
                  font.pixelSize: Style.font.caption
                }

                TextField {
                  width: Style.space(90)
                  text: root.fixedNight
                  foreground: root.fg
                  font.family: root.face
                  inputMask: "99:99"
                  onEditingFinished: if (!root.setFixedTime("night", text)) text = root.fixedNight
                }
              }
            }

            // ------------------------------------------- light sensor

            Column {
              visible: root.effectiveAutoMode === "sensor"
              width: parent.width
              spacing: Style.space(12)

              Dropdown {
                visible: root.sensorDevices.length > 1
                width: parent.width
                label: "Sensor"
                options: root.sensorDeviceOptions
                value: root.sensorDevice
                foreground: root.fg
                fontFamily: root.face
                onChanged: function(value) { root.persist({ sensor: root.sensorConfig({ device: value }) }) }
              }

              Text {
                visible: root.sensorDevices.length > 1
                width: parent.width
                text: "Sensors read differently from one another, so check the threshold "
                  + "after switching between them."
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Item {
                width: parent.width
                height: Math.max(readingLabel.height, calibrate.height)

                Text {
                  id: readingLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.sensorRead ? "Light now: " + root.sensorValue : "Reading…"
                  color: root.dim
                  font.family: root.face
                  font.pixelSize: Style.font.caption
                }

                // Readings are raw sensor counts, not lux, and differ by orders
                // of magnitude between machines. Calibrating against what the
                // sensor says right now is the only threshold that means
                // anything.
                Button {
                  id: calibrate
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Set from now"
                  bordered: true
                  enabled: root.sensorRead
                  foreground: root.fg
                  fontFamily: root.face
                  onClicked: root.persist({ sensor: root.sensorConfig({ threshold: Math.round(root.sensorValue) }) })
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(12)

                NumberField {
                  label: "Threshold"
                  value: Math.round(root.sensorThreshold)
                  from: 0
                  to: 1000000
                  stepSize: 1000
                  foreground: root.fg
                  fontFamily: root.face
                  onModified: function(value) { root.persist({ sensor: root.sensorConfig({ threshold: value }) }) }
                }

                NumberField {
                  label: "Hold for (s)"
                  value: root.sensorDwellSeconds
                  from: 0
                  to: 600
                  stepSize: 15
                  foreground: root.fg
                  fontFamily: root.face
                  onModified: function(value) { root.persist({ sensor: root.sensorConfig({ dwellSeconds: value }) }) }
                }
              }

              Text {
                width: parent.width
                text: root.sensorExplanation
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          PanelSeparator { foreground: root.fg }

          // ----------------------------------------------- night light

          Disclosure {
            title: "NIGHT LIGHT"
            summary: root.nightlightSummary

            ButtonGroup {
              width: parent.width
              options: [
                { value: "off", label: "Off" },
                { value: "auto", label: "Auto" },
                { value: "on", label: "Always" }
              ]
              value: root.nightlightMode
              foreground: root.fg
              fontFamily: root.face
              onChanged: function(value) { root.persist({ nightlight: root.nightlightConfig({ mode: value }) }) }
            }

            Text {
              width: parent.width
              text: {
                var now = root.nightlightActual > 0 ? "Screen is at " + root.nightlightActual + " K. " : ""
                if (root.nightlightHeld)
                  return now + "Held where you put it until the day next turns over."
                if (root.nightlightMode === "off")
                  return now + "Omarchy's own toggle is left to behave exactly as it always has."
                if (root.nightlightMode === "on")
                  return now + "Held warm around the clock, whatever the day is doing."
                return now + "Follows the day on its own — pinning a theme does not stop it."
              }
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            ButtonGroup {
              visible: root.nightlightMode === "auto"
              width: parent.width
              options: [
                { value: "schedule", label: "Follow the schedule" },
                { value: "fixed", label: "Own hours" }
              ]
              value: root.nightlightSource
              foreground: root.fg
              fontFamily: root.face
              onChanged: function(value) { root.persist({ nightlight: root.nightlightConfig({ source: value }) }) }
            }

            Row {
              visible: root.nightlightMode === "auto" && root.nightlightSource === "fixed"
              width: parent.width
              spacing: Style.space(14)

              Column {
                spacing: Style.space(6)

                Text {
                  text: "Neutral from"
                  color: root.dim
                  font.family: root.face
                  font.pixelSize: Style.font.caption
                }

                TextField {
                  width: Style.space(90)
                  text: root.nightlightFixedDay
                  foreground: root.fg
                  font.family: root.face
                  inputMask: "99:99"
                  onEditingFinished: if (!root.setNightlightTime("day", text)) text = root.nightlightFixedDay
                }
              }

              Column {
                spacing: Style.space(6)

                Text {
                  text: "Warm from"
                  color: root.dim
                  font.family: root.face
                  font.pixelSize: Style.font.caption
                }

                TextField {
                  width: Style.space(90)
                  text: root.nightlightFixedNight
                  foreground: root.fg
                  font.family: root.face
                  inputMask: "99:99"
                  onEditingFinished: if (!root.setNightlightTime("night", text)) text = root.nightlightFixedNight
                }
              }
            }

            NightlightStrip {
              // Its own hours give it a timetable even where the schedule has
              // none, so the sensor no longer rules the picture out.
              visible: root.nightlightMode === "auto"
                && (root.nightlightSource === "fixed" || root.autoMode !== "sensor")
              width: parent.width
            }

            Row {
              visible: root.nightlightEnabled
              width: parent.width
              spacing: Style.space(12)

              NumberField {
                label: "Night K"
                value: root.nightlightNight
                from: 1500
                to: 6500
                stepSize: 100
                foreground: root.fg
                fontFamily: root.face
                onModified: function(value) { root.persist({ nightlight: root.nightlightConfig({ night: value }) }) }
              }

              NumberField {
                label: "Day K"
                value: root.nightlightDay
                from: 3000
                to: 20000
                stepSize: 100
                foreground: root.fg
                fontFamily: root.face
                onModified: function(value) { root.persist({ nightlight: root.nightlightConfig({ day: value }) }) }
              }
            }

            Row {
              visible: root.nightlightMode === "auto"
              width: parent.width
              spacing: Style.space(12)

              NumberField {
                label: "Over (min)"
                value: root.nightlightTransitionMinutes
                from: 1
                to: 360
                stepSize: 5
                foreground: root.fg
                fontFamily: root.face
                onModified: function(value) { root.persist({ nightlight: root.nightlightConfig({ transitionMinutes: value }) }) }
              }

              NumberField {
                label: "Start early (min)"
                value: root.nightlightLeadMinutes
                from: 0
                to: 360
                stepSize: 5
                foreground: root.fg
                fontFamily: root.face
                onModified: function(value) { root.persist({ nightlight: root.nightlightConfig({ leadMinutes: value }) }) }
              }
            }

            Text {
              visible: root.nightlightEnabled
              width: parent.width
              text: root.nightlightNight + " K is " + root.nightlightStrength
                + ". 6500 K is neutral, 5000 barely shows, 4000 is comfortable for an "
                + "evening, below 3000 most people find too much. The change is spread "
                + "over the whole window, so no single minute of it is visible."
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Shares the night light with Omarchy's own toggle: switching it on there "
                + "hands the schedule the wheel, switching it off takes it back."
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.fg; visible: brightnessSection.visible }

          // ------------------------------------------------ brightness

          Disclosure {
            id: brightnessSection

            title: "BRIGHTNESS"
            summary: root.brightnessSummary
            muted: !root.onATimetable
            // Nothing is drawn on a machine where no display answers, the same
            // way the light sensor is absent rather than greyed out.
            visible: root.brightnessAvailable

            Text {
              visible: root.timetableNote !== ""
              width: parent.width
              text: root.timetableNote
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Item {
              width: parent.width
              height: Math.max(dimLabel.height, dimSwitch.height)

              Text {
                id: dimLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Dim at nightfall"
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
              }

              ToggleSwitch {
                id: dimSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.nightBrightness >= 0
                foreground: root.fg
                onToggled: root.persist({ brightness: root.brightnessConfig({ night: root.nightBrightness >= 0 ? null : 40 }) })
              }
            }

            Row {
              visible: root.nightBrightness >= 0
              width: parent.width
              spacing: Style.space(12)

              NumberField {
                label: "Night level %"
                value: Math.max(0, root.nightBrightness)
                from: 5
                to: 100
                stepSize: 5
                foreground: root.fg
                fontFamily: root.face
                onModified: function(value) { root.persist({ brightness: root.brightnessConfig({ night: value }) }) }
              }

              NumberField {
                label: "Fade (s)"
                value: root.brightnessFadeSeconds
                from: 0
                to: 300
                stepSize: 5
                foreground: root.fg
                fontFamily: root.face
                onModified: function(value) { root.persist({ brightness: root.brightnessConfig({ fadeSeconds: value }) }) }
              }
            }

            Item {
              width: parent.width
              height: Math.max(liftLabel.height, liftSwitch.height)

              Text {
                id: liftLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Brighten at daybreak"
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
              }

              ToggleSwitch {
                id: liftSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.dayBrightness >= 0
                foreground: root.fg
                onToggled: root.persist({ brightness: root.brightnessConfig({ day: root.dayBrightness >= 0 ? null : 80 }) })
              }
            }

            NumberField {
              visible: root.dayBrightness >= 0
              label: "Day level %"
              value: Math.max(0, root.dayBrightness)
              from: 5
              to: 100
              stepSize: 5
              foreground: root.fg
              fontFamily: root.face
              onModified: function(value) { root.persist({ brightness: root.brightnessConfig({ day: value }) }) }
            }

            // Folded away, because one pair of numbers is the whole setting for
            // most people and a list of displays would be the first thing they
            // had to read past to find it.
            Disclosure {
              title: "Per display"
              summary: root.brightnessTargets.length + (root.brightnessTargets.length === 1 ? " display" : " displays")

              Repeater {
                model: root.brightnessTargets

                Column {
                  id: displayRow

                  required property var modelData

                  readonly property string targetId: String(displayRow.modelData.id || "")
                  readonly property var own: root.brightnessOverrideFor(displayRow.targetId)
                  readonly property bool overridden: displayRow.own !== null
                  readonly property int ownNight: root.brightnessLevelOf(displayRow.own ? displayRow.own.night : undefined)
                  readonly property int ownDay: root.brightnessLevelOf(displayRow.own ? displayRow.own.day : undefined)

                  width: parent.width
                  spacing: Style.space(8)

                  Item {
                    width: parent.width
                    height: Math.max(displayLabel.height, displaySwitch.height)

                    Column {
                      id: displayLabel
                      anchors.left: parent.left
                      anchors.right: displaySwitch.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        width: parent.width
                        text: String(displayRow.modelData.label || "Display")
                        color: root.fg
                        font.family: root.face
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        // The live reading is what tells two identical displays
                        // apart. Apple's have no connector to name them by, so
                        // the number they are sitting at is the only handle.
                        text: (displayRow.overridden ? "Its own numbers" : "Follows the pair above")
                          + " · now " + displayRow.modelData.value + "%"
                        color: root.dim
                        font.family: root.face
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    ToggleSwitch {
                      id: displaySwitch
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      checked: displayRow.overridden
                      foreground: root.fg
                      // Taking a display off the pair starts it on the pair's
                      // own numbers, so the switch itself never changes what
                      // the screen does — only what moves it next time.
                      onToggled: root.persist({ brightness: root.brightnessConfig({
                        displays: root.brightnessDisplays(displayRow.targetId, displayRow.overridden ? null : ({
                          night: root.nightBrightness < 0 ? null : root.nightBrightness,
                          day: root.dayBrightness < 0 ? null : root.dayBrightness
                        }))
                      }) })
                    }
                  }

                  Row {
                    visible: displayRow.overridden
                    width: parent.width
                    spacing: Style.space(12)

                    NumberField {
                      label: "Night %"
                      value: Math.max(0, displayRow.ownNight)
                      from: 5
                      to: 100
                      stepSize: 5
                      foreground: root.fg
                      fontFamily: root.face
                      onModified: function(value) { root.persist({ brightness: root.brightnessConfig({
                        displays: root.brightnessDisplays(displayRow.targetId, { night: value })
                      }) }) }
                    }

                    NumberField {
                      label: "Day %"
                      value: Math.max(0, displayRow.ownDay)
                      from: 5
                      to: 100
                      stepSize: 5
                      foreground: root.fg
                      fontFamily: root.face
                      onModified: function(value) { root.persist({ brightness: root.brightnessConfig({
                        displays: root.brightnessDisplays(displayRow.targetId, { day: value })
                      }) }) }
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              text: "Only the sun and fixed hours move the brightness, and only when they "
                + "turn the day over. Night never raises it and day never lowers it, so a "
                + "screen you turned down yourself stays where you put it."
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Displays that cannot be driven are not listed. A monitor with no DDC, "
                + "or one whose firmware refuses, is left alone rather than reported broken."
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.fg }

          // ---------------------------------------------------- volume

          Disclosure {
            title: "VOLUME"
            summary: root.volumeSummary
            muted: !root.onATimetable


            Text {
              visible: root.timetableNote !== ""
              width: parent.width
              text: root.timetableNote
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Item {
              width: parent.width
              height: Math.max(nightLabel.height, nightSwitch.height)

              Text {
                id: nightLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Ease down at nightfall"
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
              }

              ToggleSwitch {
                id: nightSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.nightVolume >= 0
                foreground: root.fg
                onToggled: root.persist({ volume: root.volumeConfig({ night: root.nightVolume >= 0 ? null : 30 }) })
              }
            }

            Row {
              visible: root.nightVolume >= 0
              width: parent.width
              spacing: Style.space(12)

              NumberField {
                label: "Night level %"
                value: Math.max(0, root.nightVolume)
                from: 0
                to: 100
                stepSize: 5
                foreground: root.fg
                fontFamily: root.face
                onModified: function(value) { root.persist({ volume: root.volumeConfig({ night: value }) }) }
              }

              NumberField {
                label: "Fade (s)"
                value: root.volumeFadeSeconds
                from: 0
                to: 300
                stepSize: 5
                foreground: root.fg
                fontFamily: root.face
                onModified: function(value) { root.persist({ volume: root.volumeConfig({ fadeSeconds: value }) }) }
              }
            }

            Item {
              width: parent.width
              height: Math.max(dayLabel.height, daySwitch.height)

              Text {
                id: dayLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Ease back up at daybreak"
                color: root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
              }

              ToggleSwitch {
                id: daySwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.dayVolume >= 0
                foreground: root.fg
                onToggled: root.persist({ volume: root.volumeConfig({ day: root.dayVolume >= 0 ? null : 60 }) })
              }
            }

            NumberField {
              visible: root.dayVolume >= 0
              label: "Day level %"
              value: Math.max(0, root.dayVolume)
              from: 0
              to: 100
              stepSize: 5
              foreground: root.fg
              fontFamily: root.face
              onModified: function(value) { root.persist({ volume: root.volumeConfig({ day: value }) }) }
            }

            Text {
              width: parent.width
              text: "Only the sun and fixed hours move the volume, and only when they turn "
                + "the day over — not when you pin a half yourself. Night never raises it "
                + "and day never lowers it, so a machine you deliberately hushed stays "
                + "hushed. Reach for the volume mid-fade and the fade gives way."
              color: root.dim
              font.family: root.face
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            width: parent.width
            text: "A theme picked anywhere else lands in the half of the day that is running."
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
