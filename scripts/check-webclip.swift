import Foundation

@main
struct WebClipChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func main() throws {
        let spec = try WebClipSpec(bundleID: " com.tencent.xin ", title: "微信 & <测试>")
        let plist = try PropertyListSerialization.propertyList(from: spec.plistData(), format: nil) as! [String: Any]
        require(plist["ApplicationBundleIdentifier"] as? String == "com.tencent.xin", "Wrong launch target")
        require(plist["Title"] as? String == "微信 & <测试>", "XML escaping / Unicode round trip failed")
        require(plist["RemovalDisallowed"] as? Bool == false, "Clip must remain removable")
        require(plist["URL"] == nil, "Direct-launch payload must not use a URL")
        require(plist["TargetApplicationBundleIdentifier"] == nil, "Must not generate an MDM payload")
        for input in ["", "../com.app", "com.app/../../", "com..app", "com.app\\test", "wechat://", "com.app\nother", "com.应用", String(repeating: "a", count: 256) + ".app"] {
            require((try? WebClipSpec(bundleID: input, title: "")) == nil, "Unsafe bundle id accepted: \(input)")
        }
        for input in ["com.example.App-1", "com.tencent.xin", "org.example.app"] {
            require((try? WebClipSpec(bundleID: input, title: "")) != nil, "Valid bundle id rejected")
        }
        require((try? WebClipSpec(bundleID: "com.app", title: "one\ntwo")) == nil, "Control characters accepted")
        require((try? WebClipSpec(bundleID: "com.app", title: String(repeating: "a", count: 81))) == nil, "Overlong title accepted")
        let second = try WebClipSpec(bundleID: spec.bundleID, title: "../../other")
        require(spec.folderName != second.folderName, "Each attempt needs an isolated directory")
        require(!second.folderName.contains(".."), "Title leaked into destination path")
        require(second.targetPath.hasPrefix("/var/mobile/Library/WebClips/AirCard-WebClip-"), "Destination escaped fixed root")
        require(WebClipSpec.supportsTesting(on: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)), "27.0.1 blocked")
        for version in [(26,0,0), (27,0,0), (27,1,0), (27,2,3), (28,0,1)] {
            require(!WebClipSpec.supportsTesting(on: OperatingSystemVersion(majorVersion: version.0, minorVersion: version.1, patchVersion: version.2)), "Untested OS allowed")
        }
        let receipt = WebClipReceipt(spec: spec, createdAt: Date(), status: "pending")
        let decoded = try JSONDecoder().decode(WebClipReceipt.self, from: JSONEncoder().encode(receipt))
        require(decoded.spec == spec && decoded.status == "pending", "Receipt round trip failed")
        require(WebClipConnectionFailure.isBeforeWrite("Device connection failed: 172.16.0.1:49152 timeout"), "Connection-stage failure must allow manual retry")
        require(!WebClipConnectionFailure.isBeforeWrite("AFC write failed: Device connection failed:"), "Partial-write errors must stay guarded")
        require(!WebClipConnectionFailure.isBeforeWrite("Unknown error"), "Unknown failures must stay guarded")
        require(NetworkStatus.hasTunnelSubnet(in: [.init(name: "utun0", ipv4: "10.7.0.2", netmask: "255.255.255.0")], deviceIP: "10.7.0.1"), "Local tunnel subnet should be detected")
        require(!NetworkStatus.hasTunnelSubnet(in: [.init(name: "utun0", ipv4: "10.9.0.2", netmask: "255.255.255.0")], deviceIP: "10.7.0.1"), "Unrelated VPN must not pass subnet check")
        require(!NetworkStatus.hasTunnelSubnet(in: [.init(name: "en0", ipv4: "10.7.0.2", netmask: "255.255.255.0")], deviceIP: "10.7.0.1"), "Wi-Fi alone must not pass tunnel check")
        print("WebClip payload, path isolation, version gate, and receipt checks passed.")
    }
}
