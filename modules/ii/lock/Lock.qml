pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

LockScreen {
    id: root

    // Monitor name -> workspace id to restore on unlock (set when locking)
    property var savedWorkspaces: ({})
    property string lastProcessedLockWall: ""
    property bool lastProcessedDarkmode: Appearance.m3colors.darkmode

    Timer {
        id: restoreTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (GlobalStates.screenLocked) return;
            var batch = ""
            for (var j = 0; j < Quickshell.screens.length; ++j) {
                var monName = Quickshell.screens[j].name
                var wsId = root.savedWorkspaces[monName]
                if (wsId !== undefined) {
                    batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${monName}"})' 2>/dev/null || hyprctl dispatch focusmonitor "${monName}"; `
                    batch += `hyprctl dispatch 'hl.dsp.focus({workspace=${wsId}})' 2>/dev/null || hyprctl dispatch workspace ${wsId}; `
                }
            }
            if (batch.length > 0) {
                Quickshell.execDetached(["bash", "-c", batch])
            }
            restoreAnimTimer.restart()
        }
    }

    Timer {
        id: restoreAnimTimer
        interval: 800
        repeat: false
        onTriggered: {
            if (GlobalStates.screenLocked) return;
            var restoreAnimCmd = `hyprctl eval 'hl.animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "menu_decel", style = "slide" })' 2>/dev/null || hyprctl keyword animation workspaces,1,7,menu_decel,slide 2>/dev/null`
            Quickshell.execDetached(["bash", "-c", restoreAnimCmd])
        }
    }

    lockSurface: LockSurface {
        context: root.context
    }

    Process {
        id: lockThemeProc
        command: ["bash", "-c",
            `${Directories.wallpaperSwitchScriptPath} --mode ${Appearance.m3colors.darkmode ? "dark" : "light"} --colors_lock --image '${Config.options.background.lockWall}'`
        ]
        onExited: {
            MaterialThemeLoader.useLockTheme()
            root.lastProcessedLockWall = Config.options.background.lockWall
            root.lastProcessedDarkmode = Appearance.m3colors.darkmode
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            var wallChanged = Config.options.background.lockWall !== root.lastProcessedLockWall
            var modeChanged = Appearance.m3colors.darkmode !== root.lastProcessedDarkmode

            if (GlobalStates.screenLocked) {
                restoreTimer.stop()
                restoreAnimTimer.stop()

                if (Config.options.background.lockWall !== "" && (wallChanged || modeChanged)) {
                    lockThemeProc.running = true
                } else if (Config.options.background.lockWall !== "") {
                    MaterialThemeLoader.useLockTheme()
                }

                if (WM.compositor !== "hyprland") {
                    return;
                }

                var next = {}
                var setAnimCmd = `hyprctl eval 'hl.animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "menu_decel", style = "slidevert" })' 2>/dev/null || hyprctl keyword animation workspaces,1,7,menu_decel,slidevert 2>/dev/null; `
                var batch = setAnimCmd
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i].name
                    var mData = HyprlandData.monitors.find(m => m.name === mon)
                    var ws = (mData && mData.activeWorkspace && mData.activeWorkspace.id) ? mData.activeWorkspace.id : (i + 1)
                    next[mon] = ws
                    var tempWs = ws + 100 + (i * 10)
                    batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})' 2>/dev/null || hyprctl dispatch focusmonitor "${mon}"; `
                    batch += `hyprctl dispatch 'hl.dsp.focus({workspace=${tempWs}})' 2>/dev/null || hyprctl dispatch workspace ${tempWs}; `
                }
                root.savedWorkspaces = next
                Quickshell.execDetached(["bash", "-c", batch])
            } else {
                if (Config.options.background.lockWall !== "") {
                    MaterialThemeLoader.useLiveTheme()
                }
                if (WM.compositor === "hyprland") {
                    restoreTimer.start()
                }
            }
        }
    }

    // Push everything down (visual only; workspace switch is in Connections above)
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            property string targetMonitorName: modelData.name
            property int verticalMovementDistance: modelData.height
            property int horizontalSqueeze: modelData.width * 0.2
        }
    }
}