import XCTest
@testable import Lumber

final class ScanEngineTests: XCTestCase {
    func testScanCollectsLooseImagesAssetsAndBuildState() async throws {
        let temp = try TempDirectory()

        // 代码：Used.swift 已加入构建；Orphan.swift 只在工程导航器中
        try temp.file("App/Used.swift", contents: #"let image = UIImage(named: "used")"#)
        try temp.file("App/Orphan.swift", contents: "struct OrphanView {}")

        // 资源目录：used 被代码引用；color / data 未引用
        try temp.bytes("App/Assets.xcassets/used.imageset/used.png", count: 64)
        try temp.file("App/Assets.xcassets/used.imageset/Contents.json", contents: #"{ "images" : [ { "filename" : "used.png", "idiom" : "universal", "scale" : "1x" } ] }"#)
        try temp.file("App/Assets.xcassets/unused.colorset/Contents.json", contents: #"{ "colors" : [ { "idiom" : "universal" } ] }"#)
        try temp.bytes("App/Assets.xcassets/unused.dataset/unused.pdf", count: 32)
        try temp.file("App/Assets.xcassets/unused.dataset/Contents.json", contents: #"{ "data" : [ { "filename" : "unused.pdf", "idiom" : "universal" } ] }"#)

        // 蓝色文件夹里的散落图片：可能被运行时按路径读取
        try temp.bytes("App/Resources/hero.png", count: 48)

        let root = temp.url.standardizedFileURL
        let usedPath = root.appending(path: "App/Used.swift").path
        let orphanPath = root.appending(path: "App/Orphan.swift").path
        let resourcesPath = root.appending(path: "App/Resources").path

        let project = ProjectInfo(
            xcodeprojURL: root.appending(path: "Sample.xcodeproj"),
            name: "Sample",
            rootDirectory: root,
            targets: ["Sample"],
            referencedPaths: [usedPath, orphanPath, resourcesPath],
            builtPaths: [usedPath],
            folderReferencePaths: [resourcesPath],
            synchronizedRootPaths: [],
            assetCatalogs: [],
            mainStoryboardName: nil,
            referencedResourceNames: [],
            fileReferenceCount: 0,
            linkedProjects: []
        )

        let outcome = await ScanEngine().scan(
            project: project,
            rules: IgnoreRuleSet(patterns: []),
            options: ScanOptions()
        ) { _ in }

        let byPath = Dictionary(uniqueKeysWithValues: outcome.items.map { ($0.relativePath, $0) })

        let used = try XCTUnwrap(byPath["App/Assets.xcassets/used.imageset"])
        XCTAssertFalse(used.unreferenced)

        let color = try XCTUnwrap(byPath["App/Assets.xcassets/unused.colorset"])
        XCTAssertEqual(color.type, .color)
        XCTAssertTrue(color.unreferenced)

        let data = try XCTUnwrap(byPath["App/Assets.xcassets/unused.dataset"])
        XCTAssertEqual(data.type, .data)
        XCTAssertTrue(data.unreferenced)

        let hero = try XCTUnwrap(byPath["App/Resources/hero.png"])
        XCTAssertEqual(hero.type, .image)
        XCTAssertTrue(hero.needsReview, "整目录引用里的散落图片应进入待确认")

        let orphan = try XCTUnwrap(byPath["App/Orphan.swift"])
        XCTAssertTrue(orphan.notInTarget, "在工程里但没加入构建阶段的代码应标记为未加入 target")

        let usedCode = try XCTUnwrap(byPath["App/Used.swift"])
        XCTAssertFalse(usedCode.unreferenced)
    }

    func testScanHonorsIgnoreRulesForAssetEntries() async throws {
        let temp = try TempDirectory()
        try temp.file("App/Assets.xcassets/skip.colorset/Contents.json", contents: #"{ "colors" : [] }"#)
        try temp.file("App/Assets.xcassets/keep.colorset/Contents.json", contents: #"{ "colors" : [] }"#)

        let root = temp.url.standardizedFileURL
        let project = ProjectInfo(
            xcodeprojURL: root.appending(path: "Sample.xcodeproj"),
            name: "Sample",
            rootDirectory: root,
            targets: [],
            referencedPaths: [],
            builtPaths: [],
            folderReferencePaths: [],
            synchronizedRootPaths: [],
            assetCatalogs: [],
            mainStoryboardName: nil,
            referencedResourceNames: [],
            fileReferenceCount: 0,
            linkedProjects: []
        )

        let outcome = await ScanEngine().scan(
            project: project,
            rules: IgnoreRuleSet(patterns: ["skip.colorset/"]),
            options: ScanOptions()
        ) { _ in }

        let names = Set(outcome.items.map(\.name))
        XCTAssertFalse(names.contains("skip"))
        XCTAssertTrue(names.contains("keep"))
        XCTAssertGreaterThan(outcome.ignoredCount, 0)
    }
}
