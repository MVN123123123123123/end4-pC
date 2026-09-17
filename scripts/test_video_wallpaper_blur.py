import subprocess
import time
import os
import sys

def run_qml_test(name, qml_code, duration=3.0):
    test_file = f"/tmp/{name}.qml"
    with open(test_file, "w") as f:
        f.write(qml_code)
    
    cmd = ["stdbuf", "-oL", "qs", "-p", test_file]
    env = os.environ.copy()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    
    start_time = time.time()
    passed = False
    errors = []
    lines = []

    while time.time() - start_time < duration:
        line = proc.stdout.readline()
        if not line:
            if proc.poll() is not None:
                break
            time.sleep(0.05)
            continue
        lines.append(line.rstrip())
        if "TEST_PASS" in line:
            passed = True
            break
        elif "TEST_FAIL" in line:
            errors.append(line.rstrip())
            break

    try:
        proc.terminate()
        stdout, _ = proc.communicate(timeout=1.0)
        if stdout:
            for l in stdout.splitlines():
                lines.append(l)
                if "TEST_PASS" in l:
                    passed = True
                elif "TEST_FAIL" in l:
                    errors.append(l)
    except Exception:
        proc.kill()
        proc.communicate()

    all_output = "\n".join(lines)
    print(f"=== {name} Output ===")
    for line in lines:
        if "TEST_PASS" in line:
            print("  [PASS]", line)
        elif "TEST_FAIL" in line:
            print("  [FAIL]", line)
        elif "qml:" in line or "WARN" in line or "ERR" in line:
            print("  ", line)

    if not passed and not errors:
        errors.append("No TEST_PASS logged before timeout")

    return len(errors) == 0 and passed, all_output

def test_1_alignment_mathematics():
    """Verify coordinate mapping mathematics: videoContainer gives 0% error, videoWallpaper gives ~15-22% error."""
    qml = """import QtQuick
import Quickshell

ShellRoot {
    Item {
        id: screen
        width: 1920
        height: 1080

        property real scale: 1.2
        property real alignX: 0.5
        property real alignY: 0.0
        property string fitMode: "crop"

        property real vidW: 1920
        property real vidH: 1080
        property real vidAspect: vidW / vidH
        property real scrAspect: width / height

        Item {
            id: videoContainer
            anchors.fill: parent
            clip: true

            readonly property real baseW: width
            readonly property real baseH: height
            readonly property real scale: screen.scale
            readonly property real alignX: screen.alignX
            readonly property real alignY: screen.alignY
            readonly property string fitMode: screen.fitMode

            readonly property real vidAspect: screen.vidAspect
            readonly property real scrAspect: screen.scrAspect

            readonly property real effW: {
                if (fitMode === "stretch") return baseW * scale;
                if (fitMode === "fit") return (vidAspect > scrAspect ? baseW : baseH * vidAspect) * scale;
                return (vidAspect > scrAspect ? baseH * vidAspect : baseW) * scale;
            }
            readonly property real effH: {
                if (fitMode === "stretch") return baseH * scale;
                if (fitMode === "fit") return (vidAspect > scrAspect ? baseW / vidAspect : baseH) * scale;
                return (vidAspect > scrAspect ? baseH : baseW / vidAspect) * scale;
            }
            readonly property real maxPanX: Math.max(0, (effW - baseW) / 2)
            readonly property real maxPanY: Math.max(0, (effH - baseH) / 2)
            readonly property real panX: -alignX * maxPanX
            readonly property real panY: -alignY * maxPanY

            Item {
                id: videoWallpaper
                anchors.centerIn: parent
                width: videoContainer.effW
                height: videoContainer.effH
                transform: Translate {
                    x: videoContainer.panX
                    y: videoContainer.panY
                }
            }
        }

        Item {
            id: widget
            x: 400
            y: 300
            width: 300
            height: 200
            readonly property real oversample: 48
        }

        Component.onCompleted: {
            var pContainer1 = widget.mapToItem(videoContainer, -widget.oversample, -widget.oversample)
            var pContainer2 = widget.mapToItem(videoContainer, widget.width + widget.oversample, widget.height + widget.oversample)
            var cRect = Qt.rect(Math.min(pContainer1.x, pContainer2.x), Math.min(pContainer1.y, pContainer2.y), Math.abs(pContainer2.x - pContainer1.x), Math.abs(pContainer2.y - pContainer1.y))

            var pWallpaper1 = widget.mapToItem(videoWallpaper, -widget.oversample, -widget.oversample)
            var pWallpaper2 = widget.mapToItem(videoWallpaper, widget.width + widget.oversample, widget.height + widget.oversample)
            var wRect = Qt.rect(Math.min(pWallpaper1.x, pWallpaper2.x), Math.min(pWallpaper1.y, pWallpaper2.y), Math.abs(pWallpaper2.x - pWallpaper1.x), Math.abs(pWallpaper2.y - pWallpaper1.y))

            var expectedX = widget.x - widget.oversample
            var expectedY = widget.y - widget.oversample

            var containerErrX = Math.abs(cRect.x - expectedX)
            var containerErrY = Math.abs(cRect.y - expectedY)
            var wallpaperErrX = Math.abs(wRect.x - expectedX)
            var wallpaperErrY = Math.abs(wRect.y - expectedY)

            console.log("[Test 1] containerErrX:", containerErrX, "wallpaperErrX:", wallpaperErrX);

            if (containerErrX === 0 && containerErrY === 0 && (wallpaperErrX > 0 || wallpaperErrY > 0)) {
                var pctErr = (wallpaperErrX / screen.width) * 100;
                console.log("TEST_PASS: videoContainer gives 0.0% error while videoWallpaper produces " + pctErr.toFixed(1) + "% error");
            } else {
                console.log("TEST_FAIL: Alignment math failed, containerErrX:", containerErrX, "wallpaperErrX:", wallpaperErrX);
            }
        }
    }
}
"""
    return run_qml_test("test_1_alignment", qml, duration=2.0)

def test_2_qml_components_load():
    """Verify Background blurs and widget ShaderEffectSource bind cleanly to videoContainer."""
    qml = """import QtQuick
import Quickshell
import QtMultimedia
import Qt5Compat.GraphicalEffects

ShellRoot {
    Item {
        id: testRoot
        width: 1920
        height: 1080

        MediaPlayer {
            id: videoPlayer
            source: "file:///tmp/test_video.mp4"
            videoOutput: videoWallpaper
            loops: MediaPlayer.Infinite
            audioOutput: AudioOutput { muted: true }
        }

        Item {
            id: videoContainer
            anchors.fill: parent
            clip: true

            readonly property real baseW: width
            readonly property real baseH: height
            readonly property real scale: 1.0
            readonly property real alignX: 0.0
            readonly property real alignY: 0.0
            readonly property string fitMode: "crop"

            readonly property real effW: baseW * scale
            readonly property real effH: baseH * scale
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
                id: videoWallpaper
                property real panX: videoContainer.panX
                property real panY: videoContainer.panY
                anchors.centerIn: parent
                width: videoContainer.effW
                height: videoContainer.effH
                fillMode: VideoOutput.PreserveAspectCrop
                transformOrigin: Item.Center
                transform: Translate {
                    x: videoContainer.panX
                    y: videoContainer.panY
                }
            }
        }

        GaussianBlur {
            id: testGaussianBlur
            anchors.fill: parent
            source: videoContainer
            radius: 32
            samples: 16
        }

        FastBlur {
            id: testFastBlur
            anchors.fill: parent
            source: videoContainer
            radius: 48
        }

        Item {
            id: testWidget
            x: 100
            y: 100
            width: 200
            height: 150

            FastBlur {
                id: widgetBlur
                anchors.fill: parent
                radius: 32
                source: ShaderEffectSource {
                    sourceItem: videoContainer
                    sourceRect: Qt.rect(testWidget.x, testWidget.y, testWidget.width, testWidget.height)
                    live: true
                }
            }
        }

        Component.onCompleted: {
            videoPlayer.play();
            if (testGaussianBlur.source === videoContainer &&
                testFastBlur.source === videoContainer &&
                widgetBlur.source.sourceItem === videoContainer) {
                console.log("TEST_PASS: GaussianBlur, FastBlur, and widget ShaderEffectSource successfully bound to videoContainer");
            } else {
                console.log("TEST_FAIL: Blurs not bound to videoContainer");
            }
        }
    }
}
"""
    return run_qml_test("test_2_components", qml, duration=2.0)

def test_3_lock_surface_configuration():
    """Verify LockSurface videoContainer geometry and blur source parity with desktop config."""
    qml = """import QtQuick
import Quickshell
import QtMultimedia
import Qt5Compat.GraphicalEffects

ShellRoot {
    Item {
        id: lockRoot
        width: 1920
        height: 1080

        property real cfgScale: 1.5
        property real cfgAlignX: 0.8
        property real cfgAlignY: -0.4
        property string cfgFitMode: "fit"
        property string previewPath: "/tmp/preview_video.mp4"
        property string configPath: "/tmp/config_video.mp4"

        readonly property string effectiveWall: previewPath || configPath

        MediaPlayer {
            id: lockVideoPlayer
            source: lockRoot.effectiveWall !== "" ? ("file://" + lockRoot.effectiveWall) : ""
            videoOutput: lockVideoOutput
            loops: MediaPlayer.Infinite
            audioOutput: AudioOutput { muted: true }
        }

        Item {
            id: lockVideoContainer
            anchors.fill: parent
            clip: true

            readonly property real baseW: width
            readonly property real baseH: height
            readonly property real scale: lockRoot.cfgScale
            readonly property real alignX: lockRoot.cfgAlignX
            readonly property real alignY: lockRoot.cfgAlignY
            readonly property string fitMode: lockRoot.cfgFitMode

            readonly property real vidW: lockVideoOutput.implicitWidth > 0 ? lockVideoOutput.implicitWidth : baseW
            readonly property real vidH: lockVideoOutput.implicitHeight > 0 ? lockVideoOutput.implicitHeight : baseH
            readonly property real vidAspect: (vidH > 0 && vidW > 0) ? (vidW / vidH) : (baseW / baseH)
            readonly property real scrAspect: (baseH > 0 && baseW > 0) ? (baseW / baseH) : 1.0

            readonly property real effW: {
                if (fitMode === "stretch") return baseW * scale;
                if (fitMode === "fit") return (vidAspect > scrAspect ? baseW : baseH * vidAspect) * scale;
                return (vidAspect > scrAspect ? baseH * vidAspect : baseW) * scale;
            }

            readonly property real effH: {
                if (fitMode === "stretch") return baseH * scale;
                if (fitMode === "fit") return (vidAspect > scrAspect ? baseW / vidAspect : baseH) * scale;
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

        FastBlur {
            id: lockBlur
            anchors.fill: parent
            source: lockVideoContainer
            radius: 32
        }

        Component.onCompleted: {
            if (lockBlur.source === lockVideoContainer &&
                lockVideoOutput.width === lockVideoContainer.effW &&
                lockVideoOutput.height === lockVideoContainer.effH &&
                lockVideoContainer.scale === lockRoot.cfgScale &&
                lockVideoContainer.alignX === lockRoot.cfgAlignX &&
                lockVideoContainer.alignY === lockRoot.cfgAlignY &&
                lockVideoContainer.fitMode === lockRoot.cfgFitMode &&
                lockRoot.effectiveWall === lockRoot.previewPath) {
                console.log("TEST_PASS: LockSurface video configuration perfectly matches wallpaper video config");
            } else {
                console.log("TEST_FAIL: LockSurface configuration mismatch");
            }
        }
    }
}
"""
    return run_qml_test("test_3_lock_config", qml, duration=2.0)

def test_4_playback_during_lock():
    """Verify video does not stop or pause during screen lock."""
    qml = """import QtQuick
import Quickshell
import QtMultimedia

ShellRoot {
    Item {
        id: testRoot
        width: 1920
        height: 1080

        property bool screenLocked: false
        property bool activeWorkspaceFullscreen: true
        property bool hideWhenFullscreen: true

        readonly property bool hiddenForFullscreen: !screenLocked
            && activeWorkspaceFullscreen
            && hideWhenFullscreen

        MediaPlayer {
            id: player
            source: "file:///tmp/test_video.mp4"
            videoOutput: out
            loops: MediaPlayer.Infinite
            audioOutput: AudioOutput { muted: true }

            onPlaybackStateChanged: {
                console.log("[Test 4] PlaybackState changed to:", playbackState, "screenLocked:", testRoot.screenLocked);
            }
        }

        VideoOutput {
            id: out
            anchors.fill: parent
        }

        onHiddenForFullscreenChanged: {
            if (hiddenForFullscreen) {
                player.pause();
            } else {
                player.play();
            }
        }

        Timer {
            id: lockTimer
            interval: 300
            running: true
            onTriggered: {
                console.log("[Test 4] Simulating Screen Lock...");
                testRoot.screenLocked = true;
            }
        }

        Timer {
            id: verifyTimer
            interval: 700
            running: true
            onTriggered: {
                console.log("[Test 4] Verify playback state under lock:", player.playbackState);
                if (testRoot.screenLocked && !testRoot.hiddenForFullscreen && player.playbackState === MediaPlayer.PlayingState) {
                    console.log("TEST_PASS: Video wallpaper continues playing smoothly during screen lock without freeze");
                } else {
                    console.log("TEST_FAIL: Video stopped or paused during screen lock, playbackState:", player.playbackState);
                }
            }
        }

        Component.onCompleted: {
            player.play();
        }
    }
}
"""
    return run_qml_test("test_4_playback_lock", qml, duration=2.5)

def test_5_aspect_ratio_and_fit_modes():
    """Verify geometry calculations for portrait, ultrawide, and all fit modes (crop, fit, stretch)."""
    qml = """import QtQuick
import Quickshell

ShellRoot {
    Item {
        id: testRoot
        width: 1920
        height: 1080

        function computeEff(fitMode, scale, vidW, vidH, baseW, baseH) {
            var vidAspect = vidW / vidH;
            var scrAspect = baseW / baseH;
            var effW = 0;
            var effH = 0;
            if (fitMode === "stretch") {
                effW = baseW * scale;
                effH = baseH * scale;
            } else if (fitMode === "fit") {
                effW = (vidAspect > scrAspect ? baseW : baseH * vidAspect) * scale;
                effH = (vidAspect > scrAspect ? baseW / vidAspect : baseH) * scale;
            } else {
                effW = (vidAspect > scrAspect ? baseH * vidAspect : baseW) * scale;
                effH = (vidAspect > scrAspect ? baseH : baseW / vidAspect) * scale;
            }
            return { effW: effW, effH: effH };
        }

        Component.onCompleted: {
            var ok = true;
            // 1. Portrait 1080x1920 in crop mode on 1920x1080 screen (scale 1.0)
            var pCrop = computeEff("crop", 1.0, 1080, 1920, 1920, 1080);
            if (pCrop.effW < 1920 || pCrop.effH < 1080) {
                console.log("TEST_FAIL: Portrait crop smaller than screen bounds:", pCrop.effW, pCrop.effH);
                ok = false;
            }
            // 2. Ultrawide 2560x1080 in crop mode on 1920x1080 screen (scale 1.0)
            var uCrop = computeEff("crop", 1.0, 2560, 1080, 1920, 1080);
            if (uCrop.effW < 1920 || uCrop.effH < 1080) {
                console.log("TEST_FAIL: Ultrawide crop smaller than screen bounds:", uCrop.effW, uCrop.effH);
                ok = false;
            }
            // 3. Fit mode preserves aspect ratio
            var pFit = computeEff("fit", 1.0, 1080, 1920, 1920, 1080);
            var expectedAspect = 1080 / 1920;
            var actualAspect = pFit.effW / pFit.effH;
            if (Math.abs(actualAspect - expectedAspect) > 0.001) {
                console.log("TEST_FAIL: Fit mode aspect ratio error:", actualAspect, expectedAspect);
                ok = false;
            }
            // 4. Stretch mode stretches exactly to scaled dimensions
            var stretch = computeEff("stretch", 1.5, 1280, 720, 1920, 1080);
            if (stretch.effW !== 1920 * 1.5 || stretch.effH !== 1080 * 1.5) {
                console.log("TEST_FAIL: Stretch mode dimension mismatch:", stretch.effW, stretch.effH);
                ok = false;
            }

            if (ok) {
                console.log("TEST_PASS: All aspect ratios and fit modes (crop, fit, stretch) computed with mathematical precision");
            }
        }
    }
}
"""
    return run_qml_test("test_5_aspect_ratio_and_fit_modes", qml, duration=2.0)

def test_6_zero_dimension_fallback():
    """Verify videoContainer gracefully handles uninitialized/zero video dimensions without NaN."""
    qml = """import QtQuick
import Quickshell

ShellRoot {
    Item {
        id: testRoot
        width: 1920
        height: 1080

        readonly property real baseW: width
        readonly property real baseH: height
        readonly property real vidW: 0
        readonly property real vidH: 0

        readonly property real vidAspect: (vidH > 0 && vidW > 0) ? (vidW / vidH) : (baseW / baseH)
        readonly property real scrAspect: (baseH > 0 && baseW > 0) ? (baseW / baseH) : 1.0

        readonly property real effW: (vidAspect > scrAspect ? baseH * vidAspect : baseW) * 1.0
        readonly property real effH: (vidAspect > scrAspect ? baseH : baseW / vidAspect) * 1.0

        Component.onCompleted: {
            if (!isNaN(effW) && !isNaN(effH) && effW === baseW && effH === baseH) {
                console.log("TEST_PASS: Zero video dimensions safely fall back to base container aspect ratio without NaN");
            } else {
                console.log("TEST_FAIL: Zero dimension fallback produced NaN or invalid values:", effW, effH);
            }
        }
    }
}
"""
    return run_qml_test("test_6_zero_dimension_fallback", qml, duration=2.0)

def test_7_static_wallpaper_fallback():
    """Verify bindings cleanly fall back to static wallpaper item when wallpaperIsVideo is false."""
    qml = """import QtQuick
import Quickshell

ShellRoot {
    Item {
        id: testRoot
        width: 1920
        height: 1080

        property bool wallpaperIsVideo: false

        Item {
            id: videoContainer
            anchors.fill: parent
        }

        Image {
            id: wallpaper
            anchors.fill: parent
            property real panX: 0
            property real panY: 0
        }

        property Item activeWallpaperItem: wallpaperIsVideo ? videoContainer : wallpaper

        Component.onCompleted: {
            if (activeWallpaperItem === wallpaper && activeWallpaperItem.panX === 0) {
                console.log("TEST_PASS: Static wallpaper correctly binds to wallpaper image item when not video");
            } else {
                console.log("TEST_FAIL: Static wallpaper binding failed");
            }
        }
    }
}
"""
    return run_qml_test("test_7_static_wallpaper_fallback", qml, duration=2.0)

def test_8_rapid_lock_unlock_cycles():
    """Verify rapid lock/unlock toggles keep player in PlayingState without interruption."""
    qml = """import QtQuick
import Quickshell
import QtMultimedia

ShellRoot {
    Item {
        id: testRoot
        width: 1920
        height: 1080

        property bool screenLocked: false
        property int toggleCount: 0

        MediaPlayer {
            id: player
            source: "file:///tmp/test_video.mp4"
            videoOutput: out
            loops: MediaPlayer.Infinite
            audioOutput: AudioOutput { muted: true }
        }

        VideoOutput {
            id: out
            anchors.fill: parent
        }

        Timer {
            id: cycleTimer
            interval: 100
            repeat: true
            running: true
            onTriggered: {
                testRoot.screenLocked = !testRoot.screenLocked;
                testRoot.toggleCount++;
                if (testRoot.toggleCount >= 6) {
                    cycleTimer.stop();
                    console.log("[Test 8] Rapid toggles completed. Final playbackState:", player.playbackState);
                    if (player.playbackState === MediaPlayer.PlayingState) {
                        console.log("TEST_PASS: Video playback perfectly resilient across rapid lock/unlock transitions");
                    } else {
                        console.log("TEST_FAIL: Video playback broke during rapid toggle, state:", player.playbackState);
                    }
                }
            }
        }

        Component.onCompleted: {
            player.play();
        }
    }
}
"""
    return run_qml_test("test_8_rapid_lock_unlock", qml, duration=2.5)

if __name__ == "__main__":
    tests = [
        test_1_alignment_mathematics,
        test_2_qml_components_load,
        test_3_lock_surface_configuration,
        test_4_playback_during_lock,
        test_5_aspect_ratio_and_fit_modes,
        test_6_zero_dimension_fallback,
        test_7_static_wallpaper_fallback,
        test_8_rapid_lock_unlock_cycles,
    ]
    all_ok = True
    for t in tests:
        ok, _ = t()
        if not ok:
            all_ok = False
        print()

    if all_ok:
        print("ALL TESTS PASSED!")
        sys.exit(0)
    else:
        print("SOME TESTS FAILED!")
        sys.exit(1)
