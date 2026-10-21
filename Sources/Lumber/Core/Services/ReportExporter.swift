import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - 扫描报告导出
//
// 导出当前筛选 / 搜索结果的 CSV（UTF-8 with BOM，Excel 直接打开不乱码）。
// CSV 生成逻辑与磁盘面板分开，便于单元测试转义规则。

enum CSVWriter {
    static let header = ["名称", "类型", "状态", "相对路径", "大小(字节)", "大小", "判定说明"]

    static func report(items: [ResourceItem]) -> String {
        var lines = [line(header)]
        for item in items {
            lines.append(line([
                item.name,
                item.type.rawValue,
                item.statusText,
                item.relativePath,
                String(item.sizeBytes),
                item.sizeText,
                item.note ?? "",
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

@MainActor
enum ReportExporter {
    enum ExportError: LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let reason):
                return "报告写入失败：\(reason)"
            }
        }
    }

    /// 弹出保存面板并写入；用户取消时返回 nil
    static func export(items: [ResourceItem], projectName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "导出扫描报告"
        panel.message = "导出当前筛选 / 搜索结果（CSV，可用 Excel / Numbers 打开）"
        panel.prompt = "导出"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = fileName(for: projectName)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let csv = "\u{FEFF}" + CSVWriter.report(items: items)
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
    }

    private static func fileName(for projectName: String) -> String {
        let base = projectName
            .replacingOccurrences(of: ".xcodeproj", with: "")
            .replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: Date())
        return "Lumber-\(base)-\(stamp).csv"
    }
}
