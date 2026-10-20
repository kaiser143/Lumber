# Lumber — Cursor 提示词（Xcode 冗余资源清理工具）

> 使用方式：把本文档整体作为 Cursor 的上下文（可保存为项目根目录的 `.cursorrules` 或 `Lumber-Spec.md`，在对话中 @ 引用），然后按「分阶段提示词」一节，从 **阶段 1（UI 搭建）** 开始逐段发送。每个阶段完成后先人工验收，再发送下一阶段。

---

## 一、主提示词（项目总纲，先发给 Cursor 一次）

```
帮我开发一个 macOS 应用，项目名 Lumber，用于检查 Xcode 工程中的冗余资源并列出、预览、清理。

【产品定位】
Lumber 是一款面向 iOS/macOS 开发者的 Xcode 工程清理工具：用户把 .xcodeproj 工程文件拖进窗口，Lumber 扫描工程中「未被引用的图片、xib/storyboard、代码文件等资源」，以列表形式列出，支持预览、忽略、删除（走系统废纸篓）。

【技术约束】
- 语言：Swift，UI 框架：SwiftUI（纯 SwiftUI，不用 storyboard/xib 构建 UI）
- 目标系统：macOS 14.0+，不需要兼容更低版本，可放心使用最新 API（NavigationSplitView、Observable 宏、Swift Charts 等可用即用）
- 工程：SwiftPM 管理第三方依赖（尽量零依赖，如需解析 xcodeproj 可考虑 SPM 包，但阶段 1 不引入任何依赖）
- 架构：MVVM + 特性模块化。目录结构建议：
  Lumber/
    App/            # 入口、App 生命周期
    Features/
      Home/         # 空白首页 + 拖放区
      ScanResult/   # 扫描结果列表
      Preview/      # 资源预览页（独立页面）
      IgnoreRules/  # 忽略规则管理
    Core/
      Models/       # ResourceItem、ScanResult、IgnoreRule 等数据模型
      Services/     # 扫描引擎、文件系统、废纸篓（后续阶段实现）
      Mocks/        # UI 阶段用的测试数据
- 所有耗时操作必须异步（Swift Concurrency：async/await、Task、actor），绝不阻塞主线程/UI
- 不持久化任何历史记录：每次启动 App 都是空白首页，不做"最近工程"列表

【核心交互流程】
1. 启动 → 空白首页，中央一个大拖放区
2. 用户拖入 .xcodeproj 文件（也接受含 .xcodeproj 的目录）→ 校验后缀，非法文件在拖放区显示错误提示（不弹窗）
3. 开始异步扫描 → 首页切换为扫描中状态（进度条 + 当前扫描路径 + 已发现数量）
4. 扫描完成 → 进入结果列表页，列出所有冗余资源
5. 列表中：点击某项的 icon，或选中某项后按空格键 → 打开独立的预览页面（新页面导航，不用 App 内弹窗/sheet）
6. 列表中每项可操作：忽略（本次扫描内生效）、删除（移到系统废纸篓）
7. 支持配置忽略规则（类似 .gitignore 语法），可针对目录（如 Pods/）或文件模式；有默认内置规则

【删除安全】
- 所有删除必须走系统废纸篓（NSWorkspace.shared.recycle），绝不直接 unlink/delete
- 删除前如目标不存在或已变化，跳过并在列表中标记，不报错崩溃

【实现纪律——非常重要】
- 严格分阶段实现：当前阶段只做当前阶段的事，不提前实现后续功能
- 阶段 1 只做 UI + Mock 数据，所有数据来自 Mocks，不碰真实文件系统
- 每个阶段完成后，告诉我如何运行验收，并等我确认后才进入下一阶段
```

---

## 二、分阶段提示词

### 阶段 1：UI 搭建 + Mock 数据（先做，等验收）

```
现在实现 Lumber 的全部 UI 界面，用 Mock 数据填充。本阶段禁止访问真实文件系统、禁止实现扫描逻辑，只做界面和交互流转，保证每个页面都能通过 Mock 数据完整预览。

【1. 空白首页（App 启动页）】
- 窗口：约 560x420，标题 Lumber，使用 NavigationSplitView 布局
- 左侧边栏：窄边栏，底部放 App 设置入口（图标按钮）；顶部放"忽略规则"入口（图标按钮）。此阶段边栏保持简洁
- 主区域中央一个大拖放区：
  - 一个大的虚线圆角边框区域，中间是工程文件图标 + 主文案"拖入 Xcode 工程文件"+ 副文案"支持 .xcodeproj，扫描未使用的图片、XIB、代码等资源"
  - 整个主区域接受拖放（onDrop），拖入文件悬停时边框高亮变色
  - 本阶段：拖放区点击后弹 NSOpenPanel 选择文件的行为可先留空/仅打印日志；拖入任意文件先当作合法工程，用于演示后续流程
- 底部状态栏：显示默认忽略规则已启用（如 "已忽略: Pods/、Carthage/、fastlane/"），点击可跳到忽略规则页

【2. 扫描中状态页】
- 拖入后首页内容切换为扫描状态：顶部显示工程名与路径，中间一个进度条（indeterminate 到 determinate 的占位）、当前正在扫描的路径（等宽字体）、实时统计（已扫描文件数 / 发现冗余资源数）
- 提供取消按钮
- 本阶段：用一个 Task 模拟进度（每 100ms 推进），4 秒左右完成后自动进入结果列表页

【3. 扫描结果列表页】
- 顶部工具栏：标题"扫描结果"、工程名、汇总统计（共 N 项冗余，总大小 X MB）、按类型筛选的分段控件（全部 / 图片 / XIB·Storyboard / 代码 / 其他）、搜索框
- 列表（Table 或 List + 自定义行）：
  - 行首 icon（约 36pt）：
    - 图片资源（png/jpg/svg/pdf 等）：直接显示该图片的缩略图（Mock 阶段用 SF Symbols 生成的 NSImage 或随机色块图占位）
    - .swift 文件：SF Symbol "swift" 图标
    - .xib/.storyboard：SF Symbol "doc.richtext" 图标
    - 其他类型：通用文档图标
  - 主文案：文件名（含扩展名）；副文案：相对工程路径（等宽小字，灰色）
  - 右侧信息：文件大小（如 24 KB）、类型标签（"图片" / "XIB" / "代码"，胶囊样式 badge）
  - 行尾两个按钮：「忽略」（眼睛斜杠图标）和「删除」（废纸篓图标，红色 hover）
  - 行支持选中（高亮）；支持键盘上下键移动选中、空格键触发预览（.onKeyPress(.space)）
  - 空格和点击 icon 都打开预览页
- 底部操作栏：「全部忽略」「删除选中」「删除全部」，以及"X 项已忽略"的撤销入口（点击可查看被忽略列表并恢复）
- Mock 数据：预置 15~20 条覆盖各类型（图片 8 条、xib 3 条、swift 4 条、其他 2 条），路径、大小要真实合理（如 Assets.xcassets/xxx.imageset、Views/Cell.xib、Utils/OldHelper.swift）；被"忽略"和"删除"的行要即时从列表消失并可撤销（删除本阶段仅从列表移除 + toast 提示"已移到废纸篓（演示）"）

【4. 预览页（独立页面，不用弹窗）】
- 通过 NavigationLink / navigationDestination 从列表页推入，占据整个主区域
- 顶部：返回按钮 + 文件名 + 路径；右上角「忽略」「删除」按钮
- 内容按类型区分：
  - 图片：大图居中显示，可缩放（MagnificationGesture）适配窗口；下方显示尺寸、大小、格式
  - 代码文件：滚动文本视图显示文件内容（Mock 用一段示例 Swift 代码），等宽字体，简单的语法着色可用纯文本+着色关键词模拟，不强求
  - XIB/Storyboard：显示 XML 源码预览 + 文件信息
  - 其他：文件信息卡片（路径、大小、修改时间）
- 左右方向键可在冗余列表内切换上一项/下一项预览
- 本阶段：预览数据从 Mock 数据取，图片用程序生成的示例图（如随机渐变 NSImage）或 bundle 内置测试图

【5. 忽略规则页】
- 从边栏进入；标题"忽略规则"
- 说明文案：规则语法类似 .gitignore
- 内置默认规则区（只读展示，带锁图标）：Pods/、Carthage/、.git/、DerivedData/、fastlane/
- 用户规则区：可增删的规则列表（每行一条，如 *.md、Debug/、Test_*.png），底部输入框 + 添加按钮
- 一个"从文件导入"按钮（本阶段可禁用或仅打印）
- 规则数据先用内存模型 + Mock 默认值，持久化放后续阶段

【6. 设置页】
- 简单表单：启动时检查更新开关（占位）、扫描深度、是否包含代码文件开关等；本阶段纯 UI，不持久化

【本阶段验收标准】
- App 启动即空白首页；拖放区可交互，拖入后走完 模拟扫描 → 列表 → 预览 完整流程
- 列表筛选、搜索、忽略、删除（模拟）、空格预览、键盘导航全部可用
- 所有页面在浅色/深色模式下显示正常，窗口缩放布局不错乱
- 全程无真实磁盘读写
```

---

### 阶段 2：拖放识别 + 工程解析（验收 UI 后发送）

```
UI 已验收，现在实现真实的拖放识别与工程解析。

- 实现 onDrop 真实逻辑：读取 NSItemProvider 中的文件 URL，校验：
  - 后缀为 .xcodeproj → 合法
  - 拖入的是包含 .xcodeproj 的目录 → 自动找到其中第一个 .xcodeproj
  - 其他情况 → 拖放区显示错误提示（红色边框 + 错误文案，几秒后恢复），不弹窗
- 点击拖放区 → NSOpenPanel 选择 .xcodeproj 或目录
- 解析工程：读取 .xcodeproj/project.pbxproj，得到：
  - 所有被工程引用的文件与资源（含 PBXBuildFile、PBXFileReference，含 PBXVariantGroup 下的资源）
  - target 名称列表、工程名
- 解析 Assets.xcassets：imageset / dataset 里实际包含的图片文件，以及图片名（引用名不含扩展名，注意 imageNamed 的匹配规则）
- 解析结果构建资源引用表（ResourceItem：路径、类型、大小、被引用状态），落到底层模型，替换阶段 1 的 Mock 数据源
- 保留 Mock 开关（如启动参数 --mock 或 DEBUG 菜单），方便 UI 回归
```

---

### 阶段 3：冗余扫描引擎（异步）

```
实现扫描引擎，判定"冗余"，替代阶段 1 的模拟扫描。

- 扫描在后台 actor 中执行（ScanEngine actor），UI 通过 AsyncSequence / @Observable 状态流接收进度与结果，确保不卡 UI
- 冗余判定逻辑：
  1. 物理文件扫描：遍历工程目录（排除忽略规则命中的目录），收集候选文件：图片（png/jpg/jpeg/svg/pdf/gif/webp）、xib、storyboard、strings、swift/m/h 等类型
  2. 引用匹配：
     - 代码文件（.swift/.m/.h）：不在 pbxproj 的 PBXBuildFile/文件引用中 → 疑似冗余（对文件夹引用 folder reference 需要整目录引用则不算冗余）
     - xib/storyboard：文件名未在任何代码（字符串形式）、pbxproj Main Storyboard 配置、其他 xib 的 bundle 引用中出现 → 疑似冗余
     - 图片：分两类——bundle 内散落图片按文件名/无扩展名匹配代码字符串引用；xcassets 内 imageset 按 imageset 名匹配 imageNamed / UIImage(named:) / Color(named:) / SwiftUI Image("name") 等 API 模式
  3. 谨慎原则：匹配采用"宁漏勿删"，只列出高置信度未引用项；对低置信度（如名字出现在注释或拼接字符串中）打上"待确认"标记
- 扫描过程 UI 展示：当前路径、已扫描数、各类型发现数、进度（按文件数估算）
- 支持取消（Task cancellation，及时响应）
- 扫描结果缓存于内存（本次会话），不落盘、不保存历史
```

---

### 阶段 4：忽略规则系统

```
实现忽略规则：

- 规则语法（对齐 .gitignore 常用子集）：目录（Pods/）、通配符（*.md、Debug/*.png、Test_*）、取反（!keep.png）可选
- 内置默认规则：Pods/、Carthage/、.git/、DerivedData/、fastlane/、*.xcworkspace/contents.xcworkspacedata
- 规则生效范围：扫描时直接跳过命中目录/文件；列表中手动"忽略"的项目写入会话级忽略（本次有效，不持久化）
- 规则持久化：保存到 UserDefaults 或 ~/Library/Application Support/Lumber/ignore_rules 文件，App 重启后规则保留（但扫描历史仍不保留）
- 支持从 .gitignore 文件导入规则
- 列表页"已忽略"入口可查看并恢复
```

---

### 阶段 5：删除（废纸篓）与收尾

```
实现真实删除与整体收尾：

- 删除单个 / 删除选中 / 删除全部：统一走 NSWorkspace.shared.recycle(_:completionHandler:)，把文件移到废纸篓，绝不直接删除
- 删除后更新列表与统计；失败的项（文件被外部移动等）标记"不可用"并提示
- 二次确认：删除全部时弹系统风格的确认对话框（alert），显示将要删除的文件数与总大小；单个删除不确认直接进废纸篓
- 边界处理：删除 .xcassets 中的 imageset 时删除整个 imageset 目录而非单张图片
- 收尾：错误处理统一（扫描权限失败、pbxproj 损坏等给友好提示）；窗口标题显示当前工程；Cmd+O 也可打开选择工程
- 清理所有 Mock 残留与 TODO，补齐注释
```

---

## 三、验收顺序建议

| 顺序 | 内容      | 验收要点                                  |
| -- | ------- | ------------------------------------- |
| 1  | 阶段 1 UI | 页面流转完整、Mock 数据覆盖全类型、空格预览、忽略/删除交互、明暗模式 |
| 2  | 拖放识别    | 拖入合法/非法文件的表现、目录自动发现 .xcodeproj        |
| 3  | 扫描引擎    | 大工程（如含 1 万+文件的工程）扫描时 UI 不卡、进度实时、可取消   |
| 4  | 忽略规则    | Pods 等默认规则生效、gitignore 导入             |
| 5  | 删除      | 文件确实出现在废纸篓、可还原、无直接删除                  |

---

## 四、给 Cursor 的补充说明（可附在任何阶段）

- 遇到 pbxproj 解析的复杂边界（PBXVariantGroup、folder reference、多 target 同名文件）时，在代码注释中标注假设，不要静默简化
- 生成的每个 Swift 文件控制在 300 行以内，超过就拆分
- 每阶段交付时列出：新增/修改的文件清单、涉及的关键技术点、我该如何手动验收
