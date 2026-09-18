import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Qt5Compat.GraphicalEffects
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.ii.bar as Bar
import Quickshell
import Quickshell.Services.SystemTray

MouseArea {
    id: root
    required property LockContext context
    property bool active: false
    property bool showInputField: active || context.currentText.length > 0
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower
    readonly property MprisPlayer activePlayer: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase()
        if (preferred.length === 0) return MprisController.activePlayer
        const _ = MprisController.players.count
        for (const p of MprisController.players) {
            if ((p.identity ?? "").toLowerCase().includes(preferred) ||
                (p.desktopEntry ?? "").toLowerCase().includes(preferred))
                return p
        }
        return MprisController.activePlayer
    }

    property var    artUrl:      activePlayer?.trackArtUrl ?? ""

    // Force focus on entry
    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => {
        forceFieldFocus();
    }
    onPositionChanged: mouse => {
        forceFieldFocus();
    }

    // Toolbar appearing animation
    property real toolbarScale: 0.9
    property real toolbarOpacity: 0
    Behavior on toolbarScale {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }
    Behavior on toolbarOpacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Init
    Component.onCompleted: {
        forceFieldFocus();
        toolbarScale = 1;
        toolbarOpacity = 1;
    }

    // Key presses
    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
        } 
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false;
        }
        forceFieldFocus();
    }

    // RippleButton {
    //     anchors {
    //         top: parent.top
    //         left: parent.left
    //         leftMargin: 10
    //         topMargin: 10
    //     }
    //     implicitHeight: 40
    //     colBackground: Appearance.colors.colLayer2
    //     onClicked: {
    //         context.unlocked(LockContext.ActionEnum.Unlock);
    //         GlobalStates.screenLocked = false;
    //     }
    //     contentItem: StyledText {
    //         text: "[[ DEBUG BYPASS ]]"
    //     }
    // }

    Loader {
        anchors.fill: parent
        z: -1
        active: WM.compositor === "niri"

        sourceComponent: Item {
            anchors.fill: parent

            readonly property string effectiveWall: (GlobalStates.screenLocked && Config.options.background.lockWall !== "")
                ? Config.options.background.lockWall
                : (Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath)
            readonly property bool isVideo: Images.isVideoByName(effectiveWall)

            property int lockVideoRetryCount: 0

            onEffectiveWallChanged: {
                lockVideoRetryCount = 0;
            }

            Timer {
                id: lockRecoveryTimer
                interval: 250
                repeat: false
                onTriggered: {
                    if (isVideo && lockVideoPlayer.source.toString() !== "") {
                        if (Config.options.background.video?.loop === false && (lockVideoPlayer.playbackState === MediaPlayer.StoppedState || lockVideoPlayer.mediaStatus === MediaPlayer.EndOfMedia)) {
                            return;
                        }
                        if (lockVideoPlayer.playbackState !== MediaPlayer.PlayingState) {
                            if (lockVideoPlayer.error !== MediaPlayer.NoError) {
                                if (lockVideoRetryCount >= 2) {
                                    console.warn("[LockSurface] Video playback failed permanently after retries, stopping recovery.");
                                    lockVideoPlayer.stop();
                                    return;
                                }
                                lockVideoRetryCount++;
                                const s = lockVideoPlayer.source;
                                lockVideoPlayer.source = "";
                                lockVideoPlayer.source = s;
                            }
                            lockVideoPlayer.play();
                        }
                    }
                }
            }

            MediaPlayer {
                id: lockVideoPlayer
                source: isVideo
                    ? ("file://" + FileUtils.trimFileProtocol(effectiveWall))
                    : ""
                videoOutput: lockVideoOutput
                loops: (Config.options.background.video?.loop !== false) ? MediaPlayer.Infinite : 1
                audioOutput: null
                onPlaybackStateChanged: {
                    if (playbackState === MediaPlayer.PlayingState && error === MediaPlayer.NoError) {
                        lockVideoRetryCount = 0;
                    }
                    if (isVideo && source.toString() !== "" && playbackState !== MediaPlayer.PlayingState) {
                        if (Config.options.background.video?.loop === false && (playbackState === MediaPlayer.StoppedState || mediaStatus === MediaPlayer.EndOfMedia)) {
                            return;
                        }
                        lockRecoveryTimer.restart();
                    }
                }
                onMediaStatusChanged: {
                    if (mediaStatus === MediaPlayer.EndOfMedia) {
                        if (Config.options.background.video?.loop !== false) {
                            play();
                        }
                    }
                }
                onSourceChanged: {
                    if (source.toString() !== "") {
                        play();
                    } else {
                        stop();
                    }
                }
                Component.onCompleted: {
                    if (source.toString() !== "") play();
                }
                onErrorOccurred: (error, errorString) => {
                    console.warn("[LockSurface] Video player error:", error, errorString);
                    if (isVideo && source.toString() !== "") {
                        if (lockVideoRetryCount < 2) {
                            lockRecoveryTimer.restart();
                        } else {
                            console.warn("[LockSurface] Video playback failed permanently after retries, stopping recovery.");
                            stop();
                        }
                    }
                }
            }

            Item {
                id: lockVideoContainer
                anchors.fill: parent
                visible: isVideo
                clip: true

                readonly property real baseW: width
                readonly property real baseH: height
                readonly property real scale: Config.options.background.video?.scale || 1.0
                readonly property real alignX: Config.options.background.video?.alignX || 0.0
                readonly property real alignY: Config.options.background.video?.alignY || 0.0
                readonly property string fitMode: Config.options.background.video?.fitMode || "crop"

                readonly property real vidW: lockVideoOutput.implicitWidth > 0 ? lockVideoOutput.implicitWidth : (lockVideoOutput.sourceRect.width > 0 ? lockVideoOutput.sourceRect.width : baseW)
                readonly property real vidH: lockVideoOutput.implicitHeight > 0 ? lockVideoOutput.implicitHeight : (lockVideoOutput.sourceRect.height > 0 ? lockVideoOutput.sourceRect.height : baseH)
                readonly property real vidAspect: (vidH > 0 && vidW > 0) ? (vidW / vidH) : (baseW / baseH)
                readonly property real scrAspect: (baseH > 0 && baseW > 0) ? (baseW / baseH) : 1.0

                readonly property real effW: {
                    if (fitMode === "stretch") return baseW * scale;
                    if (fitMode === "fit") {
                        return (vidAspect > scrAspect ? baseW : baseH * vidAspect) * scale;
                    }
                    return (vidAspect > scrAspect ? baseH * vidAspect : baseW) * scale;
                }

                readonly property real effH: {
                    if (fitMode === "stretch") return baseH * scale;
                    if (fitMode === "fit") {
                        return (vidAspect > scrAspect ? baseW / vidAspect : baseH) * scale;
                    }
                    return (vidAspect > scrAspect ? baseH : baseW / vidAspect) * scale;
                }

                readonly property real maxPanX: Math.max(0, (effW - baseW) / 2)
                readonly property real maxPanY: Math.max(0, (effH - baseH) / 2)

                readonly property real panX: -alignX * maxPanX
                readonly property real panY: -alignY * maxPanY

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    z: -1
                }

                VideoOutput {
                    id: lockVideoOutput
                    property real panX: lockVideoContainer.panX
                    property real panY: lockVideoContainer.panY
                    anchors.centerIn: parent
                    width: lockVideoContainer.effW
                    height: lockVideoContainer.effH
                    fillMode: lockVideoContainer.fitMode === "stretch" ? VideoOutput.Stretch : VideoOutput.PreserveAspectCrop
                    transformOrigin: Item.Center

                    transform: Translate {
                        x: lockVideoContainer.panX
                        y: lockVideoContainer.panY
                    }
                }
            }

            Image {
                id: lockBgSource
                anchors.fill: parent
                source: !isVideo
                    ? effectiveWall
                    : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: !isVideo
            }

            GaussianBlur {
                anchors.fill: parent
                source: isVideo ? lockVideoContainer : lockBgSource
                radius: Config.options.lock.blur.enable ? Config.options.lock.blur.radius : 0
                samples: Config.options.lock.blur.size
                visible: Config.options.lock.blur.enable

                Rectangle {
                    opacity: Config.options.lock.blur.enable ? 1 : 0
                    anchors.fill: parent
                    color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                }
            }
        }
    }

    // Clicking the centered wallpaper (a square around the screen center
    // matching its locked size) plays the heartbeat thump on the background.
    // Keeps the password field focused like any other lock-screen press.
    MouseArea {
        id: centeredWallpaperThumpArea
        z: 1
        width: Math.max(1, Config.options.background.centeredWallpaperSize)
        height: width
        anchors.centerIn: parent
        visible: Config.options.background.centeredWallpaper
        onClicked: {
            root.forceFieldFocus()
            GlobalStates.centeredWallpaperThumpRequested()
        }
        // Scroll cycles the centered wallpaper shape (up = next, down = previous),
        // same cooldown as the desktop so fast scrolling can't skip shapes.
        onWheel: (wheel) => {
            if (!Config.options.background.centeredWallpaperShapeCycle) return
            if (shapeCycleCooldown.running) return
            root.forceFieldFocus()
            GlobalStates.cycleCenteredWallpaperShape(wheel.angleDelta.y > 0 ? 1 : -1)
            shapeCycleCooldown.restart()
            wheel.accepted = true
        }
        Timer {
            id: shapeCycleCooldown
            interval: 400
        }
    }

    // Main toolbar: password box
    Toolbar {
        id: mainIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 20
        }
        Behavior on anchors.bottomMargin {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        // Fingerprint
        Loader {
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            Layout.alignment: Qt.AlignVCenter
            active: root.context.fingerprintsConfigured
            visible: active

            sourceComponent: MaterialSymbol {
                id: fingerprintIcon
                fill: 1
                text: "fingerprint"
                iconSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        ToolbarTextField {
            id: passwordBox
            Layout.rightMargin: -Layout.leftMargin
            placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")

            // Style
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
            selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

            // Password
            enabled: !root.context.unlockInProgress
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData

            // Synchronizing (across monitors) and unlocking
            onTextChanged: root.context.currentText = this.text
            onAccepted: {
                root.context.tryUnlock(ctrlHeld);
            }
            Connections {
                target: root.context
                function onCurrentTextChanged() {
                    passwordBox.text = root.context.currentText;
                }
            }

            Keys.onPressed: event => {
                root.context.resetClearTimer();
            }
            
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: passwordBox.width - 8
                    height: passwordBox.height
                    radius: height / 2
                }
            }

            // Shake when wrong password
            ErrorShakeAnimation {
                id: wrongPasswordShakeAnim
                target: passwordBox
            }
            Connections {
                target: GlobalStates
                function onScreenUnlockFailedChanged() {
                    if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
                }
            }

            // We're drawing dots manually
            property bool materialShapeChars: Config.options.lock.materialShapeChars
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
            Loader {
                active: passwordBox.materialShapeChars
                anchors {
                    fill: parent
                    leftMargin: passwordBox.padding
                    rightMargin: passwordBox.padding
                }
                sourceComponent: PasswordChars {
                    length: root.context.currentText.length
                    selectionStart: passwordBox.selectionStart
                    selectionEnd: passwordBox.selectionEnd
                    cursorPosition: passwordBox.cursorPosition
                }
            }
        }

        ToolbarButton {
            id: confirmButton
            implicitWidth: height
            toggled: true
            enabled: !root.context.unlockInProgress
            colBackgroundToggled: Appearance.colors.colPrimary

            onClicked: root.context.tryUnlock()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: 24
                text: {
                    if (root.context.targetAction === LockContext.ActionEnum.Unlock) {
                        return root.ctrlHeld ? "coffee" : "arrow_right_alt";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                        return "power_settings_new";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                        return "restart_alt";
                    }
                }
                color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }
        }
    }

    // Left toolbar
    Toolbar {
        id: leftIsland
        visible: Config.options.lock.showToolbars
        anchors {
            right: mainIsland.left
            top: mainIsland.top
            bottom: mainIsland.bottom
            rightMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        // Username
        IconAndTextPair {
            Layout.leftMargin: 8
            icon: "account_circle"
            visible: !Config.options.lock.showMedia || MprisController.activePlayer === null
            text: SystemInfo.username
        }

        // Media player info 
        Loader {
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            Layout.alignment: Qt.AlignVCenter
            active: MprisController.activePlayer !== null
            visible: active && Config.options.lock.showMedia
            
            sourceComponent: Item {
                implicitWidth: mediaRow.implicitWidth
                implicitHeight: mediaRow.implicitHeight
                
                readonly property MprisPlayer activePlayer: MprisController.activePlayer
                readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || ""
                
                Timer {
                    running: activePlayer?.playbackState == MprisPlaybackState.Playing
                    interval: Config.options.resources.updateInterval
                    repeat: true
                    onTriggered: activePlayer.positionChanged()
                }
                
                RowLayout {
                    id: mediaRow
                    spacing: 8
                    anchors.centerIn: parent
                    
                    Rectangle {
                        id: artRect
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        Layout.alignment: Qt.AlignVCenter
                        clip: true 

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: artRect.width
                                height: artRect.height
                                radius: artRect.radius
                            }
                        }

                        StyledImage {
                            anchors.centerIn: parent
                            width: artRect.width
                            height: artRect.height
                            source: root.artUrl
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            antialiasing: true
                            sourceSize.width: artRect.width * 2
                            sourceSize.height: artRect.height * 2
                            visible: root.artUrl !== ""
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: 1
                            text: "music_note"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                            visible: root.artUrl === ""
                        }
                    }
                    
                    Column {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: -2
                        
                        StyledText {
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            width: Math.min(implicitWidth, 180) 
                            color: Appearance.colors.colOnSurfaceVariant
                            text: {
                                var artist = activePlayer?.trackArtist || " ";
                                return artist.length > 25 ? artist.substring(0, 25) + "..." : artist;
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        
                        StyledText {
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            width: Math.min(implicitWidth, 180) 
                            color: Appearance.colors.colOnSurfaceVariant
                            text: {
                                var title = cleanedTitle;
                                return title.length > 30 ? title.substring(0, 30) + "..." : title;
                            }
                            font.weight: Font.Medium
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                    
                    ClippedFilledCircularProgress {
                        id: mediaCircProg
                        Layout.alignment: Qt.AlignVCenter
                        lineWidth: Appearance.rounding.unsharpen
                        value: activePlayer?.position / activePlayer?.length
                        implicitSize: 24
                        colPrimary: Appearance.colors.colOnSurfaceVariant
                        enableAnimation: false
                        
                        Item {
                            anchors.centerIn: parent
                            width: mediaCircProg.implicitSize
                            height: mediaCircProg.implicitSize
                            
                            MaterialSymbol {
                                anchors.centerIn: parent
                                fill: 1
                                text: "music_note"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }
        }

        // Keyboard layout (Xkb)
        Loader {
            Layout.rightMargin: 8
            Layout.fillHeight: true
            visible: !Config.options.lock.showMedia || MprisController.activePlayer === null

            sourceComponent: Row {
                spacing: 8

                MaterialSymbol {
                    id: keyboardIcon
                    anchors.verticalCenter: parent.verticalCenter
                    fill: 1
                    text: "keyboard_alt"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnSurfaceVariant
                }
                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: StyledText {
                        text: HyprlandXkb.currentLayoutCode
                        color: Appearance.colors.colOnSurfaceVariant
                        animateChange: true
                    }
                }
            }
        }

        // Keyboard layout (Fcitx)
        Bar.SysTray {
            Layout.rightMargin: 10
            Layout.alignment: Qt.AlignVCenter
            showSeparator: false
            showOverflowMenu: false
            pinnedItems: SystemTray.items.values.filter(i => i.id == "Fcitx")
            visible: pinnedItems.length > 0
        }
    }

    // Right toolbar
    Toolbar {
        id: rightIsland
        visible: Config.options.lock.showToolbars
        anchors {
            left: mainIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
            leftMargin: 10
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        IconAndTextPair {
            visible: Battery.available
            icon: Battery.isCharging ? "bolt" : "battery_android_full"
            text: Math.round(Battery.percentage * 100)
            color: (Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
        }

        IconToolbarButton {
            id: sleepButton
            onClicked: Session.suspend()
            text: "dark_mode"
        }

        PasswordGuardedIconToolbarButton {
            id: powerButton
            text: "power_settings_new"
            targetAction: LockContext.ActionEnum.Poweroff
        }

        PasswordGuardedIconToolbarButton {
            id: rebootButton
            text: "restart_alt"
            targetAction: LockContext.ActionEnum.Reboot
        }
    }

    component PasswordGuardedIconToolbarButton: IconToolbarButton {
        id: guardedBtn
        required property var targetAction

        toggled: root.context.targetAction === guardedBtn.targetAction

        onClicked: {
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedBtn.targetAction);
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }

    component IconAndTextPair: Row {
        id: pair
        required property string icon
        required property string text
        property color color: Appearance.colors.colOnSurfaceVariant

        spacing: 4
        Layout.fillHeight: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: pair.icon
            iconSize: Appearance.font.pixelSize.huge
            animateChange: true
            color: pair.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: pair.text
            color: pair.color
        }
    }
}
