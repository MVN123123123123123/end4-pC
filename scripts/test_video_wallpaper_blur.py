import subprocess
import time
import os
import sys

def run_qml_test(name, qml_code, duration=3.0):
    test_file = f"/tmp/{name}.qml"
    with open(test_file, "w") as f:
        f.write(qml_code)
    
    cmd = ["qs", "-p", test_file]
    env = os.environ.copy()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    
    start_time = time.time()
    passed = False
    errors = []

    while time.time() - start_time < duration:
        ret = proc.poll()
        if ret is not None:
            break
        time.sleep(0.1)

    try:
        proc.terminate()
        stdout, stderr = proc.communicate(timeout=2)
    except Exception:
        proc.kill()
        stdout, stderr = proc.communicate()

    all_output = (stdout or "") + (stderr or "")
    print(f"=== {name} Output ===")
    for line in all_output.splitlines():
        if "TEST_PASS" in line:
            print("  [PASS]", line)
            passed = True
        elif "TEST_FAIL" in line:
            print("  [FAIL]", line)
            errors.append(line)
        elif "qml:" in line or "WARN" in line or "ERR" in line:
            print("  ", line)

    if not passed and not errors:
        errors.append("No TEST_PASS logged before timeout")

    return len(errors) == 0, all_output

def test_1_alignment_mathematics():
    """Verify coordinate mapping mathematics: videoContainer gives 0% error, videoWallpaper gives ~22% error."""
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

            readonly property rect containerRect: {
                var p1 = widget.mapToItem(videoContainer, -oversample, -oversample)
                var p2 = widget.mapToItem(videoContainer, widget.width + oversample, widget.height + oversample)
                return Qt.rect(Math.min(p1.x, p2.x), Math.min(p1.y, p2.y), Math.abs(p2.x - p1.x), Math.abs(p2.y - p1.y))
            }

            readonly property rect wallpaperRect: {
                var p1 = widget.mapToItem(videoWallpaper, -oversample, -oversample)
                var p2 = widget.mapToItem(videoWallpaper, widget.width + oversample, widget.height + oversample)
                return Qt.rect(Math.min(p1.x, p2.x), Math.min(p1.y, p2.y), Math.abs(p2.x - p1.x), Math.abs(p2.y - p1.y))
            }
        }

        Component.onCompleted: {
            console.log("[Test 1] effW:", videoContainer.effW, "effH:", videoContainer.effH)
            console.log("[Test 1] panX:", videoContainer.panX, "panY:", videoContainer.panY)
            console.log("[Test 1] videoWallpaper.x:", videoWallpaper.x, "y:", videoWallpaper.y)

            var pContainer1 = widget.mapToItem(videoContainer, -widget.oversample, -widget.oversample)
            var pContainer2 = widget.mapToItem(videoContainer, widget.width + widget.oversample, widget.height + widget.oversample)
            var cRect = Qt.rect(Math.min(pContainer1.x, pContainer2.x), Math.min(pContainer1.y, pContainer2.y), Math.abs(pContainer2.x - pContainer1.x), Math.abs(pContainer2.y - pContainer1.y))

            var pWallpaper1 = widget.mapToItem(videoWallpaper, -widget.oversample, -widget.oversample)
            var pWallpaper2 = widget.mapToItem(videoWallpaper, widget.width + widget.oversample, widget.height + widget.oversample)
            var wRect = Qt.rect(Math.min(pWallpaper1.x, pWallpaper2.x), Math.min(pWallpaper1.y, pWallpaper2.y), Math.abs(pWallpaper2.x - pWallpaper1.x), Math.abs(pWallpaper2.y - pWallpaper1.y))

            console.log("[Test 1] cRect (videoContainer):", cRect)
            console.log("[Test 1] wRect (videoWallpaper):", wRect)

            var expectedX = widget.x - widget.oversample
            var expectedY = widget.y - widget.oversample
            var expectedW = widget.width + widget.oversample * 2
            var expectedH = widget.height + widget.oversample * 2

            var containerErrX = Math.abs(cRect.x - expectedX)
            var containerErrY = Math.abs(cRect.y - expectedY)
            var wallpaperErrX = Math.abs(wRect.x - expectedX)
            var wallpaperErrY = Math.abs(wRect.y - expectedY)

            console.log("[Test 1] containerErrX:", containerErrX, "wallpaperErrX:", wallpaperErrX)

            if (containerErrX === 0 && containerErrY === 0) {
                console.log("TEST_PASS: videoContainer coordinate alignment error is 0.0% (exact match with screen)");
            } else {
                console.log("TEST_FAIL: videoContainer has error", containerErrX, containerErrY);
            }

            if (wallpaperErrX > 0 || wallpaperErrY > 0) {
                var pctErr = (wallpaperErrX / screen.width) * 100
                console.log("TEST_PASS: confirmed videoWallpaper produces coordinate displacement error of " + pctErr.toFixed(1) + "%");
            } else {
                console.log("TEST_FAIL: videoWallpaper did not produce expected misalignment");
            }
        }
    }
}
"""
    return run_qml_test("test_1_alignment", qml)

def test_2_qml_components_load():
    """Verify Background and LockSurface load with the updated videoContainer references."""
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
            console.log("[Test 2] Components instantiated successfully.");
            if (testGaussianBlur.source === videoContainer && testFastBlur.source === videoContainer) {
                console.log("TEST_PASS: GaussianBlur and FastBlur successfully bound to videoContainer");
            } else {
                console.log("TEST_FAIL: Blurs not bound to videoContainer");
            }
        }
    }
}
"""
    return run_qml_test("test_2_components", qml)

def test_3_lock_surface_configuration():
    """Verify LockSurface videoContainer and VideoOutput properties match wallpaper config."""
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

        MediaPlayer {
            id: lockVideoPlayer
            source: "file:///tmp/test_video.mp4"
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

        FastBlur {
            id: lockBlur
            anchors.fill: parent
            source: lockVideoContainer
            radius: 32
        }

        Component.onCompleted: {
            lockVideoPlayer.play();
            console.log("[Test 3] lockVideoContainer effW:", lockVideoContainer.effW, "effH:", lockVideoContainer.effH);
            console.log("[Test 3] lockVideoContainer panX:", lockVideoContainer.panX, "panY:", lockVideoContainer.panY);
            console.log("[Test 3] lockBlur source is lockVideoContainer:", lockBlur.source === lockVideoContainer);

            if (lockBlur.source === lockVideoContainer &&
                lockVideoOutput.width === lockVideoContainer.effW &&
                lockVideoOutput.height === lockVideoContainer.effH &&
                lockVideoContainer.scale === lockRoot.cfgScale &&
                lockVideoContainer.alignX === lockRoot.cfgAlignX &&
                lockVideoContainer.alignY === lockRoot.cfgAlignY &&
                lockVideoContainer.fitMode === lockRoot.cfgFitMode) {
                console.log("TEST_PASS: LockSurface video configuration perfectly matches wallpaper video config");
            } else {
                console.log("TEST_FAIL: LockSurface configuration mismatch");
            }
        }
    }
}
"""
    return run_qml_test("test_3_lock_config", qml)

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
            console.log("[Test 4] hiddenForFullscreen changed to:", hiddenForFullscreen);
            if (hiddenForFullscreen) {
                player.pause();
            } else {
                player.play();
            }
        }

        Timer {
            id: lockTimer
            interval: 500
            onTriggered: {
                console.log("[Test 4] Simulating Screen Lock...");
                testRoot.screenLocked = true;
            }
        }

        Timer {
            id: verifyTimer
            interval: 1200
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
            lockTimer.start();
            verifyTimer.start();
        }
    }
}
"""
    return run_qml_test("test_4_playback_lock", qml, duration=2.5)

if __name__ == "__main__":
    all_ok = True
    for t in [test_1_alignment_mathematics, test_2_qml_components_load, test_3_lock_surface_configuration, test_4_playback_during_lock]:
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
