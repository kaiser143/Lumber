import XCTest
@testable import Lumber

final class IgnoreRuleSetTests: XCTestCase {
    func testDirectoryRuleMatchesAnyDepth() {
        let rules = IgnoreRuleSet(patterns: ["Pods/"])
        XCTAssertTrue(rules.isIgnored(relativePath: "Pods", isDirectory: true))
        XCTAssertTrue(rules.isIgnored(relativePath: "App/Pods", isDirectory: true))
        XCTAssertFalse(rules.isIgnored(relativePath: "Vendor/Podspecs", isDirectory: true))
        XCTAssertFalse(rules.isIgnored(relativePath: "Pods", isDirectory: false))
    }

    func testRootAnchoredRule() {
        let rules = IgnoreRuleSet(patterns: ["/build/"])
        XCTAssertTrue(rules.isIgnored(relativePath: "build", isDirectory: true))
        XCTAssertFalse(rules.isIgnored(relativePath: "App/build", isDirectory: true))
    }

    func testWildcardDoesNotCrossDirectories() {
        let rules = IgnoreRuleSet(patterns: ["Debug/*.png"])
        XCTAssertTrue(rules.isIgnored(relativePath: "Debug/icon.png", isDirectory: false))
        XCTAssertFalse(rules.isIgnored(relativePath: "Debug/sub/icon.png", isDirectory: false))
        XCTAssertFalse(rules.isIgnored(relativePath: "Other/Debug/icon.png", isDirectory: false))
    }

    func testDoubleStarCrossesDirectories() {
        let rules = IgnoreRuleSet(patterns: ["**/fixtures/*.snap"])
        XCTAssertTrue(rules.isIgnored(relativePath: "fixtures/a.snap", isDirectory: false))
        XCTAssertTrue(rules.isIgnored(relativePath: "Tests/fixtures/a.snap", isDirectory: false))
    }

    func testNegationLastWins() {
        let rules = IgnoreRuleSet(patterns: ["*.png", "!keep.png"])
        XCTAssertTrue(rules.isIgnored(relativePath: "a/icon.png", isDirectory: false))
        XCTAssertFalse(rules.isIgnored(relativePath: "a/keep.png", isDirectory: false))
    }

    func testCaseInsensitive() {
        let rules = IgnoreRuleSet(patterns: ["*.PNG"])
        XCTAssertTrue(rules.isIgnored(relativePath: "Images/Icon.png", isDirectory: false))
    }

    func testCommentsAndEmptyLinesAreIgnored() {
        let rules = IgnoreRuleSet(patterns: ["", "# 注释", "  ", "*.md"])
        XCTAssertTrue(rules.isIgnored(relativePath: "README.md", isDirectory: false))
        XCTAssertFalse(rules.isIgnored(relativePath: "README.txt", isDirectory: false))
    }

    func testBuiltInRules() {
        let rules = IgnoreRuleSet(patterns: IgnoreRule.builtIn.map(\.pattern))
        XCTAssertTrue(rules.isIgnored(relativePath: "Pods", isDirectory: true))
        XCTAssertTrue(rules.isIgnored(relativePath: "DerivedData", isDirectory: true))
        XCTAssertTrue(rules.isIgnored(relativePath: "fastlane", isDirectory: true))
    }
}
