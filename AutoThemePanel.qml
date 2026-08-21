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
  moduleName: "io.github.priard.auto-theme"
  ipcTarget: "io.github.priard.auto-theme"

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

  // Without coordinates there is no sunrise to follow, so the schedule is fixed
  // times whatever the config says. The service falls back the same way.
  readonly property string effectiveAutoMode: hasLocation ? autoMode : "fixed"

  // Weather Icons' clear-day and clear-night, the same pair the Omarchy weather
  // widget already renders, so the bar font is known to cover them. Written as
  // escapes rather than literal glyphs: private-use characters do not survive
  // every editor and transport, and one that gets eaten leaves a blank button
  // with nothing to indicate what went wrong.
  readonly property string barIcon: side === "day" ? "" : ""

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
  component ThemeRow: Column {
    id: row
    required property string label
    required property string slot
    required property string slug

    readonly property string mode: root.service ? root.service.themeMode(slug) : ""
    readonly property bool inForce: root.service && root.service.activeSlot === slot

    // No stored preference means "whatever the bar is doing now", so the toggle
    // shows the truth instead of a default the user never picked.
    readonly property bool transparentBar: {
      if (!root.service) return false
      var stored = root.service.rememberedTransparency(slug)
      return stored === null ? root.service.barTransparent : stored === true
    }

    width: parent.width
    spacing: Style.space(4)

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: row.label
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        visible: row.mode !== ""
        text: "(" + row.mode + ")"
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: row.inForce
        text: "· now"
        color: root.dim
        font.family: root.face
        font.pixelSize: Style.font.caption
      }
    }

    Button {
      width: parent.width
      text: row.slug === "" ? "Choose a theme…" : root.displayName(row.slug)
      bordered: true
      foreground: root.fg
      fontFamily: root.face
      onClicked: root.pickTheme(row.slot, row.slug)
    }

    Toggle {
      width: parent.width
      label: "Transparent bar"
      checked: row.transparentBar
      foreground: root.fg
      fontFamily: root.face
      enabled: row.slug !== ""
      onClicked: if (root.service) root.service.rememberTransparency(row.slug, !row.transparentBar)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

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
          spacing: Style.space(8)

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

        // --------------------------------------------------- schedule

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.configMode === "auto"

          PanelSectionHeader {
            text: "SCHEDULE"
            foreground: root.fg
            fontFamily: root.face
          }

          // Offering "Sunrise to sunset" without coordinates would be a button
          // that quietly does something else, so it is simply not there until
          // there is a location to compute it from.
          ButtonGroup {
            visible: root.hasLocation
            width: parent.width
            options: [
              { value: "sun", label: "Sunrise to sunset" },
              { value: "fixed", label: "Fixed hours" }
            ]
            value: root.effectiveAutoMode
            foreground: root.fg
            fontFamily: root.face
            onChanged: function(value) { root.persist({ autoMode: value }) }
          }

          Text {
            visible: root.hasLocation && root.effectiveAutoMode === "sun"
            width: parent.width
            text: root.sunLine
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !root.hasLocation
            width: parent.width
            text: "Sunrise and sunset need a location. Set one in the Weather widget, "
              + "or run:\nomarchy-weather-location --set \"City\" lat,lon\n"
              + "Until then, only fixed hours are available."
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            visible: root.effectiveAutoMode === "fixed"
            width: parent.width
            spacing: Style.space(12)

            Column {
              spacing: Style.space(4)

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
              spacing: Style.space(4)

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
        }

        PanelSeparator { foreground: root.fg }

        // ----------------------------------------------------- themes

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "THEMES"
            foreground: root.fg
            fontFamily: root.face
          }

          ThemeRow { label: "DAY"; slot: "dayTheme"; slug: root.dayTheme }
          ThemeRow { label: "NIGHT"; slot: "nightTheme"; slug: root.nightTheme }

          Text {
            visible: !root.wallpaperRenderable
            width: parent.width
            text: "This wallpaper is in a format Qt cannot decode here, so the desktop "
              + "paints black behind a transparent bar and the bar colours itself for a "
              + "picture nobody can see. Transparency is held off until it can render. "
              + "Install qt6-imageformats to get it back; the preference above is kept."
            color: root.fg
            font.family: root.face
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "Changing the theme anywhere else — the menu, the theme switcher — "
              + "sets it for whichever half of the day is running. Backgrounds and bar "
              + "transparency are remembered per theme."
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
