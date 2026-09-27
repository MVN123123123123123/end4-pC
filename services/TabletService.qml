pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Universal drawing tablet controls.
 *
 * Discovery: parses the `Tablets:` section of `hyprctl devices`, which reports
 * every tablet with its name, address and physical size in millimeters.
 *
 * Geometry: turns the configured orientation, output and active area mode into
 * a physical rectangle on the tablet. The aspect ratio mode crops the tablet so
 * its drawing area matches the target monitor, so circles stay circles.
 *
 * Applying: pushes the result to the running compositor through `hyprctl eval`
 * and hands it to scripts/hyprland/tablet_configurator.py, which writes the
 * persistent shellOverrides/tablet.lua loaded by Hyprland on startup.
 */
Singleton {
    id: root

    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/hyprland/tablet_configurator.py")
    readonly property string overrideFilePath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/tablet.lua`)
    readonly property string mainOverridePath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)

    // ─── Detection ───────────────────────────────────────────────────────
    property var tablets: [] // [{ name, address, width, height }]
    readonly property bool hasTablet: root.tablets.length > 0
    property bool polling: false // kept on while the settings page is open

    readonly property var activeTablet: {
        const wanted = Config.options.tablet.targetDevice
        const match = wanted ? root.tablets.find(t => t.name === wanted) : null
        return match ?? (root.tablets.length > 0 ? root.tablets[0] : null)
    }
    readonly property real physWidth: root.activeTablet?.width ?? 0
    readonly property real physHeight: root.activeTablet?.height ?? 0

    // ─── Settings mirrors (reading them here is what triggers an apply) ──
    readonly property string cfgTargetDevice: Config.options.tablet.targetDevice
    readonly property string cfgOutput: Config.options.tablet.output
    readonly property int cfgOrientation: Config.options.tablet.orientation
    readonly property bool cfgLeftHanded: Config.options.tablet.leftHanded
    readonly property string cfgAreaMode: Config.options.tablet.activeAreaMode
    readonly property real cfgCustomWidth: Config.options.tablet.customWidth
    readonly property real cfgCustomHeight: Config.options.tablet.customHeight
    readonly property real cfgCustomX: Config.options.tablet.customX
    readonly property real cfgCustomY: Config.options.tablet.customY

    onCfgTargetDeviceChanged: root.scheduleApply()
    onCfgOutputChanged: root.scheduleApply()
    onCfgOrientationChanged: root.scheduleApply()
    onCfgLeftHandedChanged: root.scheduleApply()
    onCfgAreaModeChanged: root.scheduleApply()
    onCfgCustomWidthChanged: root.scheduleApply()
    onCfgCustomHeightChanged: root.scheduleApply()
    onCfgCustomXChanged: root.scheduleApply()
    onCfgCustomYChanged: root.scheduleApply()

    // ─── Geometry engine ─────────────────────────────────────────────────
    readonly property int orientation: ((root.cfgOrientation % 4) + 4) % 4
    readonly property bool vertical: root.orientation === 1 || root.orientation === 3
    readonly property int tabletTransform: (root.orientation + (root.cfgLeftHanded ? 2 : 0)) % 4

    readonly property var targetMonitor: {
        const out = root.cfgOutput
        const monitors = WM.monitors ?? []
        if (out) {
            const match = monitors.find(m => m.name === out)
            if (match) return match
        }
        return monitors.find(m => m.focused) ?? monitors[0] ?? null
    }

    // Width / height of the monitor the tablet is drawn on, as seen by the user.
    readonly property real displayRatio: {
        const mon = root.targetMonitor
        if (!mon) return 0
        const w = mon.width ?? 0
        const h = mon.height ?? 0
        if (w <= 0 || h <= 0) return 0
        const rotated = ((mon.transform ?? 0) % 2) === 1
        return (rotated ? h : w) / (rotated ? w : h)
    }

    readonly property var activeArea: root.computeArea(root.activeTablet)

    // "204.8 × 115.2 mm (16:9)" for the preview card.
    readonly property string activeAreaLabel: {
        const area = root.activeArea
        if (!area) return ""
        const w = root.vertical ? area.height : area.width
        const h = root.vertical ? area.width : area.height
        return `${root.fmtDisplay(w)} × ${root.fmtDisplay(h)} mm (${root.ratioLabel(w, h)})`
    }

    function computeArea(tab) {
        if (!tab) return null
        const tw = Number(tab.width) || 0
        const th = Number(tab.height) || 0
        if (tw <= 0 || th <= 0) return null

        const mode = root.cfgAreaMode
        if (mode === "custom") {
            const wantedW = Number(root.cfgCustomWidth) || 0
            const wantedH = Number(root.cfgCustomHeight) || 0
            const cw = Math.min(tw, wantedW > 0 ? wantedW : tw)
            const ch = Math.min(th, wantedH > 0 ? wantedH : th)
            const cx = Math.min(Math.max(Number(root.cfgCustomX) || 0, 0), tw - cw)
            const cy = Math.min(Math.max(Number(root.cfgCustomY) || 0, 0), th - ch)
            return { x: cx, y: cy, width: cw, height: ch }
        }

        if (mode === "full" || !(root.displayRatio > 0))
            return { x: 0, y: 0, width: tw, height: th }

        // A vertical tablet orientation transposes the axes, so the physical
        // rectangle has to follow the inverse of the monitor ratio.
        const wanted = root.vertical ? 1 / root.displayRatio : root.displayRatio
        let aw = tw
        let ah = th
        if (tw / th > wanted)
            aw = th * wanted
        else
            ah = tw / wanted
        return { x: (tw - aw) / 2, y: (th - ah) / 2, width: aw, height: ah }
    }

    function ratioLabel(w, h) {
        if (!(w > 0) || !(h > 0)) return ""
        const ratio = w / h
        const common = [
            [16, 9], [16, 10], [4, 3], [3, 2], [5, 4], [1, 1],
            [21, 9], [32, 9], [32, 10], [9, 16], [10, 16], [3, 4], [2, 3], [4, 5]
        ]
        for (const pair of common) {
            if (Math.abs(ratio - pair[0] / pair[1]) < 0.02) return `${pair[0]}:${pair[1]}`
        }
        return ratio.toFixed(2)
    }

    // ─── Applying ────────────────────────────────────────────────────────
    // 204.8 stays 204.8, 10.6666 stays 10.667, Lua reads all of it fine.
    function fmtLua(value) {
        return String(Math.round(Number(value) * 1000) / 1000)
    }

    function fmtDisplay(value) {
        return String(Math.round(Number(value) * 10) / 10)
    }

    function luaEscape(value) {
        return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
    }

    function scheduleApply() {
        if (!Config.ready) return
        applyTimer.restart()
    }

    // Back to "everything on every display, undistorted and unrotated".
    function resetToDefaults() {
        Config.options.tablet.output = ""
        Config.options.tablet.orientation = 0
        Config.options.tablet.leftHanded = false
        Config.options.tablet.activeAreaMode = "aspectRatio"
        Config.options.tablet.customWidth = 0
        Config.options.tablet.customHeight = 0
        Config.options.tablet.customX = 0
        Config.options.tablet.customY = 0
        root.scheduleApply()
    }

    function applyConfig() {
        if (WM.compositor !== "hyprland" || !Config.ready) return
        const area = root.activeArea
        if (!area) return

        const out = root.cfgOutput
        const transform = root.tabletTransform
        const size = `${root.fmtLua(area.width)}, ${root.fmtLua(area.height)}`
        const position = `${root.fmtLua(area.x)}, ${root.fmtLua(area.y)}`

        Quickshell.execDetached([
            "hyprctl", "eval",
            `hl.config({ input = { tablet = { output = "${out}", transform = ${transform}, ` +
            `active_area_size = { ${size} }, active_area_position = { ${position} } } } })`
        ])

        root.tablets.forEach(tab => {
            const tabArea = root.computeArea(tab)
            if (!tabArea) return
            Quickshell.execDetached([
                "hyprctl", "eval",
                `hl.device({ name = "${root.luaEscape(tab.name)}", output = "${out}", transform = ${transform}, ` +
                `active_area_size = { ${root.fmtLua(tabArea.width)}, ${root.fmtLua(tabArea.height)} }, ` +
                `active_area_position = { ${root.fmtLua(tabArea.x)}, ${root.fmtLua(tabArea.y)} } })`
            ])
        })

        root.persist(area)
    }

    function persist(area) {
        let args = [
            "python3", root.configuratorScriptPath,
            "--file", root.overrideFilePath,
            "--main-file", root.mainOverridePath,
            "--output", root.cfgOutput,
            "--transform", String(root.tabletTransform),
            "--active-area-size", root.fmtLua(area.width), root.fmtLua(area.height),
            "--active-area-position", root.fmtLua(area.x), root.fmtLua(area.y)
        ]
        root.tablets.forEach(tab => {
            const tabArea = root.computeArea(tab)
            if (!tabArea) return
            args.push("--device", tab.name)
            args.push("--device-area", tab.name,
                root.fmtLua(tabArea.width), root.fmtLua(tabArea.height),
                root.fmtLua(tabArea.x), root.fmtLua(tabArea.y))
        })
        Quickshell.execDetached(args)
    }

    // ─── Discovery plumbing ──────────────────────────────────────────────
    function refreshDevices() {
        if (WM.compositor !== "hyprland") return
        devicesProc.running = false
        devicesProc.running = true
    }

    // hyprctl devices only reports the physical size in its text output:
    //   Tablets:
    //       Tablet at 556773359210:
    //           some-tablet-name
    //               size: 204.8x136.5mm
    function parseDevices(text) {
        const lines = String(text ?? "").split("\n")
        const found = []
        for (let i = 0; i < lines.length; i++) {
            const head = lines[i].match(/^[ \t]*Tablet at ([0-9a-fA-F]+):[ \t]*$/)
            if (!head) continue
            const name = (lines[i + 1] ?? "").trim()
            const size = (lines[i + 2] ?? "").match(/size:\s*([0-9]+(?:\.[0-9]+)?)x([0-9]+(?:\.[0-9]+)?)mm/)
            if (!name || !size) continue
            found.push({
                address: "0x" + head[1],
                name: name,
                width: parseFloat(size[1]),
                height: parseFloat(size[2])
            })
        }
        root.tablets = found
    }

    function init() {
        root.refreshDevices()
        root.scheduleApply()
    }

    onTabletsChanged: {
        if (root.tablets.length > 0) root.scheduleApply()
    }

    Timer {
        id: applyTimer
        interval: 250
        repeat: false
        onTriggered: root.applyConfig()
    }

    Timer {
        id: pollTimer
        interval: 3000
        repeat: true
        running: root.polling
        onTriggered: root.refreshDevices()
    }

    Process {
        id: devicesProc
        command: ["hyprctl", "devices"]
        stdout: StdioCollector {
            id: devicesCollector
            onStreamFinished: root.parseDevices(devicesCollector.text)
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.scheduleApply()
        }
    }

    Connections {
        target: WM
        function onMonitorsChanged() {
            root.scheduleApply()
        }
    }

    Connections {
        target: Hyprland
        enabled: WM.compositor === "hyprland"

        function onRawEvent(event) {
            const name = event.name
            if (name === "monitoradded" || name === "monitorremoved" || name === "configreloaded") {
                root.refreshDevices()
                root.scheduleApply()
            }
        }
    }
}
