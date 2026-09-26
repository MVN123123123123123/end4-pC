pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})
    property int windowRevision: 0

    // Convenient stuff

    function isRegionCovered(screenName, rx, ry, rw, rh) {
        var _rev = root.windowRevision;
        if (!root.windowList || root.windowList.length === 0) return false;

        var mon = null;
        if (root.monitors && root.monitors.length > 0) {
            mon = root.monitors.find(m => m.name === screenName);
        }
        var monX = mon ? mon.x : 0;
        var monY = mon ? mon.y : 0;

        var activeWsId = -1;
        if (typeof Hyprland !== "undefined" && Hyprland.workspaces) {
            var hlWs = Hyprland.workspaces.values.find(w => w.monitor && w.monitor.name === screenName && w.active);
            if (hlWs) activeWsId = hlWs.id;
        }
        if (activeWsId === -1 && mon && mon.activeWorkspace) {
            activeWsId = mon.activeWorkspace.id;
        }
        if (activeWsId === -1 && root.activeWorkspace) {
            activeWsId = root.activeWorkspace.id;
        }
        if (activeWsId === -1) return false;

        var specialWsId = (mon && mon.specialWorkspace && mon.specialWorkspace.id !== 0) ? mon.specialWorkspace.id : 0;

        for (var i = 0; i < root.windowList.length; ++i) {
            var w = root.windowList[i];
            if (!w.mapped || w.hidden) continue;
            if (w.workspace.id !== activeWsId && w.workspace.id !== specialWsId) continue;
            if (mon && w.monitor !== undefined && w.monitor !== mon.id) continue;

            var wx = w.at[0] - monX;
            var wy = w.at[1] - monY;
            var ww = w.size[0];
            var wh = w.size[1];

            if (wx <= rx && wy <= ry && (wx + ww) >= (rx + rw) && (wy + wh) >= (ry + rh)) {
                return true;
            }
        }
        return false;
    }

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    // Internals

    property bool _pendingClients: false
    property bool _pendingMonitors: false
    property bool _pendingLayers: false
    property bool _pendingWorkspaces: false

    Timer {
        id: eventDebounceTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (WM.compositor !== "hyprland") return;
            if (root._pendingClients) {
                getClients.running = false;
                getClients.running = true;
                root._pendingClients = false;
            }
            if (root._pendingMonitors) {
                getMonitors.running = false;
                getMonitors.running = true;
                root._pendingMonitors = false;
            }
            if (root._pendingLayers) {
                getLayers.running = false;
                getLayers.running = true;
                root._pendingLayers = false;
            }
            if (root._pendingWorkspaces) {
                getWorkspaces.running = false;
                getWorkspaces.running = true;
                getActiveWorkspace.running = false;
                getActiveWorkspace.running = true;
                root._pendingWorkspaces = false;
            }
        }
    }

    function queueUpdate(clients = false, workspaces = false, monitors = false, layers = false) {
        if (WM.compositor !== "hyprland") return;
        if (clients) root._pendingClients = true;
        if (workspaces) root._pendingWorkspaces = true;
        if (monitors) root._pendingMonitors = true;
        if (layers) root._pendingLayers = true;
        eventDebounceTimer.restart();
    }

    function updateWindowList() {
        queueUpdate(true, false, false, false);
    }

    function updateLayers() {
        queueUpdate(false, false, false, true);
    }

    function updateMonitors() {
        queueUpdate(false, false, true, false);
    }

    function updateWorkspaces() {
        queueUpdate(false, true, false, false);
    }

    function updateAll() {
        queueUpdate(true, true, true, true);
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        if (WM.compositor === "hyprland") {
            getClients.running = true;
            getMonitors.running = true;
            getLayers.running = true;
            getWorkspaces.running = true;
            getActiveWorkspace.running = true;
        }
    }

    Connections {
        target: Hyprland
        enabled: WM.compositor === "hyprland"

        function onRawEvent(event) {
            const name = event.name;
            if (["openlayer", "closelayer", "screencast", "submap", "activelayout"].includes(name)) return;

            if (name.startsWith("workspace") || name.startsWith("createworkspace") || name.startsWith("destroyworkspace") || name.startsWith("moveworkspace") || name === "renameworkspace") {
                root.queueUpdate(false, true, true, false);
            } else if (name.startsWith("activespecial")) {
                root.queueUpdate(false, true, true, false);
            } else if (name.startsWith("openwindow") || name.startsWith("closewindow") || name.startsWith("movewindow")) {
                root.queueUpdate(true, true, false, false);
            } else if (name.startsWith("window") || name.startsWith("activewindow") || name === "fullscreen" || name === "changefloatingmode" || name === "pin" || name === "urgent" || name === "minimize") {
                root.queueUpdate(true, false, false, false);
            } else if (name.startsWith("monitor") || name === "focusedmon") {
                root.queueUpdate(false, true, true, false);
            } else {
                root.queueUpdate(true, true, false, false);
            }
        }
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                try {
                    root.windowList = JSON.parse(clientsCollector.text);
                    let tempWinByAddress = {};
                    for (var i = 0; i < root.windowList.length; ++i) {
                        var win = root.windowList[i];
                        tempWinByAddress[win.address] = win;
                    }
                    root.windowByAddress = tempWinByAddress;
                    root.addresses = root.windowList.map(win => win.address);
                    root.windowRevision++;
                } catch (e) {
                    console.error("[HyprlandData] Failed to parse clients:", e);
                }
            }
        }
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(monitorsCollector.text);
                    root.windowRevision++;
                } catch (e) {
                    console.error("[HyprlandData] Failed to parse monitors:", e);
                }
            }
        }
    }

    Process {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                try {
                    root.layers = JSON.parse(layersCollector.text);
                } catch (e) {
                    console.error("[HyprlandData] Failed to parse layers:", e);
                }
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                try {
                    var rawWorkspaces = JSON.parse(workspacesCollector.text);
                    root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                    let tempWorkspaceById = {};
                    for (var i = 0; i < root.workspaces.length; ++i) {
                        var ws = root.workspaces[i];
                        tempWorkspaceById[ws.id] = ws;
                    }
                    root.workspaceById = tempWorkspaceById;
                    root.workspaceIds = root.workspaces.map(ws => ws.id);
                    root.windowRevision++;
                } catch (e) {
                    console.error("[HyprlandData] Failed to parse workspaces:", e);
                }
            }
        }
    }

    Process {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                try {
                    root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);
                    root.windowRevision++;
                } catch (e) {
                    console.error("[HyprlandData] Failed to parse active workspace:", e);
                }
            }
        }
    }
}