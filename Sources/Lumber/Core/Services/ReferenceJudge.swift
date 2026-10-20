import Foundation

// MARK: - 扫描候选
//
// 清单遍历阶段产生的「候选资源」原始数据；判定阶段再补上未引用状态与置信度。

struct ScanCandidate: Sendable {
    enum Kind: Sendable {
        /// 代码文件：只看是否被 pbxproj 引用
        case code
        /// strings 等随包资源：pbxproj 引用或名称出现即算使用
        case bundled
        /// xib / storyboard：名称需出现在代码、其他界面文件或 Info.plist 配置里
        case interface
        /// Assets.xcassets 中的 imageset：整目录聚合成一条，按 imageset 名匹配
        case imageSet
        /// 散落在 bundle 里的图片文件
        case looseImage
    }

    var name: String
    var relativePath: String
    var absolutePath: String
    var sizeBytes: Int
    var type: ResourceType
    var directoryPath: String?
    /// 用于在文本索引里查的名字（已去掉扩展名、@2x 等变体）
    var keys: [String]
    var kind: Kind
}

// MARK: - 判定结果

enum ReferenceVerdict: Sendable {
    /// 确认被引用，不进列表
    case referenced(String)
    /// 疑似冗余，但存在模糊信号，标记「待确认」
    case uncertain(String)
    /// 高置信度冗余
    case unused(String)
}

// MARK: - 引用判定
//
// 原则：宁漏勿删 —— 只有「工程文本里完全找不到这个名称」才给出高置信度未引用；
// 名称只出现在注释、只出现了名称片段（可能是拼接字符串）、或已加入 target 但没有名称引用时，
// 一律标记为「待确认」。

struct ReferenceJudge {
    let project: ProjectInfo
    let index: ReferenceIndex

    func verdict(for candidate: ScanCandidate) -> ReferenceVerdict {
        switch candidate.kind {
        case .code:
            return judgeCode(candidate)
        case .bundled:
            return judgeBundled(candidate)
        case .interface:
            return judgeInterface(candidate)
        case .imageSet:
            return judgeImageSet(candidate)
        case .looseImage:
            return judgeLooseImage(candidate)
        }
    }

    // MARK: - 各类型

    /// 代码文件：先看是否登记在工程编译清单里，再看文件里声明的类型有没有被别的文件用到
    ///
    /// 代码文件不按「有没有实例化」判定：基类、协议、只做类型标注的模型都不会被 new，
    /// 但只要它们的名字出现在另一个源文件里（继承、遵循、属性/参数类型），就是有效引用。
    private func judgeCode(_ candidate: ScanCandidate) -> ReferenceVerdict {
        if project.isReferenced(candidate.absolutePath) {
            return .referenced("已纳入工程编译")
        }
        if index.isUsedInOtherDocuments(anyOf: candidate.keys) {
            return .referenced("文件里声明的类型被其他源文件使用（基类 / 协议 / 类型引用）")
        }
        if index.isMentionedInOtherDocuments(anyOf: candidate.keys) {
            return .uncertain("既不在工程编译清单中，类型名也只出现在其他文件的注释里")
        }
        return .unused("未出现在任何工程的编译清单中，且没有其他文件使用其中声明的类型")
    }

    private func judgeBundled(_ candidate: ScanCandidate) -> ReferenceVerdict {
        if project.isReferenced(candidate.absolutePath) {
            return .referenced("已加入 target 资源")
        }
        if index.containsStrict(anyOf: candidate.keys) {
            return .referenced("代码中引用了该名称")
        }
        if index.containsLoose(anyOf: candidate.keys) {
            return .uncertain("名称只出现在注释或说明文字中")
        }
        return .unused("既不在工程引用表，也未在工程文本中出现")
    }

    private func judgeInterface(_ candidate: ScanCandidate) -> ReferenceVerdict {
        let names = Set(candidate.keys)
        if !names.isDisjoint(with: project.referencedResourceNames) {
            return .referenced("Info.plist 或构建设置中配置")
        }
        if index.containsStrict(anyOf: candidate.keys) {
            return .referenced("代码或界面文件中出现该名称")
        }
        if index.containsLoose(anyOf: candidate.keys) {
            return .uncertain("名称只出现在注释或说明文字中")
        }
        if project.isReferenced(candidate.absolutePath) {
            return .uncertain("已加入 target 资源，但工程文本中没有出现名称，可能通过运行时拼接加载")
        }
        return .unused("未在工程引用表中，工程文本里也没有出现该名称")
    }

    private func judgeImageSet(_ candidate: ScanCandidate) -> ReferenceVerdict {
        if project.referencedResourceNames.contains(candidate.name) {
            return .referenced("构建设置中配置")
        }
        if index.containsStrict(anyOf: candidate.keys) {
            return .referenced("代码或界面文件中出现该名称")
        }
        if index.containsLoose(anyOf: candidate.keys) {
            return .uncertain("名称只出现在注释或说明文字中")
        }
        if let hint = prefixHint(for: candidate.name) {
            return .uncertain("名称片段「\(hint)」出现在工程文本中，可能为拼接引用")
        }
        if candidate.name.contains(" ") {
            return .uncertain("名称包含空格，引用时可能被拆分或去掉空格")
        }
        return .unused("工程文本中没有出现该 imageset 名称")
    }

    private func judgeLooseImage(_ candidate: ScanCandidate) -> ReferenceVerdict {
        if index.containsStrict(anyOf: candidate.keys) {
            return .referenced("代码或界面文件中出现该文件名")
        }
        if index.containsLoose(anyOf: candidate.keys) {
            return .uncertain("文件名只出现在注释或说明文字中")
        }
        if let hint = prefixHint(for: candidate.name) {
            return .uncertain("名称片段「\(hint)」出现在工程文本中，可能为拼接引用")
        }
        if candidate.name.contains(" ") {
            return .uncertain("名称包含空格，引用时可能被拆分或去掉空格")
        }
        return .unused("工程文本中没有出现该文件名")
    }

    /// 拼接字符串的兜底信号
    ///
    /// 例：代码里写 `"icon_\(name)"` 时，文本 token 是带分隔符结尾的 `icon_`。
    /// 如果候选名 `icon_cell_badge_fork` 的首段 + 分隔符正好在文本里出现过，
    /// 就说明它可能被拼接引用，标为「待确认」而不是高置信度冗余。
    private func prefixHint(for name: String) -> String? {
        let separators = "_-+@"
        guard let separatorIndex = name.firstIndex(where: { separators.contains($0) }) else { return nil }
        let head = String(name[name.startIndex..<separatorIndex])
        guard head.count >= 3 else { return nil }

        let preferred = "\(head)\(name[separatorIndex])"
        if index.containsStrict(preferred) { return preferred }
        for separator in separators where separator != name[separatorIndex] {
            let probe = "\(head)\(separator)"
            if index.containsStrict(probe) { return probe }
        }
        return nil
    }
}
