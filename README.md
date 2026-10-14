# WordShelf：右键 Look Up 后加入清单

主要功能：在其他 App 右键英文单词，再用鼠标点击系统 **Look Up / 查询** 菜单项后，将该词加入本地清单。重复词只保留一条。

已移除快捷键查词、手工输入、剪贴板收藏、释义、次数显示、Anki 导出及诊断面板。清单界面支持查看已保存单词与导出 CSV；菜单栏提供显示清单和退出入口。

## 打开与构建

用 Xcode 打开本目录或 Package.swift，选择 WordShelf scheme。运行需要 macOS 12 Monterey 或更新版本，支持 Intel 与 Apple 芯片。源码构建需要安装 Xcode。构建脚本同时生成 arm64 和 x86_64 通用程序。

```sh
bash build-app.sh
open dist/WordShelf.app
```

打包采用 Debug 构建、临时签名，未公证。辅助功能授权请添加打包后的 `dist/WordShelf.app`，不要添加 Xcode 调试宿主。首次运行点击“允许辅助功能访问”，在系统设置 → 隐私与安全性 → 辅助功能开启 WordShelf，必要时用 + 添加 App。App 会自动检测授权变化。重新构建更换签名后可能需要重新授权。

## 工作原理和范围

使用 NSEvent 全局鼠标事件观察与 AXUIElementCopyElementAtPosition 命中测试，不拦截或模拟点击，不读取系统查词历史，不自动抓取选中文本，不自动打开查词弹窗。

右键（或 Control + 点击）建立一次最多 30 秒的上下文。随后在鼠标按下时读取指针下的辅助功能元素；它必须是同一 App 的已启用 AXMenuItem，父元素为 AXMenu，标题严格符合 `Look Up “word”` 或 `查询“word” / 查找“word”`。只接受单个英文词，可含撇号或连字符。读取该项的范围；鼠标在范围内松开才完成收藏，延迟 0.1 秒写入数据库。

普通选词、菜单高亮、仅打开菜单、复制、菜单外松开均不触发收藏。保存表示用户点击了匹配的查词项，不保证系统词典一定返回释义；无法独立验证来源 App 的动作回调或区分故意使用相同标题的自定义菜单。

**右键路径已由用户确认可用。** 全局事件回调异步到达，某些 App 可能在读取前就关闭菜单，或不暴露菜单项/标题/位置，这时漏记而不猜测单词。其他语言、无引号的菜单、右键按住并拖动释放、键盘选择菜单不由右键点击路径处理。没有退回普通选中文本的自动保存。

数据库为 `~/Library/Application Support/WordShelf/words.sqlite`；沿用旧数据库格式，保留旧清单，旧字段不再显示或更新。App 无第三方依赖、不联网上传。需要辅助功能访问以读取其他 App 的菜单，只观察鼠标按下/松开，不监听键盘、不要求屏幕录制。

## 实机验收

1. 授权打包后的 App，并保持运行。
2. Apple News 中右键英文单词，点击 Look Up；关闭弹窗，再看清单，应新增该词。
3. 再查相同词，清单不重复。
4. 右键另一个词，只悬停 Look Up，点菜单外关闭；不得新增。
5. 右键选择 Copy；不得新增。
6. 用三个不同词重复第 2 步；对照 Safari / TextEdit。若未收藏，需要在实际系统上检查菜单暴露情况及事件时序，不能把编译通过视为功能验收。

自动化测试：`swift test`。覆盖菜单标题识别、鼠标在项内松开/越界/过期、SQLite 重开及去重。不会把模拟输入测试当作真实跨 App 点击测试。

官方接口：
- https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)
- https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition

源代码：Accessibility.swift 为点击监听，MenuClick.swift 为标题和点击规则，Store.swift 为本地清单，App.swift 为最小界面。

## App 图标

图标改为平面风格：仅稍微淡化的英国国旗背景与较大的鲜红收藏爱心，去掉毛玻璃、液态玻璃、模糊、折射和厚边框。国旗在上一版基础上再混合约 20% 白色，红心放大约 25%，占图标主体宽度约 50%。图标使用内置 ImageGen 生成/修改，PNG 原图为 Resources/AppIcon.png；Resources/AppIcon.icns 包含标准尺寸，Info.plist 的 CFBundleIconFile 指向 AppIcon。Swift Package 同时复制资源并设置 applicationIconImage，因此 Xcode 运行也能加载图标。

最终设计提示词：Clean flat macOS rounded-square icon; solid pearl-white tile with crisp geometric Union Jack with rich red and deep navy blue softened by mixing previous navy blue and flag red with approximately 20% white; large opaque vivid red heart lower right, 50% tile width, narrow white outline; no glass, blur, refraction, rim, bevel, gloss, glow, heavy shadow or text; clean transparent exterior. 图像为栅格合成，颜色淡化比例为视觉设计目标，不是可编辑的独立国旗图层。

图标源图变更后运行 `bash prepare-icon.sh /absolute/path/to/generated.png`，再运行 `bash build-app.sh`。

## 0.2.1：已授权但仍提示未授权

临时签名的 designated requirement 绑定该版本的代码哈希。重新构建或更换图标后重新签名，可能不再满足旧版本的辅助功能授权。当前开发环境没有可用的 Apple Development / Developer ID 签名身份，因此不会声称临时签名能够保证更新后继续授权。

请按这个顺序恢复：

1. 退出所有 WordShelf，包括 Xcode 启动的版本。
2. 系统设置 → 隐私与安全性 → 辅助功能，选中旧 WordShelf 条目，用减号移除。
3. 用加号重新添加本工程 `dist/WordShelf.app`，打开开关。
4. 运行同一份 App。如果仍提示未授权，点击“显示当前 App”核对运行位置，退出该 App 再打开，点击“重新检查权限”。不要给源码目录、Xcode 或另一份 WordShelf 授权来代替当前 App。
5. 在 Apple News 中右键英文单词，点击 Look Up，确认单词加入清单。

权限状态现在每秒独立更新，不再依赖查词状态消息；回到 App 前台和手动重查也会刷新。程序不会改写 TCC 数据库或自动替用户授予权限。

如果以后已有开发签名证书，可用 `WORDSHELF_SIGNING_IDENTITY="证书指纹" bash build-app.sh` 使用固定身份签名；仍需在首次更换身份时重新授权。不要把临时签名改成宽松的 identifier-only requirement 来绕过身份检查。

官方说明：https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements

## 0.2.3：导出 CSV

清单右上角点击“导出 CSV”，在系统保存对话框选择位置。导出 UTF-8 编码 CSV，单列 `word`，每个收藏单词一行，使用标准 CRLF 换行与带引号字段，顺序与清单一致。重复词不会重复导出，导出不会清空清单。没有记录时按钮禁用；导出不要求辅助功能权限。

## 0.3.1：单词斑马纹清单与 CSV

仅保留右键 Look Up 后加入单词清单，不获取或显示词典释义。清单以单列表格逐行显示，交替使用系统行底色。右上角“导出 CSV”可选择保存位置；导出 UTF-8 编码、单列 `word`，每个单词一行，重复词仅导出一条，不清空清单。导出不要求辅助功能权限；清单为空时按钮禁用。

测试：先右键一个英文词，点击 Look Up，确认新增；重复查询不重复；只打开或取消右键菜单不得新增。再导出 CSV，确认与清单一致。临时签名更新后可能需要移除旧辅助功能条目并重新添加这一版 App。

## 0.3.2：菜单栏重新打开清单

“显示清单”使用 SwiftUI `openWindow(id:)` 打开具有固定 ID 的单一清单窗口，不再遍历已有窗口并按标题匹配。关闭清单后仍能由菜单栏重新创建；重复点击复用同一窗口。菜单动作结束后激活 App。

验收：关闭清单窗口 → 菜单栏点击“显示清单”；重复关闭再打开；在其他 App 前台时再次点击；确认只出现一个清单窗口，原有记录及 CSV 导出仍可使用。

## 0.3.3：单词计数

“导出 CSV”按钮左侧显示“单词数量：N个”，直接根据当前去重清单的记录数更新。启动载入已有记录和收藏新词后会刷新；重复查询不会增加单词数量。

## 0.4：手动中文含义

斑马纹清单改为“已查单词”“中文含义”两列。鼠标滑到中文含义单元格时出现输入框，点击后输入；按回车或焦点离开时保存，非编辑状态直接显示已有含义。输入内容为用户手动填写，不使用自动词典或翻译。关闭窗口、退出 App、导出 CSV 前会提交正在编辑的草稿，防止漏掉最后一次输入。

CSV 表头为“已查单词,中文含义”，包含全部记录和手动含义，支持引号/逗号/换行转义。原有单词和去重计数保持；含义可修改或清空，重复查词不会覆盖含义。

## 0.4.1：菜单栏图标

菜单栏图标改为单色矢量的圆润飘动小旗与爱心收藏标记，19 × 18 点，模板渲染自动适应菜单栏颜色。只替换菜单栏图标，App 的 Dock/Finder 图标保持原样。MenuIcon.swift 使用 AppKit 路径绘制，不引入图像生成资源或新的依赖。

## 0.4.2：米字旗菜单栏图标与清空

菜单栏改为更短的近方形圆角米字旗＋小爱心，19 × 18 点，减少内部纹理，保留英国旗帜的特征。导出 CSV 前增加“清空单词”按钮，清空前弹窗确认，取消为默认按钮；确认后删除全部单词和中文含义，丢弃未提交的编辑草稿，数量归零。空清单时按钮禁用，清空后仍可重新收藏。

## 0.4.3：空清单提示

没有单词时，在清单区域居中显示“目前暂无单词，去查一个试试~”；记录第一个单词后自动切换为表格。清空后也会显示此提示。

## 0.4.5：关于页面联系方式

系统关于面板显示用户提供的原文“Auther：leiquan@live.com”。可由应用菜单或菜单栏“关于 WordShelf”打开。

## 0.4.6：手动检查权限反馈

点击“重新检查权限”会明确显示检查结果：未授权时弹出提示，可选择打开系统辅助功能设置；已授权时提示监听状态。如果系统设置打不开，提供手动入口。后台定时检查和回到 App 前台的自动刷新保持静默，不会反复弹窗。不会自动修改系统授权。

## 0.4.7：权限提示文案

未授权状态与检查权限弹窗统一显示“暂无权限，无法记录”，删除长段落解释。

## 0.5.0：macOS 12 与通用程序

最低系统版本降至 macOS 12 Monterey，打包包含 Intel x86_64 和 Apple Silicon arm64。菜单栏使用 NSStatusItem，清单使用 NSWindow 承载 SwiftUI，替代 macOS 13 才支持的 MenuBarExtra / Window / openWindow。

点击左上角关闭按钮只关闭清单窗口，App、菜单栏和已授权的鼠标监听继续运行。菜单栏“显示清单”重新显示同一窗口，重复点击不会创建多个清单；仅选择“退出”或 Command-Q 才结束程序。窗口关闭前提交手动含义草稿。

已验证两种架构的 Mach-O 最低系统版本为 12.0，签名完整性检查通过，6 项存储与点击规则测试通过，并在当前 Mac 打开了清单界面。尚未在 Intel Mac 或 macOS 12 实机验证跨 App 菜单监听；各 App 暴露的辅助功能菜单仍可能不同。

## 0.5.1：销毁清单窗口并隐藏 Dock

点击叉号先保存编辑草稿，再移除窗口的 SwiftUI 内容、释放清单窗口引用，并切换为 accessory 模式，使 Dock 图标隐藏。Model 与鼠标监听器由应用代理继续持有，菜单栏保持运行。菜单栏“显示清单”切回 regular 模式并创建新窗口；重复点击复用当前打开的窗口。保存失败时取消关闭，保留草稿。
