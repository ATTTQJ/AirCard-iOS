import Foundation

/// A direct-launch WebClip. This is a local folder payload, not a configuration profile.
/// The destination is fixed; user input can never become a filesystem path.
struct WebClipSpec: Codable, Equatable {
    static let targetParent = "/var/mobile/Library/WebClips"
    let id: UUID
    let bundleID: String
    let title: String

    init(bundleID: String, title: String, id: UUID = UUID()) throws {
        let bundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bundle.utf8.count <= 255,
              bundle.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil else {
            throw WebClipError.invalidBundleID
        }
        guard label.count <= 80, !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw WebClipError.invalidTitle
        }
        self.id = id
        self.bundleID = bundle
        self.title = label
    }

    var folderName: String { "AirCard-WebClip-\(id.uuidString).webclip" }
    var targetPath: String { Self.targetParent + "/" + folderName }

    func plistData() throws -> Data {
        // Independently implemented from the on-device WebClip format. No URL or
        // Shortcuts action is embedded: SpringBoard resolves the installed bundle.
        let info: [String: Any] = [
            "ApplicationBundleIdentifier": bundleID,
            "ApplicationBundleVersion": 1,
            "Title": title,
            "FullScreen": true,
            "ConfigurationIsManaged": false,
            "RemovalDisallowed": false,
            "IsAppClip": false,
            "ClassicMode": false,
            "ContentMode": "UIWebClipContentModeRecommended",
            "IconIsPrecomposed": true,
            "IconIsScreenShotBased": false,
            "IgnoreManifestScope": false,
            "Orientations": 0,
            "ScenelessBackgroundLaunch": false,
            "WebClipStatusBarStyle": "UIWebClipStatusBarStyleDefault"
        ]
        return try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    }

    static func supportsTesting(on version: OperatingSystemVersion) -> Bool {
        version.majorVersion == 27 && version.minorVersion == 0 && version.patchVersion == 1
    }
}

enum WebClipError: LocalizedError {
    case invalidBundleID, invalidTitle, invalidImage, unsupportedOS, noPairing, busy
    case transport(String)
    var errorDescription: String? {
        switch self {
        case .invalidBundleID: return "请输入正确的 App Bundle ID，例如 com.tencent.xin；不能填写网址或路径。"
        case .invalidTitle: return "图标名称不能超过 80 个字符，也不能包含换行或控制字符。"
        case .invalidImage: return "无法读取图标，请重新选择一张有效图片。"
        case .unsupportedOS: return "此实验功能暂时仅对 iOS 27.0.1 开放。"
        case .noPairing: return "请先到首页完成本机配对。"
        case .busy: return "另一项设备操作仍在进行，请等待结束。"
        case .transport(let message): return message
        }
    }
}

struct WebClipReceipt: Codable, Identifiable {
    var id: UUID { spec.id }
    let spec: WebClipSpec
    let createdAt: Date
    var status: String
    var diagnostic: String? = nil
}

/// Only these exact core errors originate before AFC or filesystem operations.
/// Unknown/partial-write errors must keep the duplicate-write guard in place.
enum WebClipConnectionFailure {
    static func isBeforeWrite(_ message: String) -> Bool {
        message.hasPrefix("Device connection failed:") || message.hasPrefix("Pairing file is invalid:")
    }
}
