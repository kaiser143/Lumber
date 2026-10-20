import SwiftUI

// MARK: - 忽略规则页
//
// 内置规则只读；用户规则写入 ~/Library/Application Support/Lumber/ignore_rules，
// 重启后仍然生效。会话级的「忽略」条目不在这里，它们在结果页的「已忽略」入口。

struct IgnoreRulesView: View {
    @Environment(AppModel.self) private var model
    @State private var newRule = ""

    private var userRules: [IgnoreRule] { model.rules.filter { !$0.isBuiltIn } }
    private var builtInRules: [IgnoreRule] { model.rules.filter(\.isBuiltIn) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                builtInSection
                userSection
                footer
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("忽略规则")
                .font(.system(size: 17, weight: .bold))
            Text("语法对齐 .gitignore 常用子集：目录（Pods/）、通配符（*.md、Debug/*.png、Test_*）、根锚定（/build/）、取反（!keep.png）。命中规则的目录/文件在扫描时直接跳过。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var builtInSection: some View {
        section(title: "内置默认规则（\(builtInRules.count) 条，只读）", tint: .secondary) {
            ForEach(builtInRules) { rule in
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(rule.pattern)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.lumberCanvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var userSection: some View {
        section(title: "用户规则（\(userRules.count) 条，已持久化）", tint: .lumberAccent) {
            if userRules.isEmpty {
                Text("还没有用户规则。添加的规则会立即生效，并在下次启动时保留。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }

            ForEach(userRules) { rule in
                HStack(spacing: 8) {
                    Image(systemName: rule.pattern.hasPrefix("!") ? "arrow.uturn.left.circle" : "text.justify.left")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(rule.pattern)
                        .font(.system(size: 12, design: .monospaced))
                    if rule.pattern.hasPrefix("!") {
                        Text("取反")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button { model.deleteUserRule(rule.id) } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("删除该规则")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.lumberCanvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            addRow
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.lumberAccent)
            TextField("例如 *.md、Debug/、!keep.png", text: $newRule)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(addRule)
            Button("从 .gitignore 导入") { model.importGitignoreFile() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("选择工程里的 .gitignore，规则会合并到用户规则")
            Button("添加") { addRule() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newRule.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("规则文件：\(IgnoreRulesStore.displayPath)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text("与 git 相同，父目录被忽略时无法用 ! 再取回其中的文件（扫描器在目录层就剪枝了）。修改规则后重新扫描即可生效。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private func section<Content: View>(
        title: String, tint: Color, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }

    private func addRule() {
        model.addUserRule(newRule)
        newRule = ""
    }
}
