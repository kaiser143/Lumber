import XCTest
@testable import Lumber

final class ReferenceJudgeTests: XCTestCase {
    private func makeProject(
        root: URL,
        referenced: Set<String> = [],
        built: Set<String> = [],
        folders: [String] = [],
        syncRoots: [String] = [],
        names: Set<String> = []
    ) -> ProjectInfo {
        ProjectInfo(
            xcodeprojURL: root.appending(path: "Demo.xcodeproj"),
            name: "Demo",
            rootDirectory: root,
            targets: ["Demo"],
            referencedPaths: referenced,
            builtPaths: built,
            folderReferencePaths: folders,
            synchronizedRootPaths: syncRoots,
            assetCatalogs: [],
            mainStoryboardName: nil,
            referencedResourceNames: names,
            fileReferenceCount: 0,
            linkedProjects: []
        )
    }

    private func makeIndex(_ texts: [String]) -> ReferenceIndex {
        var builder = ReferenceIndexBuilder()
        for text in texts { builder.addText(text) }
        return builder.build()
    }

    private func assetCandidate(name: String, root: URL) -> ScanCandidate {
        let directory = root.appending(path: "Assets.xcassets/\(name).imageset", directoryHint: .isDirectory)
        return ScanCandidate(
            name: name,
            relativePath: "Assets.xcassets/\(name).imageset",
            absolutePath: directory.appending(path: "\(name).png").path,
            sizeBytes: 100,
            type: .image,
            directoryPath: directory.path,
            keys: [name],
            kind: .asset
        )
    }

    private func codeCandidate(name: String, root: URL) -> ScanCandidate {
        let path = root.appending(path: "App/\(name).swift")
        return ScanCandidate(
            name: "\(name).swift",
            relativePath: "App/\(name).swift",
            absolutePath: path.path,
            sizeBytes: 100,
            type: .code,
            directoryPath: nil,
            keys: [name],
            kind: .code
        )
    }

    private func looseCandidate(name: String, root: URL) -> ScanCandidate {
        let path = root.appending(path: "Resources/\(name).png")
        return ScanCandidate(
            name: name,
            relativePath: "Resources/\(name).png",
            absolutePath: path.path,
            sizeBytes: 100,
            type: .image,
            directoryPath: nil,
            keys: [name],
            kind: .looseImage
        )
    }

    func testAssetReferencedByName() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let project = makeProject(root: root)
        let judge = ReferenceJudge(project: project, index: makeIndex([#"Image("hero")"#]))
        guard case .referenced = judge.verdict(for: assetCandidate(name: "hero", root: root)) else {
            return XCTFail("代码里出现资源名应判定为已引用")
        }
    }

    func testAssetOnlyInCommentIsUncertain() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let project = makeProject(root: root)
        let judge = ReferenceJudge(project: project, index: makeIndex(["// hero 已经废弃"]))
        guard case .uncertain = judge.verdict(for: assetCandidate(name: "hero", root: root)) else {
            return XCTFail("只出现在注释里应判定为待确认")
        }
    }

    func testAssetReferencedButNotBuiltIsNotInTarget() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let catalog = root.appending(path: "Assets.xcassets").path
        let project = makeProject(root: root, referenced: [catalog], folders: [catalog])
        let judge = ReferenceJudge(project: project, index: makeIndex([]))
        guard case .notInTarget = judge.verdict(for: assetCandidate(name: "hero", root: root)) else {
            return XCTFail("资源目录没有加入构建阶段应判定为未加入 target")
        }
    }

    func testAssetNamedInCodeButCatalogNotBuiltIsNotInTarget() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let catalog = root.appending(path: "Assets.xcassets").path
        let project = makeProject(root: root, referenced: [catalog], folders: [catalog])
        let judge = ReferenceJudge(project: project, index: makeIndex([#"Image("hero")"#]))
        guard case .notInTarget = judge.verdict(for: assetCandidate(name: "hero", root: root)) else {
            return XCTFail("资源名在代码里出现，但目录没有加入 Copy Bundle Resources，仍应提示未加入 target")
        }
    }

    func testAssetBuiltButUnnamedIsUnused() {        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let catalog = root.appending(path: "Assets.xcassets").path
        let project = makeProject(root: root, referenced: [catalog], built: [catalog], folders: [catalog])
        let judge = ReferenceJudge(project: project, index: makeIndex([]))
        guard case .unused = judge.verdict(for: assetCandidate(name: "hero", root: root)) else {
            return XCTFail("已加入构建阶段但工程文本没有名称，应判定为高置信度未引用")
        }
    }

    func testLooseImageInFolderReferenceIsUncertain() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let resources = root.appending(path: "Resources").path
        let project = makeProject(root: root, referenced: [resources], folders: [resources])
        let judge = ReferenceJudge(project: project, index: makeIndex([]))
        guard case .uncertain = judge.verdict(for: looseCandidate(name: "hero", root: root)) else {
            return XCTFail("整目录引用里的散落图片可能被运行时按路径读取，应判定为待确认")
        }
    }

    func testLooseImageOutsideFolderReferenceIsUnused() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let project = makeProject(root: root)
        let judge = ReferenceJudge(project: project, index: makeIndex([]))
        guard case .unused = judge.verdict(for: looseCandidate(name: "hero", root: root)) else {
            return XCTFail("工程文本里没有出现的散落图片应判定为未引用")
        }
    }

    func testCodeBuiltIsReferenced() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let path = root.appending(path: "App/Used.swift").path
        let project = makeProject(root: root, referenced: [path], built: [path])
        let judge = ReferenceJudge(project: project, index: makeIndex([]))
        guard case .referenced = judge.verdict(for: codeCandidate(name: "Used", root: root)) else {
            return XCTFail("加入 target 编译阶段的代码文件应判定为已引用")
        }
    }

    func testCodeReferencedButNotBuiltIsNotInTarget() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let path = root.appending(path: "App/OrphanView.swift").path
        let project = makeProject(root: root, referenced: [path])
        let judge = ReferenceJudge(project: project, index: makeIndex([]))
        guard case .notInTarget = judge.verdict(for: codeCandidate(name: "OrphanView", root: root)) else {
            return XCTFail("在工程里但没加入编译阶段，应判定为未加入 target")
        }
    }

    func testCodeNotReferencedButUsedElsewhereIsReferenced() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let project = makeProject(root: root)
        let judge = ReferenceJudge(
            project: project,
            index: makeIndex(["final class Child: OrphanView {}", "let view = OrphanView()"])
        )
        guard case .referenced = judge.verdict(for: codeCandidate(name: "OrphanView", root: root)) else {
            return XCTFail("类型名被其他文件使用，应判定为已引用")
        }
    }

    func testCodeUnreferencedAndUnusedIsUnused() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let project = makeProject(root: root)
        let judge = ReferenceJudge(project: project, index: makeIndex(["let unrelated = 1"]))
        guard case .unused = judge.verdict(for: codeCandidate(name: "OrphanView", root: root)) else {
            return XCTFail("没有构建引用也没有类型使用，应判定为未引用")
        }
    }

    func testMakeItemMapsNotInTarget() {
        let root = URL(fileURLWithPath: "/tmp/LumberJudge")
        let candidate = codeCandidate(name: "OrphanView", root: root)
        let item = ScanEngine.makeItem(from: candidate, verdict: .notInTarget("未加入 target"))
        XCTAssertTrue(item.unreferenced)
        XCTAssertTrue(item.needsReview)
        XCTAssertTrue(item.notInTarget)
        XCTAssertFalse(item.isConfirmedUnused)
        XCTAssertEqual(item.statusText, "未加入 target")
    }
}
