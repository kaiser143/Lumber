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

    func testEscapeNeutralizesFormulaInjection() {
        // CWE-1236：名称/路径来自被扫描工程，必须以单引号中和，否则表格软件会执行
        XCTAssertEqual(CSVWriter.escape("=cmd|'/c calc'!A1"), "'=cmd|'/c calc'!A1")
        XCTAssertEqual(CSVWriter.escape("+1+1"), "'+1+1")
        XCTAssertEqual(CSVWriter.escape("-2+3"), "'-2+3")
        XCTAssertEqual(CSVWriter.escape("@SUM(A1)"), "'@SUM(A1)")
        XCTAssertEqual(CSVWriter.escape("\t=1"), "'\t=1")
        // 需要加引号时，单引号在包裹引号内部
        XCTAssertEqual(CSVWriter.escape("=A1,B1"), "\"'=A1,B1\"")
        XCTAssertEqual(CSVWriter.escape("=say \"hi\""), "\"'=say \"\"hi\"\"\"")
        XCTAssertEqual(CSVWriter.escape(""), "")
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
