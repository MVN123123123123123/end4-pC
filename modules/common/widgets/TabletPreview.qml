import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Live preview of a drawing tablet: the outer rectangle is the whole physical
 * tablet, the tinted rectangle inside it is the area that actually maps to the
 * screen after the current orientation / aspect ratio / custom settings.
 */
Rectangle {
    id: root

    property var tabletService: TabletService

    readonly property var area: root.tabletService?.activeArea ?? null
    readonly property int degrees: (root.tabletService?.orientation ?? 0) * 90
    readonly property real physW: {
        const w = root.tabletService?.physWidth ?? 0
        return w > 0 ? w : 16
    }
    readonly property real physH: {
        const h = root.tabletService?.physHeight ?? 0
        return h > 0 ? h : 10
    }

    // 24px padding around the tablet, 44px below it for the size label.
    readonly property real previewScale: Math.max(0, Math.min(
        (root.width - 48) / root.physW,
        (root.height - 68) / root.physH))
    readonly property real frameW: Math.max(1, root.physW * root.previewScale)
    readonly property real frameH: Math.max(1, root.physH * root.previewScale)
    readonly property real frameX: (root.width - root.frameW) / 2
    readonly property real frameY: 24 + ((root.height - 68) - root.frameH) / 2

    readonly property real areaX: root.frameX + (root.area ? root.area.x * root.previewScale : 0)
    readonly property real areaY: root.frameY + (root.area ? root.area.y * root.previewScale : 0)
    readonly property real areaW: root.area ? Math.max(4, root.area.width * root.previewScale) : root.frameW
    readonly property real areaH: root.area ? Math.max(4, root.area.height * root.previewScale) : root.frameH

    Layout.fillWidth: true
    implicitHeight: 220
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    clip: true

    // Tablet bezel
    Rectangle {
        x: root.frameX
        y: root.frameY
        width: root.frameW
        height: root.frameH
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    // Active drawing area
    Rectangle {
        x: root.areaX
        y: root.areaY
        width: root.areaW
        height: root.areaH
        radius: Appearance.rounding.small
        color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25)
        border.width: 2
        border.color: Appearance.colors.colPrimary
    }

    // Stylus anchor, centered on the active area
    Item {
        x: root.areaX
        y: root.areaY
        width: root.areaW
        height: root.areaH

        Rectangle {
            anchors.centerIn: parent
            width: 26
            height: 2
            radius: 1
            color: Appearance.colors.colPrimary
        }
        Rectangle {
            anchors.centerIn: parent
            width: 2
            height: 26
            radius: 1
            color: Appearance.colors.colPrimary
        }
        Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 10
            radius: 5
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary
        }
    }

    // Orientation badge, top left of the tablet
    Rectangle {
        x: root.frameX + 10
        y: root.frameY + 10
        width: badgeText.implicitWidth + 18
        height: badgeText.implicitHeight + 8
        radius: height / 2
        color: Appearance.colors.colPrimary

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: `${root.degrees}°`
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnPrimary
        }
    }

    // Detected tablet, top right of the card
    StyledText {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 14
        anchors.rightMargin: 16
        // Long device names (they look like "vendor.product.driver-tablet")
        // should stay on one line instead of running across the card.
        width: Math.min(implicitWidth, root.width * 0.45)
        text: root.tabletService?.activeTablet?.name ?? ""
        elide: Text.ElideRight
        opacity: 0.5
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnLayer1
    }

    // Active area size and its ratio, bottom center of the card
    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        text: root.tabletService?.activeAreaLabel ?? ""
        opacity: 0.8
        horizontalAlignment: Text.AlignHCenter
        color: Appearance.colors.colOnLayer1
    }
}
