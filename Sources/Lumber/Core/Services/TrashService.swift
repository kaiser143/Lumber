import AppKit
import Foundation

// MARK: - 废纸篓
//
// 所有删除统一走 NSWorkspace.recycle，绝不直接 unlink。
// imageset 这类聚合条目删除的是整个目录（ResourceItem.directoryPath），而不是单张图片。

struct TrashFailure: Identifiable {
    let id = UUID()
    let item: ResourceItem
    let reason: String
}

struct TrashOutcome {
    /// 已成功移入废纸篓（或无需删除的演示条目）
    var trashedIDs: [UUID] = []
    /// 演示数据：没有磁盘路径，直接从列表移除
    var skippedIDs: [UUID] = []
    var failures: [TrashFailure] = []

    var removedIDs: [UUID] { trashedIDs + skippedIDs }
}

enum TrashService {
    static func recycle(_ items: [ResourceItem]) async -> TrashOutcome {
        var outcome = TrashOutcome()
        var pending: [(item: ResourceItem, url: URL)] = []
        var seen: Set<String> = []

        for item in items {
            guard !item.absolutePath.isEmpty else {
                outcome.skippedIDs.append(item.id)
                continue
            }
            let path = item.directoryPath ?? item.absolutePath
            guard FileManager.default.fileExists(atPath: path) else {
                outcome.failures.append(TrashFailure(
                    item: item,
                    reason: "目标已不存在，可能被外部移动或删除"
                ))
                continue
            }
            // 同一目录可能被多条条目指向（理论上不会，但保证只回收一次）
            guard seen.insert(path).inserted else {
                outcome.trashedIDs.append(item.id)
                continue
            }
            pending.append((item, URL(fileURLWithPath: path)))
        }

        guard !pending.isEmpty else { return outcome }

        do {
            let mappings = try await NSWorkspace.shared.recycle(pending.map(\.url))
            for (item, url) in pending {
                if mappings[url] != nil || !FileManager.default.fileExists(atPath: url.path) {
                    outcome.trashedIDs.append(item.id)
                } else {
                    outcome.failures.append(TrashFailure(item: item, reason: "系统拒绝了回收请求"))
                }
            }
        } catch {
            // 整批失败时逐个重试，定位真正失败的条目
            for (item, url) in pending {
                do {
                    _ = try await NSWorkspace.shared.recycle([url])
                    outcome.trashedIDs.append(item.id)
                } catch {
                    outcome.failures.append(TrashFailure(
                        item: item,
                        reason: error.localizedDescription
                    ))
                }
            }
        }

        return outcome
    }
}
