import Foundation

// MARK: - 代码文件自己声明的类型名
//
// 代码文件是否需要，不能只看「有没有被实例化」：
// 被别的类继承的基类、被遵循的协议、只当类型标注用的模型，本身都不会 new 出来。
// 这里提取文件里声明的类型名，判定阶段再看这些名字是否出现在别的文件里。
//
// 只收 class / struct / enum / protocol / actor 与 Objective-C 的 @interface / @implementation，
// extension 的名字多为系统类型（extension UIViewController 之类），收进来会大量误判为「被引用」。

enum TypeDeclarationScanner {
    private static let swiftPattern = #"(?m)^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]+)*(?:(?:public|private|internal|open|final|fileprivate|package|indirect|nonisolated|mutating)[ \t]+)*(?:class|struct|enum|protocol|actor)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#
    private static let objcPattern = #"(?m)^[ \t]*@(?:interface|implementation)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#

    private static let swiftRegex = try? NSRegularExpression(pattern: swiftPattern)
    private static let objcRegex = try? NSRegularExpression(pattern: objcPattern)

    /// 文件里声明的类型名（去重、保持出现顺序）
    static func names(in text: String) -> [String] {
        let source = text.count > 1_200_000 ? String(text.prefix(1_200_000)) : text
        let nsText = source as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var seen: Set<String> = []
        var names: [String] = []

        for regex in [swiftRegex, objcRegex].compactMap({ $0 }) {
            for match in regex.matches(in: source, range: range) {
                let name = nsText.substring(with: match.range(at: 1))
                if seen.insert(name).inserted { names.append(name) }
            }
        }
        return names
    }
}
