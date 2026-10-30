import XCTest
@testable import Lumber

final class PBXProjCleanerTests: XCTestCase {
    private func sampleText() -> String {
        """
        {
          archiveVersion = 1;
          objects = {
            ROOT = { isa = PBXProject; targets = (TARGET); };
            TARGET = { isa = PBXNativeTarget; name = Demo; buildPhases = (SOURCES); };
            SOURCES = { isa = PBXSourcesBuildPhase; files = (BUILD_USED, BUILD_UNUSED); };
            BUILD_USED = { isa = PBXBuildFile; fileRef = USED; };
            BUILD_UNUSED = { isa = PBXBuildFile; fileRef = UNUSED; };
            USED = { isa = PBXFileReference; path = "App/Used.swift"; sourceTree = "<group>"; };
            UNUSED = { isa = PBXFileReference; path = "App/Unused.swift"; sourceTree = "<group>"; };
            ASSET = { isa = PBXFileReference; path = "App/Assets.xcassets"; sourceTree = "<group>"; lastKnownFileType = folder.assetcatalog; };
            GROUP = { isa = PBXGroup; children = (USED, UNUSED, ASSET); sourceTree = "<group>"; };
          };
          rootObject = ROOT;
        }
        """
    }

    func testRemovesFileReferenceAndBuildFile() throws {
        let temp = try TempDirectory()
        let projectURL = temp.url.appending(path: "Demo.xcodeproj")
        let unusedPath = temp.url.appending(path: "App/Unused.swift").path

        let result = try PBXProjCleaner.clean(
            pbxprojText: sampleText(),
            xcodeprojURL: projectURL,
            absolutePaths: [unusedPath]
        )

        XCTAssertEqual(result.outcome.removedObjectCount, 2) // UNUSED + BUILD_UNUSED
        XCTAssertEqual(result.outcome.cleanedPaths, [URL(fileURLWithPath: unusedPath).standardizedFileURL.path])
        XCTAssertFalse(result.text.contains("UNUSED = {"))
        XCTAssertFalse(result.text.contains("BUILD_UNUSED = {"))
        XCTAssertTrue(result.text.contains("USED = {"))
        XCTAssertTrue(result.text.contains("BUILD_USED = {"))
        XCTAssertFalse(result.text.contains("UNUSED,"))
        XCTAssertTrue(result.text.contains("USED"))
        // 仍可被解析
        let graph = try PBXProjectGraph.build(xcodeprojURL: projectURL, pbxprojText: result.text)
        XCTAssertFalse(graph.referencedPaths.contains(unusedPath))
        XCTAssertTrue(graph.referencedPaths.contains(temp.url.appending(path: "App/Used.swift").path))
    }

    func testSkipsAssetCatalogInnerEntries() throws {
        let temp = try TempDirectory()
        let projectURL = temp.url.appending(path: "Demo.xcodeproj")
        let imageset = temp.url.appending(path: "App/Assets.xcassets/orphan.imageset").path

        let result = try PBXProjCleaner.clean(
            pbxprojText: sampleText(),
            xcodeprojURL: projectURL,
            absolutePaths: [imageset]
        )

        XCTAssertEqual(result.outcome.removedObjectCount, 0)
        XCTAssertTrue(result.outcome.skippedPaths.contains(URL(fileURLWithPath: imageset).standardizedFileURL.path))
        XCTAssertTrue(result.text.contains("ASSET = {"))
    }

    /// 回归：旧实现的朴素花括号计数会被注释 / 字符串里的 `{` `}` 带偏，导致删错范围。
    func testRemovesObjectWithBracesInsideCommentsAndStrings() throws {
        let temp = try TempDirectory()
        let projectURL = temp.url.appending(path: "Demo.xcodeproj")
        let unusedPath = temp.url.appending(path: "App/Unused.swift").path

        let text = [
            "{",
            "\tarchiveVersion = 1;",
            "\tobjects = {",
            "\t\tROOT = { isa = PBXProject; };",
            "\t\tGROUP = { isa = PBXGroup; children = (USED, UNUSED); sourceTree = \"<group>\"; };",
            "\t\tUSED = { isa = PBXFileReference; path = \"App/Used.swift\"; sourceTree = \"<group>\"; };",
            "\t\t/* 注释里也有一个 { 花括号 */",
            "\t\tUNUSED = { isa = PBXFileReference; path = \"App/Unused.swift\"; sourceTree = \"<group>\";"
                + " settings = {COMPILER_FLAGS = \"-Wl,-segalign,{4000}\"}; };",
            "\t};",
            "\trootObject = ROOT;",
            "}",
        ].joined(separator: "\n")

        let result = try PBXProjCleaner.clean(
            pbxprojText: text,
            xcodeprojURL: projectURL,
            absolutePaths: [unusedPath]
        )

        XCTAssertEqual(result.outcome.removedObjectCount, 1)
        XCTAssertFalse(result.text.contains("UNUSED = {"))
        XCTAssertFalse(result.text.contains("UNUSED,"))
        XCTAssertTrue(result.text.contains("USED = {"))
        // 注释与无关对象必须原样保留
        XCTAssertTrue(result.text.contains("/* 注释里也有一个 { 花括号 */"))
        XCTAssertTrue(result.text.contains("ROOT = { isa = PBXProject; };"))

        let graph = try PBXProjectGraph.build(xcodeprojURL: projectURL, pbxprojText: result.text)
        XCTAssertFalse(graph.referencedPaths.contains(unusedPath))
        XCTAssertTrue(graph.referencedPaths.contains(temp.url.appending(path: "App/Used.swift").path))
    }

    /// 列表里只有一项时（`children = (UNUSED);`），删除后不能留下悬空引用。
    func testRemovesOnlyItemInList() throws {
        let temp = try TempDirectory()
        let projectURL = temp.url.appending(path: "Demo.xcodeproj")
        let text = [
            "{",
            "\tobjects = {",
            "\t\tGROUP = { isa = PBXGroup; children = (UNUSED); sourceTree = \"<group>\"; };",
            "\t\tUNUSED = { isa = PBXFileReference; path = \"Unused.png\"; sourceTree = \"<group>\"; };",
            "\t};",
            "\trootObject = ROOT;",
            "}",
        ].joined(separator: "\n")

        let result = try PBXProjCleaner.clean(
            pbxprojText: text,
            xcodeprojURL: projectURL,
            absolutePaths: [temp.url.appending(path: "Unused.png").path]
        )
        XCTAssertEqual(result.outcome.removedObjectCount, 1)
        XCTAssertFalse(result.text.contains("UNUSED"))
    }

    /// 备份保留的是「首次修改前」的原文，后续清理不得覆盖。
    func testBackupKeepsOriginalAcrossCleanups() throws {
        let temp = try TempDirectory()
        let projectURL = try temp.directory("Demo.xcodeproj")
        let pbxprojURL = projectURL.appending(path: "project.pbxproj")
        try Self.makePbxproj(with: ["UNUSED1", "UNUSED2"]).write(to: pbxprojURL, atomically: true, encoding: .utf8)
        let backupURL = pbxprojURL.appendingPathExtension("lumber-bak")

        _ = try PBXProjCleaner.removeReferences(
            xcodeprojURL: projectURL,
            absolutePaths: [temp.url.appending(path: "App/UNUSED1.swift").path]
        )
        let backup = try String(contentsOf: backupURL, encoding: .utf8)
        XCTAssertTrue(backup.contains("UNUSED1 = {"))
        XCTAssertTrue(backup.contains("UNUSED2 = {"))

        _ = try PBXProjCleaner.removeReferences(
            xcodeprojURL: projectURL,
            absolutePaths: [temp.url.appending(path: "App/UNUSED2.swift").path]
        )
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), backup)
        let current = try String(contentsOf: pbxprojURL, encoding: .utf8)
        XCTAssertFalse(current.contains("UNUSED1 = {"))
        XCTAssertFalse(current.contains("UNUSED2 = {"))
    }

    /// UTF-16 工程写回后必须仍是 UTF-16，不能被改写成 UTF-8。
    func testWriteBackPreservesUTF16Encoding() throws {
        let temp = try TempDirectory()
        let projectURL = try temp.directory("Demo.xcodeproj")
        let pbxprojURL = projectURL.appending(path: "project.pbxproj")
        let body = Self.makePbxproj(with: ["USED", "UNUSED"]).data(using: .utf16LittleEndian)!
        try (Data([0xFF, 0xFE]) + body).write(to: pbxprojURL, options: .atomic)

        _ = try PBXProjCleaner.removeReferences(
            xcodeprojURL: projectURL,
            absolutePaths: [temp.url.appending(path: "App/UNUSED.swift").path]
        )

        let data = try Data(contentsOf: pbxprojURL)
        XCTAssertTrue(data.starts(with: Data([0xFF, 0xFE])), "BOM 必须保留")
        let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        XCTAssertNotNil(text)
        XCTAssertFalse(text?.contains("UNUSED = {") ?? true)
        XCTAssertTrue(text?.contains("USED = {") ?? false)
    }

    private static func makePbxproj(with ids: [String]) -> String {
        let entries = ids.map {
            "\t\t\($0) = { isa = PBXFileReference; path = \"App/\($0).swift\"; sourceTree = \"<group>\"; };"
        }
        return (["{", "\tarchiveVersion = 1;", "\tobjects = {"] + entries + ["\t};", "}"])
            .joined(separator: "\n")
    }

    func testDoesNotTouchUnrelatedAssetCatalogRef() throws {
        let temp = try TempDirectory()
        let projectURL = temp.url.appending(path: "Demo.xcodeproj")
        let assetPath = temp.url.appending(path: "App/Assets.xcassets").path

        let result = try PBXProjCleaner.clean(
            pbxprojText: sampleText(),
            xcodeprojURL: projectURL,
            absolutePaths: [assetPath]
        )

        XCTAssertEqual(result.outcome.removedObjectCount, 1) // sample 里 ASSET 没有对应 PBXBuildFile
        XCTAssertTrue(result.outcome.cleanedPaths.contains(URL(fileURLWithPath: assetPath).standardizedFileURL.path))
        XCTAssertFalse(result.text.contains("ASSET = {"))
    }
}
