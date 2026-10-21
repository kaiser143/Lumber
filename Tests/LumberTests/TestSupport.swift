import Foundation

/// 临时目录辅助：每个测试自己创建、结束时清理，避免依赖仓库里的样例工程。
final class TempDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LumberTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func directory(_ path: String) throws -> URL {
        let target = url.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    @discardableResult
    func file(_ path: String, contents: String = "") throws -> URL {
        try write(path, content: Data(contents.utf8))
    }

    @discardableResult
    func data(_ path: String, data: Data) throws -> URL {
        try write(path, content: data)
    }

    /// 写入指定长度的占位二进制内容
    @discardableResult
    func bytes(_ path: String, count: Int) throws -> URL {
        try write(path, content: Data(repeating: 0xAB, count: count))
    }

    @discardableResult
    private func write(_ path: String, content: Data) throws -> URL {
        let target = url.appending(path: path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: target)
        return target
    }
}
