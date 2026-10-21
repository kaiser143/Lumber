import XCTest
@testable import Lumber

final class ProjectResolverTests: XCTestCase {
    func testDirectoryWithMultipleProjectsReturnsAllSorted() throws {
        let temp = try TempDirectory()
        try temp.directory("B.xcodeproj")
        try temp.directory("A.xcodeproj")

        let candidates = try ProjectResolver.resolveCandidates(temp.url)
        XCTAssertEqual(candidates.map(\.lastPathComponent), ["A.xcodeproj", "B.xcodeproj"])
        XCTAssertEqual(try ProjectResolver.resolve(temp.url).lastPathComponent, "A.xcodeproj")
    }

    func testDependencyDirectoriesAreSkipped() throws {
        let temp = try TempDirectory()
        try temp.directory("App/App.xcodeproj")
        try temp.directory("Pods/Pods.xcodeproj")
        try temp.directory("Carthage/Carthage.xcodeproj")

        let candidates = try ProjectResolver.resolveCandidates(temp.url)
        XCTAssertEqual(candidates.map(\.lastPathComponent), ["App.xcodeproj"])
    }

    func testWorkspaceFiltersPodsAndResolvesApp() throws {
        let temp = try TempDirectory()
        try temp.file("App/App.xcodeproj/project.pbxproj", contents: "{}")
        try temp.file("Pods/Pods.xcodeproj/project.pbxproj", contents: "{}")
        let workspace = try temp.directory("Demo.xcworkspace")
        try temp.file("Demo.xcworkspace/contents.xcworkspacedata", contents: """
        <?xml version="1.0" encoding="UTF-8"?>
        <Workspace version = "1.0">
           <FileRef location = "group:App/App.xcodeproj"></FileRef>
           <FileRef location = "group:Pods/Pods.xcodeproj"></FileRef>
        </Workspace>
        """)

        let candidates = try ProjectResolver.resolveCandidates(workspace)
        XCTAssertEqual(candidates.map(\.lastPathComponent), ["App.xcodeproj"])

        // 目录里只有 workspace 时也应能解析
        let fromDirectory = try ProjectResolver.resolveCandidates(temp.url)
        XCTAssertEqual(fromDirectory.map(\.lastPathComponent), ["App.xcodeproj"])
    }

    func testWorkspaceWithTwoProjectsReturnsBoth() throws {
        let temp = try TempDirectory()
        try temp.file("A/A.xcodeproj/project.pbxproj", contents: "{}")
        try temp.file("B/B.xcodeproj/project.pbxproj", contents: "{}")
        let workspace = try temp.directory("All.xcworkspace")
        try temp.file("All.xcworkspace/contents.xcworkspacedata", contents: """
        <?xml version="1.0" encoding="UTF-8"?>
        <Workspace version = "1.0">
           <FileRef location = "group:A/A.xcodeproj"></FileRef>
           <FileRef location = "group:B/B.xcodeproj"></FileRef>
        </Workspace>
        """)

        let candidates = try ProjectResolver.resolveCandidates(workspace)
        XCTAssertEqual(Set(candidates.map(\.lastPathComponent)), Set(["A.xcodeproj", "B.xcodeproj"]))
    }

    func testProjectPackageReturnsItself() throws {
        let temp = try TempDirectory()
        let project = try temp.directory("Solo.xcodeproj")
        let candidates = try ProjectResolver.resolveCandidates(project)
        XCTAssertEqual(candidates.map(\.standardizedFileURL.path), [project.standardizedFileURL.path])
    }

    func testUnsupportedAndMissingInputsThrow() throws {
        let temp = try TempDirectory()
        let textFile = try temp.file("notes.txt", contents: "hello")
        XCTAssertThrowsError(try ProjectResolver.resolveCandidates(textFile)) { error in
            guard let dropError = error as? ProjectDropError,
                  case .unsupportedType = dropError else {
                return XCTFail("普通文件应报 unsupportedType，实际：\(error)")
            }
        }

        let empty = try temp.directory("Empty")
        XCTAssertThrowsError(try ProjectResolver.resolveCandidates(empty)) { error in
            guard let dropError = error as? ProjectDropError,
                  case .emptyDirectory = dropError else {
                return XCTFail("空目录应报 emptyDirectory，实际：\(error)")
            }
        }

        let missing = temp.url.appending(path: "Missing.xcodeproj")
        XCTAssertThrowsError(try ProjectResolver.resolveCandidates(missing)) { error in
            guard let dropError = error as? ProjectDropError,
                  case .missingProject = dropError else {
                return XCTFail("不存在的路径应报 missingProject，实际：\(error)")
            }
        }
    }
}
