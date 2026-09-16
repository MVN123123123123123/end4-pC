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
        if (!root.generateThumbnail) return;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }
    Process {
        id: thumbnailGeneration
        command: {
            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            const outPath = FileUtils.trimFileProtocol(root.thumbnailPath);
            const isVid = Images.isVideoByName(root.sourcePath);
            if (isVid) {
                return ["bash", "-c",
                    `[ -f '${outPath}' ] && exit 0 || { mkdir -p "$(dirname '${outPath}')" && (ffmpegthumbnailer -i '${root.sourcePath}' -o '${outPath}' -s ${maxSize} 2>/dev/null || ffmpeg -y -i '${root.sourcePath}' -vframes 1 -vf "scale=${maxSize}:-1" '${outPath}' 2>/dev/null) && exit 1; }`
                ];
            }
            return ["bash", "-c", 
                `[ -f '${outPath}' ] && exit 0 || { mkdir -p "$(dirname '${outPath}')" && magick '${root.sourcePath}' -resize ${maxSize}x${maxSize} '${outPath}' && exit 1; }`
            ];
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) { // Force reload if thumbnail had to be generated
                root.source = "";
                root.source = root.thumbnailPath; // Force reload
            }
        }
    }
}
