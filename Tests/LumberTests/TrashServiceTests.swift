import XCTest

@testable import Lumber

final class TrashServiceTests: XCTestCase {
    private func item(_ path: String) -> ResourceItem {
        ResourceItem(
            name: (path as NSString).lastPathComponent,
            relativePath: (path as NSString).lastPathComponent,
            absolutePath: path,
            sizeBytes: 1,
            type: .image,
            unreferenced: true
        )
    }

    /// 目标在工程根目录之外：必须判失败，且不得真的删掉文件
    func testRejectsTargetOutsideRoot() async throws {
        let project = try TempDirectory()
        let outside = try TempDirectory()
        let file = try outside.file("outside.png", contents: "x")

        let outcome = await TrashService.recycle([item(file.path)], rootDirectory: project.url)

        XCTAssertTrue(outcome.trashedIDs.isEmpty)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(outcome.failures[0].reason.contains("工程目录之外"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    /// 工程内的软链接指向外部：解析后越界，同样拒绝
    func testRejectsSymlinkEscapingRoot() async throws {
        let project = try TempDirectory()
        let outside = try TempDirectory()
        let target = try outside.file("outside.png", contents: "x")
        let link = project.url.appending(path: "escape.png")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)

        let outcome = await TrashService.recycle([item(link.path)], rootDirectory: project.url)

        XCTAssertTrue(outcome.trashedIDs.isEmpty)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(outcome.failures[0].reason.contains("工程目录之外"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
}
