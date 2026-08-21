import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar button plus the settings popup for Auto Theme.
//
// Every setting lives in shell.json and is read back by the service, so the
// panel, the CLI and a hand-edited config can never disagree. The panel writes
// through shell.updateEntryInline and then gets out of the way: it holds no
// copy of the state it edits.
Panel {
  id: root
  moduleName: "priard.auto-theme"
  ipcTarget: "priard.auto-theme"

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

  readonly property string twilight: service ? String(service.twilight) : "official"
  readonly property int sunriseOffsetMinutes: service ? service.sunriseOffsetMinutes : 0
  readonly property int sunsetOffsetMinutes: service ? service.sunsetOffsetMinutes : 0

  readonly property bool sensorAvailable: service ? service.sensorAvailable === true : false
  readonly property bool sensorRead: service ? service.sensorRead === true : false
  readonly property real sensorValue: service ? service.sensorValue : 0
  readonly property real sensorThreshold: service ? service.sensorThreshold : 0
  readonly property int sensorDwellSeconds: service ? service.sensorDwellSeconds : 45
  readonly property string sensorPending: service ? String(service.sensorCandidate) : ""

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
      dwellSeconds: sensorDwellSeconds
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
      console.warn("auto-theme: no shell to persist through")
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
    pickerProcess.command = [pluginFile("bin/auto-theme-pick"), canonical(current)]
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
    backgroundPicker.command = [pluginFile("bin/auto-theme-bg-pick"), canonical(slug), String(currentName || "")]
    close()
    backgroundPicker.running = true
  }

  // ----------------------------------------------------------- lifecycle

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: resolveService()
  onBarChanged: resolveService()
  onOpenedChanged: if (opened) resolveService()

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

    Item {
      width: timeline.width
      height: Style.space(12)

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
      }

      Rectangle {
        x: parent.width * timeline.dayFraction(timeline.dayStart)
        width: Math.max(2, parent.width
          * (timeline.dayFraction(timeline.dayEnd) - timeline.dayFraction(timeline.dayStart)))
        height: parent.height
        radius: height / 2
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.34)
      }

      Rectangle {
        width: Math.max(2, Style.space(2))
        height: parent.height + Style.space(8)
        y: -Style.space(4)
        x: Math.max(0, Math.min(parent.width - width,
          parent.width * timeline.dayFraction(root.nowMs) - width / 2))
        radius: width / 2
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

    function refresh() {
      if (slug === "" || infoProcess.running) return
      infoProcess.command = [root.pluginFile("bin/auto-theme-slot"), slug]
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
    }

    // The wallpaper can change without the theme changing, so the card follows
    // the remembered state rather than only its own slug.
    Connections {
      target: root.service
      enabled: root.service !== null
      function onBackgroundMemoryChanged() { card.refresh() }
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

    default property alias body: holder.children

    width: parent.width
    spacing: Style.space(12)

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
            width: parent.width
            title: "Auto Theme"
            meta: root.heroMeta
            foreground: root.fg
            fontFamily: root.face
            iconComponent: Text {
              text: root.barIcon
              color: root.fg
              font.family: root.face
              font.pixelSize: Style.font.display
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
              text: "Pinned. The schedule is not running; switch to Auto to follow it again."
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

          PanelSeparator { foreground: root.fg }

          // -------------------------------------------------- schedule

          Disclosure {
            visible: root.configMode === "auto"
            title: "SCHEDULE"
            summary: root.scheduleSummary

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
