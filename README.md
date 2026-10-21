# Lumber

Lumber 是一款 macOS 原生应用，用于扫描 Xcode 工程里**没有被引用的冗余资源**——图片、颜色、数据集、XIB / Storyboard、代码文件等——并支持预览、忽略、多选、导出报告和一键移入废纸篓。

界面基于 SwiftUI + Liquid Glass，工程解析与引用判定全部由零依赖的 Swift 代码完成，不依赖 Xcode 命令行工具，也不会修改工程文件。

## 特性

- **拖放即用**：拖入 `.xcodeproj`、`.xcworkspace` 或包含工程的目录，也可点击选择；非法文件仅红框提示，不弹窗
- **多工程选择**：目录 / workspace 里有多个工程时弹出选择面板，自动排除 Pods、Carthage 等依赖工程
- **自研 pbxproj 解析**：文件引用、folder reference、Xcode 16 同步文件夹、`PBXVariantGroup`、target、Info.plist 与构建设置资源名，并合并同一 workspace 下兄弟工程的引用（如 Pods）
- **构建阶段判定**：读取 `PBXBuildFile`，区分「已加入 target」与「在工程导航器里但没加入任何构建阶段」
- **Assets 解析**：统一解析 `imageset` / `colorset` / `dataset` / `imagestack` / `spriteatlas`，按资源名聚合，而不是逐张图片
- **引用判定宁漏勿删**：区分代码与注释（strict / loose 索引）、类型声明、`@2x/@3x` 与驼峰变体；结果分为「高置信度未引用」「未加入 target」「待确认」
- **整目录保护**：蓝色文件夹 / 同步文件夹里的散落资源按「可能运行时按路径读取」处理，避免误删
- **流畅扫描**：两阶段异步扫描，实时进度，可取消；不写缓存、不落盘
- **结果列表**：类型筛选、搜索、排序、只看待确认、缩略图、Finder 定位、多选、批量操作与键盘导航
- **结果统计**：当前结果总大小与高置信度可释放空间
- **单例预览窗口**：同一时间只有一个预览窗口，切换资源只替换内容；图片按比例自适应窗口，支持缩放旋转；代码 / XIB 文本预览；`← →` 切换，`空格 / Esc` 关闭
- **导出报告**：当前筛选结果导出 CSV（UTF-8 with BOM，Excel / Numbers 直接打开）
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
| `--demo=about`   | 进入关于页               |

示例：

```bash
swift run Lumber --open ~/Develop/DemoApp
swift run Lumber --inspect ~/Develop/DemoApp/DemoApp.xcodeproj
swift run Lumber --inspect ~/Develop/DemoApp/DemoApp.xcworkspace
```

## 使用方式

1. 拖入或选择 `.xcodeproj` / `.xcworkspace`，等待扫描完成；有多个工程时先选择；
2. 在结果列表按类型筛选、搜索、排序，或只看「待确认」；
3. 单击选中，`⌘` 点击多选，`Shift` 点击区间选择；双击 / 空格预览，确认后忽略或移入废纸篓；
4. 需要长期跳过的文件，到忽略规则页添加规则（或导入 `.gitignore`）后重新扫描；
5. 需要留档时，从右上角菜单导出当前筛选结果为 CSV。

常用快捷键：`⌘O` 打开工程、`⌘R` 重新扫描、`⌘F` 搜索、`⌘A` 全选、`⌘E` 导出报告、列表内 `空格 / 回车` 预览、`Delete` 删除；预览窗口内 `← →` 切换资源、`空格 / Esc` 关闭。

首次扫描其他目录若提示无权限，请在「系统设置 › 隐私与安全性 › 完全磁盘访问权限」中放行。

## 判定原则

| 结果        | 含义                                                                 |
| --------- | ------------------------------------------------------------------ |
| 已引用       | 出现在 pbxproj、构建阶段、Info.plist 或工程文本（代码 / 字符串）中                          |
| 未加入 target | 文件登记在工程导航器中，但没有出现在任何 `PBXBuildFile` 构建阶段；不会进包，通常是漏配             |
| 待确认       | 名字只出现在注释、拼接前缀、空格拆分或部分匹配中，需要人工判断                                    |
| 高置信度未引用   | 工程里完全找不到该名称，且未被 target 引用                                          |

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
│   ├── Services/   扫描引擎、引用索引与判定、预览、废纸篓、CSV 导出
│   ├── Ignore/     忽略规则匹配与持久化
│   └── Mocks/      演示数据
└── Features/       首页、扫描、结果、预览、规则、设置、关于、多工程选择
Tests/LumberTests/  解析 / 忽略规则 / 判定 / 导出 / 工程选择单元测试
```

原始产品需求与实现计划见 `Lumber-Cursor-Prompt.md`。

## 测试

```bash
swift test
```

覆盖：

- pbxproj 解析：构建阶段、folder reference、同步根组、VariantGroup、`projectDirPath`
- 忽略规则：目录 / 根锚定 / 通配符 / `**` / 取反 / 大小写
- 引用判定：已引用、未加入 target、注释命中、整目录保护、代码类型使用
- Assets 解析：imageset / colorset / dataset、体积与代表文件
- 工程选择：多工程、workspace、Pods 过滤、错误输入
- CSV 导出：逗号 / 引号 / 换行转义

CI 见 `.github/workflows/ci.yml`。

## 已知限制

- 采用静态文本匹配，运行时拼接的资源名只能归为「待确认」或漏报；
- 只解析 pbxproj 的第一个 `rootObject`，不递归解析嵌套子工程；
- 同步文件夹按「自动加入 target」处理，不区分 `PBXFileSystemSynchronizedBuildFileExceptionSet` 的 exception；
- 不解析 `.xcconfig`，`INFOPLIST_FILE` / `ASSETCATALOG_COMPILER_*` 写在 xcconfig 时读不到；
- 不扫描 SPM `.swiftpm` 资源包；
- 单文件索引上限 1.5MB、单个 token 上限 96 字符，预览文本上限 400KB；
- 扫描历史与扫描选项不持久化。

## 许可

仓库暂未附带许可证，如需开源发布请补充。
