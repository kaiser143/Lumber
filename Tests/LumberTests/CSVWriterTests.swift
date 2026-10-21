import XCTest
@testable import Lumber

final class CSVWriterTests: XCTestCase {
    func testEscapePlainValue() {
        XCTAssertEqual(CSVWriter.escape("plain"), "plain")
    }

    func testEscapeCommaQuoteAndNewline() {
        XCTAssertEqual(CSVWriter.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVWriter.escape("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(CSVWriter.escape("a\nb"), "\"a\nb\"")
        XCTAssertEqual(CSVWriter.escape("a\rb"), "\"a\rb\"")
    }

    func testReportContainsHeaderAndStatus() {
        let item = ResourceItem(
            name: "hero_banner",
            relativePath: "Assets.xcassets/hero_banner.imageset",
            absolutePath: "/tmp/hero.png",
            sizeBytes: 1_500_000,
            type: .image,
            unreferenced: true,
            note: "名称, 含逗号\n以及换行"
        )
        let csv = CSVWriter.report(items: [item])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.first.map(String.init), CSVWriter.line(CSVWriter.header))
        XCTAssertTrue(csv.contains("高置信度未引用"))
        XCTAssertTrue(csv.contains("1.5 MB"))
        XCTAssertTrue(csv.contains("\"名称, 含逗号\n以及换行\""))
    }

    func testNotInTargetStatus() {
        let item = ResourceItem(
            name: "Orphan.swift",
            relativePath: "App/Orphan.swift",
            absolutePath: "/tmp/Orphan.swift",
            sizeBytes: 10,
            type: .code,
            unreferenced: true,
            needsReview: true,
            notInTarget: true
        )
        XCTAssertEqual(item.statusText, "未加入 target")
        XCTAssertTrue(CSVWriter.report(items: [item]).contains("未加入 target"))
    }
}
