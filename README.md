# Lumber

Lumber 是一款 macOS 原生应用，用于扫描 Xcode 工程里**没有被引用的冗余资源**——图片、XIB / Storyboard、代码文件等——并支持预览、忽略和一键移入废纸篓。

界面基于 SwiftUI + Liquid Glass，工程解析与引用判定全部由零依赖的 Swift 代码完成，不依赖 Xcode 命令行工具，也不会修改工程文件。

## 特性

- **拖放即用**：拖入 `.xcodeproj` 或包含工程的目录，也可点击选择；非法文件仅红框提示，不弹窗
- **自研 pbxproj 解析**：文件引用、folder reference、Xcode 16 同步文件夹、`PBXVariantGroup`、target、Info.plist 与构建设置资源名，并合并同一 workspace 下兄弟工程的引用（如 Pods）
- **Assets 解析**：识别 `imageset` / `dataset` / `colorset` 等条目，而不是逐张图片
- **引用判定宁漏勿删**：区分代码与注释（strict / loose 索引）、类型声明、`@2x/@3x` 与驼峰变体，结果分为「高置信度未引用」和「待确认」
- **流畅扫描**：两阶段异步扫描，实时进度，可取消；不写缓存、不落盘
- **结果列表**：类型筛选、搜索、只看待确认、缩略图、Finder 定位、批量操作与键盘导航
- **独立预览窗口**：图片按比例自适应窗口，支持缩放旋转；代码 / XIB 文本预览；`← →` 切换
- **忽略规则**：兼容 `.gitignore` 常用子集，支持导入 `.gitignore`，规则持久化
- **安全删除**：统一走系统废纸篓，可恢复；批量删除需确认
- **命令行自检**：`--inspect` 无界面打印解析与扫描摘要，便于验证解析正确性

## 环境要求

- macOS 26.0+
- Xcode 26 / Swift 6（`swift-tools-version:5.9`）
- 无第三方依赖

## 快速开始

```bash
git clone <仓库地址> Lumber
cd Lumber
swift run Lumber
```

发布构建：

```bash
swift build -c release   # 产物：.build/release/Lumber
```

也可以 `open Package.swift` 用 Xcode 开发。

## 命令行参数

| 参数                | 说明                  |
| ----------------- | ------------------- |
| `--open <路径>`     | 启动后直接扫描指定工程或目录      |
| `--inspect <路径>`  | 不开窗口，打印解析与扫描摘要后退出   |
| `--mock`          | 使用内置演示数据，模拟扫描，不读写磁盘 |
| `--demo=results`  | 直接进入结果列表（Mock 数据）   |
| `--demo=preview`  | 进入结果列表并打开预览窗口       |
| `--demo=scanning` | 进入扫描中状态             |
| `--demo=rules`    | 进入忽略规则页             |
| `--demo=settings` | 进入设置页               |

示例：

```bash
swift run Lumber --open ~/Develop/DemoApp
swift run Lumber --inspect ~/Develop/DemoApp/DemoApp.xcodeproj
```

## 使用方式

1. 拖入或选择 `.xcodeproj`，等待扫描完成；
2. 在结果列表按类型筛选、搜索，或只看「待确认」；
3. 双击 / 空格预览，确认后忽略或移入废纸篓；
4. 需要长期跳过的文件，到忽略规则页添加规则（或导入 `.gitignore`）后重新扫描。

常用快捷键：`⌘O` 打开工程、`⌘R` 重新扫描、`空格 / 回车` 预览、`Delete` 删除、`Esc` 关闭预览。

首次扫描其他目录若提示无权限，请在「系统设置 › 隐私与安全性 › 完全磁盘访问权限」中放行。

## 判定原则

| 结果      | 含义                                           |
| ------- | -------------------------------------------- |
| 已引用     | 出现在 pbxproj、构建配置、Info.plist 或工程文本（代码 / 字符串）中 |
| 待确认     | 名字只出现在注释、拼接前缀或部分匹配中，需要人工判断                   |
| 高置信度未引用 | 工程里完全找不到该名称，且未被 target 引用                    |

扫描会跳过 `Pods`、`Carthage`、`DerivedData`、`build`、`node_modules`、`fastlane` 等目录，以及 `.xcodeproj`、`.xcframework`、`.bundle`、`.app` 等包。

## 忽略规则

规则保存在 `~/Library/Application Support/Lumber/ignore_rules`，每行一条，支持：

```
Pods/            # 任意层级的目录
*.md             # 任意层级的文件
Debug/*.png      # 相对工程根目录
/build/          # 根锚定
!keep.png        # 取反，后写优先
```

与 git 一致，父目录被忽略后无法再用 `!` 取回其中的文件。

## 项目结构

```
Sources/Lumber/
├── App/            入口、全局状态、外壳与主题
├── Core/
│   ├── Models/     资源与工程数据模型
│   ├── Parsing/    pbxproj、Assets、Info.plist 解析
│   ├── Services/   扫描引擎、引用索引与判定、预览、废纸篓
│   ├── Ignore/     忽略规则匹配与持久化
│   └── Mocks/      演示数据
└── Features/       首页、扫描、结果、预览、规则、设置
```

原始产品需求与实现计划见 `Lumber-Cursor-Prompt.md`。

## 已知限制

- 采用静态文本匹配，运行时拼接的资源名只能归为「待确认」或漏报；
- 只解析 pbxproj 的第一个 `rootObject`，不递归嵌套子工程；
- 同步文件夹按整目录视为已引用，不区分 exception；
- 单文件索引上限 1.2MB，预览文本上限 400KB；
- 扫描历史与扫描选项不持久化。

## 许可

仓库暂未附带许可证，如需开源发布请补充。
