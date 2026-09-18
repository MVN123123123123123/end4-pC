pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Singleton {
    id: root

    property bool inhibit: false
    property string inhibitBinary: ""

    function load() {
    }

    function startInhibitProcess() {
        if (root.inhibit && root.inhibitBinary.length > 0 && !inhibitProc.running) {
            inhibitProc.command = [root.inhibitBinary, "--what=idle:sleep:handle-lid-switch", "--who=quickshell", "--why=Keep awake", "sleep", "infinity"];
            inhibitProc.running = true;
        }
    }

    function stopInhibitProcess() {
        if (inhibitProc.running) {
            inhibitProc.running = false;
        }
    }

    function initInhibit() {
        const saved = Persistent.states?.idle?.inhibit ?? false;
        if (root.inhibit !== saved) {
            root.inhibit = saved;
        } else if (saved) {
            root.startInhibitProcess();
        }
    }

    Component.onCompleted: {
        detectProc.running = true;
        if (Persistent.ready) {
            root.initInhibit();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) {
                root.initInhibit();
            }
        }
    }

    Connections {
        target: Persistent.states?.idle ?? null
        function onInhibitChanged() {
            if (Persistent.ready) {
                root.initInhibit();
            }
        }
    }

    onInhibitChanged: {
        if (root.inhibit) {
            root.startInhibitProcess();
        } else {
            root.stopInhibitProcess();
        }
        if (Persistent.ready && Persistent.states?.idle && Persistent.states.idle.inhibit !== root.inhibit) {
            Persistent.states.idle.inhibit = root.inhibit;
        }
    }

    function toggleInhibit(active = null) {
        const target = (active !== null) ? Boolean(active) : !root.inhibit;
        if (root.inhibit === target) {
            if (target) {
                root.startInhibitProcess();
            }
            return;
        }
        root.inhibit = target;
    }

    Process {
        id: detectProc
        command: ["sh", "-c", "if command -v systemd-inhibit >/dev/null 2>&1 && systemd-inhibit --list >/dev/null 2>&1; then echo systemd-inhibit; elif command -v elogind-inhibit >/dev/null 2>&1 && elogind-inhibit --list >/dev/null 2>&1; then echo elogind-inhibit; fi"]
        running: false
        stdout: StdioCollector {
            id: detectCollector
            onStreamFinished: {
                root.inhibitBinary = detectCollector.text.trim();
                root.startInhibitProcess();
            }
        }
    }

    Process {
        id: inhibitProc
        running: false
    }

    IdleInhibitor {
        id: idleInhibitor
        enabled: root.inhibit
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            anchors {
                right: true
                bottom: true
            }
            mask: Region {
                item: null
            }
        }
    }

    IpcHandler {
        target: "idle"

        function toggle(): void {
            root.toggleInhibit();
        }

        function enable(): void {
            root.toggleInhibit(true);
        }

        function disable(): void {
            root.toggleInhibit(false);
        }

        function status(): bool {
            return root.inhibit;
        }
    }
}