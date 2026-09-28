import AppKit

struct PlayerDetector {
    private static let supportedBundleIdentifiers = Set([
        "com.apple.Music",
        "com.spotify.client",
        "com.netease.163music",
        "com.tencent.QQMusicMac",
        "com.kugou.mac.Music",
        "com.colliderli.iina",
        "org.videolan.vlc",
        "com.tidal.desktop",
        "com.deezer.deezer-desktop",
        "co.brushedtype.doppler-macos"
    ].map { $0.lowercased() })

    private static let supportedBundlePrefixes = [
        "com.kugou.",
        "com.tencent.qqmusic"
    ]

    private static let supportedNameFragments = [
        "网易云音乐",
        "netease cloud music",
        "neteasemusic",
        "qq音乐",
        "qq music",
        "qqmusic",
        "酷狗音乐",
        "kugou music",
        "kugoumusic"
    ]

    static var frontmostPlayerName: String? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              isSupported(
                  bundleIdentifier: application.bundleIdentifier,
                  localizedName: application.localizedName
              ) else {
            return nil
        }

        return application.localizedName ?? "音乐播放器"
    }

    static func isSupported(bundleIdentifier: String?, localizedName: String?) -> Bool {
        if let bundleIdentifier {
            let normalizedIdentifier = bundleIdentifier.lowercased()
            if supportedBundleIdentifiers.contains(normalizedIdentifier) ||
                supportedBundlePrefixes.contains(where: { normalizedIdentifier.hasPrefix($0) }) {
                return true
            }
        }

        guard let localizedName else { return false }
        return supportedNameFragments.contains {
            localizedName.localizedCaseInsensitiveContains($0)
        }
    }
}
