import Foundation

// MARK: - 演示数据（仅 --mock / --demo 调试时使用）

enum MockData {
    static var projectName: String { "DemoApp.xcodeproj" }

    static var scanSteps: [String] {
        [
            "DemoApp/Sources/AppDelegate.swift",
            "DemoApp/Assets.xcassets/icon.imageset/icon@3x.png",
            "DemoApp/Assets.xcassets/banner.imageset/banner.png",
            "DemoApp/Assets.xcassets/old_bg.dataset/old_bg.pdf",
            "DemoApp/Views/ProfileCell.xib",
            "DemoApp/Views/Onboarding.storyboard",
            "DemoApp/Views/LegacyDetailViewController.xib",
            "DemoApp/Utils/OldHelper.swift",
            "DemoApp/Utils/DeprecatedAPI.m",
            "DemoApp/Networking/OldEndpoint.swift",
            "DemoApp/Resources/strings_unused.txt",
            "DemoApp/Resources/launch_splash.gif",
            "DemoApp/Assets.xcassets/unused_icon.imageset/unused_icon.png",
        ]
    }

    static var projectItems: [ResourceItem] {
        [
            ResourceItem(
                id: UUID(), name: "hero_banner@3x.png",
                relativePath: "Assets.xcassets/hero_banner.imageset/hero_banner@3x.png",
                absolutePath: "", sizeBytes: 486_400, type: .image, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "promo_card.png",
                relativePath: "Assets.xcassets/promo_card.imageset/promo_card.png",
                absolutePath: "", sizeBytes: 312_320, type: .image, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "old_launch.pdf",
                relativePath: "Assets.xcassets/old_launch.dataset/old_launch.pdf",
                absolutePath: "", sizeBytes: 188_416, type: .data, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "brand_legacy_color",
                relativePath: "Assets.xcassets/brand_legacy_color.colorset",
                absolutePath: "", sizeBytes: 1_280, type: .color, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "OrphanPanel.swift",
                relativePath: "Views/Legacy/OrphanPanel.swift",
                absolutePath: "", sizeBytes: 7_680, type: .code, unreferenced: true,
                needsReview: true, notInTarget: true,
                note: "在工程导航器中，但没有加入任何 target 的编译阶段"
            ),
            ResourceItem(
                id: UUID(), name: "avatar_placeholder.webp",
                relativePath: "Resources/avatar_placeholder.webp",
                absolutePath: "", sizeBytes: 96_256, type: .image, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "tab_share.svg",
                relativePath: "Resources/icons/tab_share.svg",
                absolutePath: "", sizeBytes: 8_192, type: .image, unreferenced: true,
                needsReview: true, note: "名称片段「tab_」出现在工程文本中，可能为拼接引用"
            ),
            ResourceItem(
                id: UUID(), name: "splash_old.gif",
                relativePath: "Resources/splash_old.gif",
                absolutePath: "", sizeBytes: 1_024_000, type: .image, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "empty_state.png",
                relativePath: "Assets.xcassets/empty_state.imageset/empty_state.png",
                absolutePath: "", sizeBytes: 143_360, type: .image, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "share_wechat@2x.png",
                relativePath: "Assets.xcassets/share_wechat.imageset/share_wechat@2x.png",
                absolutePath: "", sizeBytes: 61_440, type: .image, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "ProfileCell.xib",
                relativePath: "Views/Profile/ProfileCell.xib",
                absolutePath: "", sizeBytes: 24_576, type: .xib, unreferenced: true,
                needsReview: true, note: "已加入 target 资源，但工程文本中没有出现名称，可能通过运行时拼接加载"
            ),
            ResourceItem(
                id: UUID(), name: "Onboarding.storyboard",
                relativePath: "Views/Onboarding/Onboarding.storyboard",
                absolutePath: "", sizeBytes: 88_064, type: .xib, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "LegacyDetailView.xib",
                relativePath: "Views/Legacy/LegacyDetailView.xib",
                absolutePath: "", sizeBytes: 31_744, type: .xib, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "OldHelper.swift",
                relativePath: "Utils/OldHelper.swift",
                absolutePath: "", sizeBytes: 12_288, type: .code, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "DeprecatedAPI.m",
                relativePath: "Utils/DeprecatedAPI.m",
                absolutePath: "", sizeBytes: 9_216, type: .code, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "OldEndpoint.swift",
                relativePath: "Networking/OldEndpoint.swift",
                absolutePath: "", sizeBytes: 6_144, type: .code, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "LegacyStore.h",
                relativePath: "Store/LegacyStore.h",
                absolutePath: "", sizeBytes: 3_072, type: .code, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "changelog_2023.md",
                relativePath: "Docs/changelog_2023.md",
                absolutePath: "", sizeBytes: 5_120, type: .other, unreferenced: true
            ),
            ResourceItem(
                id: UUID(), name: "strings_backup.strings",
                relativePath: "Resources/strings_backup.strings",
                absolutePath: "", sizeBytes: 11_264, type: .other, unreferenced: true
            ),
        ]
    }

    /// 代码 / XIB 类型的预览占位内容
    static var sampleSwiftCode: String {
        """
        import Foundation
        import UIKit

        /// 遗留的旧版分享助手 —— 已无人调用，仅供预览演示。
        final class OldShareHelper: NSObject {

            static let shared = OldShareHelper()

            private override init() { super.init() }

            func share(text: String, imageName: String?) {
                let activity = UIActivityViewController(
                    activityItems: [text],
                    applicationActivities: nil
                )
                let keyWindow = UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                    .first
                keyWindow?.rootViewController?.present(activity, animated: true)
            }

            func legacyImage(named name: String) -> UIImage? {
                return UIImage(named: name, in: .main, compatibleWith: nil)
            }
        }
        """
    }

    static var sampleXibXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0">
            <objects>
                <tableViewCell clipsSubviews="YES" contentMode="scaleToFill"
                    restorationIdentifier="ProfileCell" rowHeight="88" id="KGe-2T-xyz">
                    <rect key="frame" x="0.0" y="0.0" width="375" height="88"/>
                    <autoresizingMask key="autoresizingMask" flexibleMaxX="YES"/>
                    <tableViewCellContentView key="contentView" opaque="NO"
                        clipsSubviews="YES" id="H2p-sc-9uM">
                        <subviews>
                            <imageView userInteractionEnabled="NO" contentMode="scaleAspectFill"
                                image="avatar_placeholder" id="avatarView"/>
                            <label text="昵称" id="nameLabel"/>
                        </subviews>
                    </tableViewCellContentView>
                </tableViewCell>
            </objects>
            <resources>
                <image name="avatar_placeholder" width="120" height="120"/>
            </resources>
        </document>
        """
    }
}
