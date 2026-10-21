import XCTest
@testable import Lumber

final class PBXProjectGraphTests: XCTestCase {
    private func makeProjectText(projectDirPath: String = "") -> String {
        """
        {
          archiveVersion = 1;
          objects = {
            ROOT = { isa = PBXProject; targets = (TARGET); \(projectDirPath.isEmpty ? "" : "projectDirPath = \"\(projectDirPath)\";") };
            TARGET = { isa = PBXNativeTarget; name = Demo; buildPhases = (SOURCES, RESOURCES); };
            SOURCES = { isa = PBXSourcesBuildPhase; files = (BUILD_CODE); };
            RESOURCES = { isa = PBXResourcesBuildPhase; files = (BUILD_ASSET, BUILD_FOLDER, BUILD_VARIANT); };
            BUILD_CODE = { isa = PBXBuildFile; fileRef = CODE; };
            BUILD_ASSET = { isa = PBXBuildFile; fileRef = ASSET; };
            BUILD_FOLDER = { isa = PBXBuildFile; fileRef = FOLDER; };
            BUILD_VARIANT = { isa = PBXBuildFile; fileRef = VARIANT; };
            CODE = { isa = PBXFileReference; path = "App/Used.swift"; sourceTree = "<group>"; };
            UNBUILT = { isa = PBXFileReference; path = "App/Unused.swift"; sourceTree = "<group>"; };
            ASSET = { isa = PBXFileReference; path = "App/Assets.xcassets"; sourceTree = "<group>"; lastKnownFileType = folder.assetcatalog; };
            FOLDER = { isa = PBXFileReference; path = "App/Resources"; sourceTree = "<group>"; lastKnownFileType = folder; };
            VARIANT = { isa = PBXVariantGroup; children = (EN, ZH); sourceTree = "<group>"; };
            EN = { isa = PBXFileReference; path = "en.lproj/Localizable.strings"; sourceTree = "<group>"; };
            ZH = { isa = PBXFileReference; path = "zh-Hans.lproj/Localizable.strings"; sourceTree = "<group>"; };
            SYNC = { isa = PBXFileSystemSynchronizedRootGroup; path = Sync; sourceTree = "<group>"; };
            GROUP = { isa = PBXGroup; children = (CODE, UNBUILT, ASSET, FOLDER, VARIANT, SYNC); sourceTree = "<group>"; };
          };
          rootObject = ROOT;
        }
        """
    }

    func testBuildPhasesFolderReferencesAndSyncRoots() throws {
        let temp = try TempDirectory()
        let projectURL = temp.url.appending(path: "Demo.xcodeproj")
        let graph = try PBXProjectGraph.build(
            xcodeprojURL: projectURL,
            pbxprojText: makeProjectText()
        )

        let root = temp.url.standardizedFileURL
        XCTAssertEqual(graph.projectName, "Demo")
        XCTAssertEqual(graph.targets, ["Demo"])
        XCTAssertEqual(graph.fileReferenceCount, 6)
        XCTAssertEqual(graph.rootDirectory, root)

        let usedPath = root.appending(path: "App/Used.swift").path
        let unbuiltPath = root.appending(path: "App/Unused.swift").path
        let folderPath = root.appending(path: "App/Resources").path
        let assetPath = root.appending(path: "App/Assets.xcassets").path
        let syncPath = root.appending(path: "Sync").path

        XCTAssertTrue(graph.referencedPaths.contains(usedPath))
        XCTAssertTrue(graph.referencedPaths.contains(unbuiltPath))
        XCTAssertTrue(graph.referencedPaths.contains(syncPath))

        XCTAssertTrue(graph.builtPaths.contains(usedPath))
        XCTAssertFalse(graph.builtPaths.contains(unbuiltPath))
        XCTAssertTrue(graph.builtPaths.contains(folderPath))
        XCTAssertTrue(graph.builtPaths.contains(assetPath))
        XCTAssertTrue(graph.builtPaths.contains(root.appending(path: "en.lproj/Localizable.strings").path))
        XCTAssertTrue(graph.builtPaths.contains(root.appending(path: "zh-Hans.lproj/Localizable.strings").path))

        XCTAssertTrue(graph.folderReferencePaths.contains(folderPath))
        XCTAssertTrue(graph.folderReferencePaths.contains(assetPath))
        XCTAssertTrue(graph.folderReferencePaths.contains(syncPath))
        XCTAssertEqual(Set(graph.synchronizedRootPaths), Set([syncPath]))
        XCTAssertEqual(graph.assetCatalogURLs.map(\.standardizedFileURL.path), [assetPath])
    }

    func testProjectDirPathChangesRootDirectory() throws {
        let temp = try TempDirectory()
        let projectURL = temp.url.appending(path: "Demo.xcodeproj")
        let graph = try PBXProjectGraph.build(
            xcodeprojURL: projectURL,
            pbxprojText: makeProjectText(projectDirPath: "Sub")
        )
        let expectedRoot = temp.url.appending(path: "Sub").standardizedFileURL
        XCTAssertEqual(graph.rootDirectory, expectedRoot)
        XCTAssertTrue(graph.referencedPaths.contains(expectedRoot.appending(path: "App/Used.swift").path))
    }

    func testBuiltFilePathsIgnoreMissingObjects() throws {
        let temp = try TempDirectory()
        let text = """
        {
          objects = {
            ROOT = { isa = PBXProject; targets = (); };
            BROKEN = { isa = PBXBuildFile; fileRef = MISSING; };
          };
          rootObject = ROOT;
        }
        """
        let graph = try PBXProjectGraph.build(
            xcodeprojURL: temp.url.appending(path: "Broken.xcodeproj"),
            pbxprojText: text
        )
        XCTAssertTrue(graph.builtPaths.isEmpty)
        XCTAssertTrue(graph.targets.isEmpty)
    }
}
