import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

Item {
    id: root
    required property Item blurSource
    property real cardRadius: 30
    property color tint: "white"
    property real tintOpacity: 0.15
    property real blurRadius: Config.options.background.widgets.blurRadius ?? 32
    property real trackX: 0
    property real trackY: 0
    property bool live: false

    function scheduleUpdate() {
        shaderSource.scheduleUpdate();
    }

    onBlurSourceChanged: scheduleUpdate()
    Component.onCompleted: scheduleUpdate()
    onXChanged: scheduleUpdate()
    onYChanged: scheduleUpdate()
    onWidthChanged: scheduleUpdate()
    onHeightChanged: scheduleUpdate()

    readonly property real oversample: blurRadius * 1.5

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width; height: root.height
            radius: root.cardRadius
        }
    }

    Connections {
        target: root.blurSource
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (root.blurSource && root.blurSource.status === Image.Ready) {
                root.scheduleUpdate();
            }
        }
    }

    FastBlur {
        id: blur
        x: -root.oversample
        y: -root.oversample
        width: root.width + root.oversample * 2
        height: root.height + root.oversample * 2
        radius: root.blurRadius
        visible: root.blurSource !== null
        source: root.blurSource ? shaderSource : null

        ShaderEffectSource {
            id: shaderSource
            sourceItem: root.blurSource
            sourceRect: {
                var _fx = root.trackX
                var _fy = root.trackY
                var _rx = root.x
                var _ry = root.y
                var _rw = root.width
                var _rh = root.height
                var _prx = root.parent ? root.parent.x : 0
                var _pry = root.parent ? root.parent.y : 0
                var _prw = root.parent ? root.parent.width : 0
                var _prh = root.parent ? root.parent.height : 0
                if (!root.blurSource) return Qt.rect(0, 0, 0, 0)
                var _bs = root.blurSource.scale
                var _bw = root.blurSource.width
                var _bh = root.blurSource.height
                var _bx = root.blurSource.x
                var _by = root.blurSource.y
                var _px = root.blurSource.panX ?? 0
                var _py = root.blurSource.panY ?? 0
                var p1 = root.mapToItem(root.blurSource, -root.oversample, -root.oversample)
                var p2 = root.mapToItem(root.blurSource, root.width + root.oversample, root.height + root.oversample)
                return Qt.rect(Math.min(p1.x, p2.x), Math.min(p1.y, p2.y), Math.abs(p2.x - p1.x), Math.abs(p2.y - p1.y))
            }
            onSourceRectChanged: root.scheduleUpdate()
            hideSource: false
            live: root.live
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.cardRadius
        color: root.tint
        opacity: root.tintOpacity
    }
}