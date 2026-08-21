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
Item {
  id: root

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "priard.auto-theme"
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy"
  readonly property string themeNamePath: stateDir + "/current/theme.name"
  readonly property string currentDir: stateDir + "/current"
  readonly property string backgroundLink: stateDir + "/current/background"
  // Written by omarchy-weather-location, and shared with the weather widget so
  // a location only ever has to be set once.
  readonly property string locationPath: stateDir + "/settings/weather.json"
  readonly property string memoryPath: stateDir + "/settings/auto-theme.json"

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
    if (value === "sun" || value === "fixed") return value
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

  function computeSchedule() {
    var now = new Date()

    if (configMode === "off") {
      scheduleSource = ""
      return null
    }

    // Pinned to one slot. No transitions, so nothing to wait for.
    if (configMode === "day" || configMode === "night") {
      scheduleSource = "pinned"
      return { mode: configMode, since: null, next: null }
    }

    if (configAutoMode !== "fixed" && hasLocation) {
      var sun = Sun.sunSchedule(now, latitude, longitude, {
        twilight: twilight,
        sunriseOffsetMinutes: sunriseOffsetMinutes,
        sunsetOffsetMinutes: sunsetOffsetMinutes
      })
      if (sun) {
        scheduleSource = "sun"
        return sun
      }
      // Inside the polar circles there are stretches with no sunrise or sunset
      // at all. Fall through to the clock so the desktop keeps some rhythm
      // instead of freezing on one theme for weeks.
    }

    var fixed = Sun.fixedSchedule(now, fixedDay, fixedNight)
    scheduleSource = fixed ? "fixed" : ""
    return fixed
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
  }

  function evaluate() {
    refreshSunTimes()
    schedule = computeSchedule()
    if (!schedule) return

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
      console.warn("auto-theme: no shell to persist through")
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
    themeProcess.command = [pluginFile("bin/auto-theme-apply"), slug, rememberedBackground(slug)]
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

  // ------------------------------------------------------- background memory

  property var backgroundMemory: ({})
  property var transparencyMemory: ({})

  // False when the current wallpaper's format has no decoder in this Qt build.
  // The file is still on disk and every ImageMagick-based tool reads it fine;
  // it simply never reaches the screen.
  property bool wallpaperRenderable: true

  function saveMemory() {
    memoryFile.setText(JSON.stringify({
      version: 1,
      backgrounds: backgroundMemory,
      transparency: transparencyMemory
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
    backgroundMemory = next
    saveMemory()
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
    transparencyMemory = next
    saveMemory()
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
    command: [root.pluginFile("bin/auto-theme-bg-state")]
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

  function probeBackground() {
    if (!backgroundProbe.running) backgroundProbe.running = true
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
    command: [root.pluginFile("bin/auto-theme-themes")]
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
          console.warn("auto-theme: could not parse theme list:", e)
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

  Component.onCompleted: loadThemes()

  onSettingsChanged: Qt.callLater(evaluate)
  onStoredLocationChanged: Qt.callLater(evaluate)

  // ------------------------------------------------------------------ IPC

  IpcHandler {
    target: "auto-theme"

    function status(): string {
      return JSON.stringify({
        configured: root.configured,
        running: root.running,
        mode: root.configMode,
        autoMode: root.configAutoMode,
        side: root.side,
        source: root.scheduleSource,
        currentTheme: root.currentTheme,
        scheduledTheme: root.canonical(root.scheduledTheme),
        dayTheme: root.canonical(root.dayTheme),
        nightTheme: root.canonical(root.nightTheme),
        fixed: { day: root.fixedDay, night: root.fixedNight },
        nextTransition: root.nextTransition ? new Date(root.nextTransition).toISOString() : null,
        sunrise: root.todaySunrise ? new Date(root.todaySunrise).toISOString() : null,
        sunset: root.todaySunset ? new Date(root.todaySunset).toISOString() : null,
        location: root.hasLocation
          ? { name: root.locationName, latitude: root.latitude, longitude: root.longitude }
          : null,
        backgrounds: root.backgroundMemory,
        transparency: root.transparencyMemory,
        barTransparent: root.barTransparent,
        wallpaperRenderable: root.wallpaperRenderable
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
  }
}
