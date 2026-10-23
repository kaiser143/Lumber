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
