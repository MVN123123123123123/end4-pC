import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property string thumbnailPath: {
        if (sourcePath.length == 0) return;
        const resolvedUrlWithoutFileProtocol = FileUtils.trimFileProtocol(`${Qt.resolvedUrl(sourcePath)}`);
        const encodedUrlWithoutFileProtocol = resolvedUrlWithoutFileProtocol.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encodedUrlWithoutFileProtocol}`);
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`;
    }
    source: thumbnailPath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onSourceSizeChanged: {
        if (!root.generateThumbnail || !root.sourcePath) return;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }
    Process {
        id: thumbnailGeneration
        command: {
            if (!root.sourcePath || !root.thumbnailPath) return ["true"];
            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            const outPath = FileUtils.trimFileProtocol(root.thumbnailPath);
            const srcPath = FileUtils.trimFileProtocol(root.sourcePath);
            const isVid = Images.isVideoByName(root.sourcePath);
            if (isVid) {
                return [
                    "bash", "-c",
                    'out="$1"; src="$2"; sz="$3"; [ -s "$out" ] && exit 0 || { mkdir -p "$(dirname "$out")" && (ffmpegthumbnailer -i "$src" -o "$out" -s "$sz" 2>/dev/null || { ffmpeg -y -ss 00:00:01 -i "$src" -vframes 1 -vf "scale=${sz}:${sz}:force_original_aspect_ratio=decrease" "$out" 2>/dev/null; if [ ! -s "$out" ]; then ffmpeg -y -i "$src" -vframes 1 -vf "scale=${sz}:${sz}:force_original_aspect_ratio=decrease" "$out" 2>/dev/null; fi; }); if [ -s "$out" ]; then exit 1; else rm -f "$out"; exit 2; fi; }',
                    "_",
                    outPath,
                    srcPath,
                    String(maxSize)
                ];
            }
            return [
                "bash", "-c", 
                'out="$1"; src="$2"; sz="$3"; [ -s "$out" ] && exit 0 || { mkdir -p "$(dirname "$out")" && magick "$src" -resize "${sz}x${sz}" "$out" 2>/dev/null; if [ -s "$out" ]; then exit 1; else rm -f "$out"; exit 2; fi; }',
                "_",
                outPath,
                srcPath,
                String(maxSize)
            ];
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) { // Force reload if thumbnail had to be generated
                root.source = "";
                root.source = Qt.binding(() => root.thumbnailPath);
            }
        }
    }
}
