# 漫阅 · Manhua Reader

<p>
  <img src="assets/app_icon.png" width="88" alt="漫阅图标" />
</p>

面向手机与平板的本地漫画阅读器，支持 **PDF** 与 **MOBI**。深色低光界面，横竖屏自适应，阅读进度自动保存。

## 功能

- **导入本地漫画**：支持多选 PDF / MOBI，导入时复制到应用私有目录，不改动原文件。
- **书架**：封面缩略图、格式标签、页数、阅读进度、继续阅读卡片；点卡片右上角菜单或长按进入管理（只删应用内副本）。
- **书架整理（P1）**
  - 按书名 / 原始文件名即时搜索，未命中时提示清除筛选。
  - 按最近阅读、最近导入、书名、阅读进度排序；按 PDF / MOBI、未读 / 阅读中 / 已读完筛选。
  - 网格 / 列表视图切换，偏好写入 `library.json`，下次启动保留。
  - 长按进入多选：全选、批量标记已读、批量删除。
  - 重命名只修改书架显示名；丢失文件可重新定位替换，保留进度与书签；封面可手动重建。
  - 存储管理显示总占用、每本书占用、缓存与无引用文件，并支持一键清理。
- **可靠导入**：多文件顺序导入，显示当前 / 总数 / 成功 / 失败与百分比；支持取消剩余任务；先写 `.part` 临时文件再原子改名，失败自动回滚。
- **阅读器**
  - 横向翻页（PageView）与纵向连续滚动两种模式，切换时保留当前页。
  - **双页模式**：横向模式下按「封面单页 + 后续两页一跨」组合，适合平板横屏；可从底部工具栏一键开关，并记住设置。
  - 左右点击区域翻页，点击中间显示 / 隐藏菜单。
  - 双击放大、双指缩放与拖动，双击可复位。
  - 页码滑杆、精确跳页、从右向左阅读模式。
  - 自动保存页码、阅读时间、模式、方向与双页设置；返回书架后立即体现。
- **目录 / 书签 / 缩略图**
  - PDF 读取内嵌 outline（PDF 书签）生成章节目录；MOBI 解析 HTML 标题生成章节。
  - 没有章节信息的单行本会自动生成每 20 页的页码目录，并提示使用书签建立自己的章节。
  - 阅读时点击顶部书签图标即可快速收藏 / 取消当前页；收藏后提示条可直接进入「命名」。
  - 书签支持自定义名称和备注：在书签面板点击「收藏当前页 / 编辑当前页」打开编辑对话框，或点击列表行的铅笔图标；备注会显示在书签列表中。
  - 书签持久化保存，可在导航面板中跳转、编辑或删除。
  - 缩略图网格按需渲染，可快速按画面定位；当前页有高亮边框。
- **格式支持**
  - PDF：基于 PDFium（`pdfrx`）按页渲染，扫描版与矢量 PDF 均可阅读。
  - **加密 PDF**：导入或打开时弹出解锁对话框，支持错误密码重试；密码只在本次运行的内存中缓存，不写入磁盘，重启后需重新输入。
  - MOBI：解析 PalmDB / MOBI 头、EXTH 封面与 HTML `<img recindex>` 阅读顺序，按需读取内嵌图片；100 MB 的卷不会整体读入内存，也不会因物理记录乱序而错页。
- **手机 / 平板适配**：书架列数随宽度变化，阅读器适配横竖屏与桌面窗口。
- **隐私**：全部本地处理，运行时不联网；导入文件只保存在本机；PDF 密码不落盘。

> 本仓库不包含用户提供的测试漫画 `test/VOL.001.pdf` / `.mobi`（体积大且含版权内容），也不提交本地截图。将样本放回 `test/` 后即可运行对应测试；界面截图可用 `tool/capture_screens.ps1` 在本地生成。

## 快速开始

### 环境要求

- Flutter **3.47+**（Dart 3.13+）
- Windows 构建需开启 **开发者模式**（Flutter 插件符号链接所需）
- Android 构建需要安装 **Android SDK**（本仓库不包含 SDK）
- iOS 构建需要 macOS + Xcode

### 运行

```bash
flutter pub get

# Windows 桌面（本机已验证）
flutter run -d windows

# Android（需先通过 flutter doctor 配置 SDK）
flutter run -d android

# iOS（在 macOS 上）
flutter run -d ios
```

### 打包

```bash
# Android（需配置签名）
flutter build apk --release

# Windows
flutter build windows --release
```

- Windows 产物：`build/windows/x64/runner/Release/`
- Android 产物：`build/app/outputs/flutter-apk/app-release.apk`

Debug / Release 两个版本均已在本地实机验证 PDF 与 MOBI 阅读；构建产物不提交到仓库。

本机没有 Android SDK / JDK，因此**未生成 APK**；Android 工程与依赖已经就绪，在装有 SDK 的机器上执行上面的命令即可。

> Windows 构建说明：正常情况下开启系统「开发者模式」即可。若无法开启，可手动为 `.flutter-plugins-dependencies` 里的 Windows 插件在 `windows/flutter/ephemeral/.plugin_symlinks/` 下创建目录 junction，然后使用 `flutter build windows --no-pub`（本项目开发环境即采用这种方式）。

## 使用说明

1. 打开应用，点击右下角「导入」，选择 PDF 或 MOBI（可多选）。
2. 如果选择的是加密 PDF，会弹出解锁对话框；密码错误会提示重试，取消则放弃本次导入。密码只在内存中保留到本次运行结束。
3. 导入完成后点击封面开始阅读；再次打开会自动回到上次的页码。加密 PDF 在同一运行会话内会复用内存中的密码，应用重启后再次打开需要输入。
4. 阅读界面：
   - 中间点击：显示 / 隐藏菜单。
   - 横向模式下点击屏幕左右两侧：上一页 / 下一页（双页模式下按跨页翻页）。
   - 双击：放大到 2.4×；再次双击复位。
   - 顶部按钮：返回、收藏 / 取消当前页书签、打开「目录 / 书签 / 缩略图」、切换阅读方向（横向模式）。
   - 底部：进度滑杆、上一页 / 下一页、页码（点击输入跳页）、双页开关（横向模式）、切换横向 / 纵向。
   - 双页模式：第 1 页单独显示（通常是封面），之后按 (2,3)、(4,5)… 成对展示；设置会自动保存。
   - 目录：PDF 优先使用内嵌 outline，MOBI 使用 HTML 标题；没有章节信息时回退到「每 20 页」的页码目录。
   - 书签：顶部书签图标快速收藏；提示条点击「命名」或导航面板的「收藏当前页 / 编辑当前页」/铅笔图标，可设置自定义名称和备注；备注会显示在书签列表中。
   - 桌面键盘：`←` / `→` 翻页，`空格` 下一页，`Esc` 返回书架。

## 数据存储

导入时会把文件复制到应用支持目录，原文件不会被修改或删除。

| 平台 | 应用数据目录（路径由 `path_provider` 决定） |
| --- | --- |
| Windows | `%APPDATA%\com.manhua\manhua_reader\ManhuaReader\` |
| Android | 应用私有 files 目录下的 `ManhuaReader/` |
| iOS | Application Support 下的 `ManhuaReader/` |

```
ManhuaReader/
├─ books/        # 导入的漫画副本
├─ covers/       # 自动生成的封面缩略图（PNG）
├─ cache/        # 预留缓存目录
└─ library.json  # 书架、阅读进度、阅读设置
```

删除书架条目只会删除 `books/` 下的副本和对应封面；原文件始终保留。

## 项目结构

```
lib/
├─ main.dart                  # 正式入口：初始化 PDFium、路径、书架
├─ main_demo.dart             # 演示/截图入口：导入 test/ 样本，支持 --open=pdf|mobi
├─ app.dart                   # MaterialApp 与鼠标拖动行为
├─ theme/                     # 深色暖色主题
├─ models/                    # ComicBook、ReaderSettings、LibrarySettings、Bookmark、TocEntry
├─ formats/
│  ├─ comic_source.dart       # 统一页面源接口（页面 / 缩略图 / 目录）
│  ├─ pdf_comic_source.dart   # pdfrx 渲染 + PDF outline 解析
│  ├─ mobi_comic_source.dart  # MOBI 图片页懒加载 + 缩略图
│  ├─ comic_source_factory.dart
│  └─ mobi/mobi_book.dart     # PalmDB / MOBI / EXTH / HTML 阅读顺序解析
├─ screens/
│  ├─ library_screen.dart     # 书架、搜索筛选、多选、导入、维护、存储管理
│  └─ reader_screen.dart      # 横/纵向、双页、缩放、菜单、跳页
├─ services/
│  ├─ app_paths.dart
│  ├─ library_repository.dart # 导入 / 重定位 / 封面 / 删除 / 存储统计 / 持久化
│  ├─ cover_generator.dart    # PDF / 图片封面缩略图
│  └─ pdf_password_cache.dart # 会话级密码缓存（不落盘）
├─ utils/pagination.dart      # 双页跨页配对
└─ widgets/
   ├─ book_cover.dart
   ├─ bookmark_editor_dialog.dart   # 书签名称 / 备注编辑
   ├─ library_storage_sheet.dart    # 存储统计与清理
   ├─ pdf_password_dialog.dart      # 加密 PDF 解锁对话框
   └─ reader_navigation_sheet.dart  # 目录 / 书签 / 缩略图面板
test/
├─ mobi_book_test.dart        # 真实 196 页 MOBI（含 HTML 阅读顺序）
├─ pdf_render_test.dart       # 真实 196 页 PDF 渲染
├─ pdf_password_test.dart     # 加密 PDF 打开 / 重试 / 带密码导入
├─ pdf_password_dialog_test.dart # 密码对话框输入 / 取消
├─ bookmark_editor_dialog_test.dart # 书签名称 / 备注对话框
├─ pagination_test.dart       # 双页配对逻辑
├─ library_repository_test.dart # 加载 / 保存 / 进度 / 书签 / 路径迁移
├─ library_p1_test.dart       # 视图/排序、重命名、存储清理、批量删除/已读、原子导入
├─ library_repair_test.dart   # 丢失文件重定位、封面重建、失败回滚
├─ library_p1_screen_test.dart # 搜索筛选、列表、多选、重命名、缺文件、存储面板
├─ library_screen_test.dart
├─ encrypted_sample.pdf       # 加密测试样本（密码 manhua123）
└─ VOL.001.pdf / .mobi        # 本地可选漫画样本（不随仓库提交）
tool/
├─ generate_icon.dart         # 生成 Android / iOS / Windows 图标
├─ make_small_pdf.dart        # 生成测试用小型 PDF（再用 qpdf 加密）
└─ capture_screens.ps1        # Windows 实机截图/交互验证脚本
```

## 测试

```bash
flutter analyze
flutter test
```

当前 41 个测试（本机样本齐全时全部通过；公开仓库不含 `test/VOL.001.*`，缺失的相关测试会自动跳过），包括：

- 真实样本 `test/VOL.001.mobi`：196 页、EXTH 封面、HTML `<img recindex>` 阅读顺序、尺寸解析、按页懒读取、非法文件拒绝。
- 真实样本 `test/VOL.001.pdf`：打开 196 页文档、确认无内嵌 outline、用 PDFium 渲染首页并读取像素。
- 加密样本 `test/encrypted_sample.pdf`（密码 `manhua123`）：正确密码打开、错误密码重试、取消时抛错、带密码导入并生成封面、未提供密码时清理副本。
- 密码对话框：输入返回、取消返回 null。
- 书签自定义名称与备注：编辑对话框预填 / 保存、空表单默认书签、名称与备注的持久化与清除。
- 双页配对逻辑（封面单页 + 后续成对）。
- 书架 JSON 的加载 / 保存 / 进度恢复 / 书签增删与持久化 / 损坏容错。
- P1 书架偏好：网格 / 列表与排序方式的持久化；重命名空白规整与持久化。
- P1 批量操作：批量删除文件 / 封面 / 密码缓存；批量标记已读与进度持久化。
- P1 存储管理：引用文件、缓存、无引用文件的统计与清理，清理后保留书架文件。
- P1 导入原子性：失败导入不会留下 `.part` 或半成品副本。
- P1 文件修复：重定位后保留标题 / 进度 / 书签，失败时不动原书；封面重建与源文件丢失处理。
- P1 书架 UI：搜索与空结果、格式 / 状态筛选、列表切换、多选 / 全选 / 退出、重命名、缺失文件提示、存储面板。
- iOS 等平台容器路径变化后的文件 / 封面路径自动迁移。
- 空书架界面冒烟测试。

如果对应的测试样本不存在，相关测试会自动跳过。首次构建 / 测试 Windows 版本时，`pdfium_dart` 的构建钩子会从 GitHub 下载 PDFium 原生库；之后使用缓存。

加密测试样本由 `tool/make_small_pdf.dart` 生成小型 PDF 后用 qpdf 加密（密码 `manhua123`）：

```bash
dart tool/make_small_pdf.dart
qpdf --encrypt manhua123 owner123 256 -- build/small_plain.pdf test/encrypted_sample.pdf
```

### 调试 / 截图入口

```bash
# 构建演示版本；启动时会自动导入 test/ 下的两个样本
flutter build windows --debug -t lib/main_demo.dart

# 直接打开指定格式的阅读器（从书架路由压栈，返回键可回书架）
build/windows/x64/runner/Debug/manhua_reader.exe --open=pdf --mode=vertical
build/windows/x64/runner/Debug/manhua_reader.exe --open=mobi --mode=horizontal
```

演示入口还支持 `--page=N`、`--bookmarks=1,10,50`、`--named-bookmarks`、`--double/--single`、`--encrypted`（导入加密测试样本）、`--cached-password`（用测试密码预填会话缓存），便于复现目录、书签、双页与密码流程截图。

`tool/capture_screens.ps1` 会用 `MANHUA_WINDOW_WIDTH/HEIGHT` 环境变量控制初始窗口尺寸，并自动截图，方便做手机 / 平板尺寸的视觉验收；`-Clicks "x,y;..."` 与 `-LongPresses "x,y;..."` 接受相对客户区的归一化坐标（0–1），可用于复现筛选、多选等交互。
备注：`windows/runner/main.cpp` 支持这两个环境变量，仅用于开发验收，正常启动不设置时保持 1280×800。

## 实现要点

- **MOBI**：读取 PalmDB 记录表、MOBI header、EXTH（含 `kindle:embed` 封面）与 HTML 文本记录；按 `<img recindex>` 顺序映射物理图片记录，修复 Calibre 等工具产生的乱序记录，并排除未引用的封面缩略图；最后把封面放在第一页。页面读取通过 `File.open` 按需完成。支持 JPEG / PNG / GIF / BMP / WebP 与 PalmDOC 文本解压；不支持 DRM 与纯文字 MOBI。
- **PDF**：`pdfrx` + PDFium，`PdfPageView` 根据可用尺寸按需渲染；矢量 / 扫描版都能显示。导入时渲染 520px 宽封面；`loadOutline()` 解析内嵌书签为章节目录。
- **加密 PDF**：通过 pdfrx 的异步 `PdfPasswordProvider` 接入密码对话框；密码错误时 pdfrx 会再次调用 provider，因此可以反复重试。成功使用的密码放在进程内存的 `PdfPasswordCache` 中，同一次运行内再次打开免密，退出应用即清除；`library.json` 不保存密码。
- **书签**：书签按页保存名称与备注；顶部图标提供快速收藏，书签面板的编辑按钮 / 铅笔图标打开编辑对话框；名称留空时回退为「第 N 页」，备注显示在书签列表中；`Bookmark` 随 `library.json` 持久化。
- **目录回退**：没有章节信息时生成每 20 页的页码目录，并与缩略图网格共同提供导航；书签可作为自定义章节。
- **双页**：`buildSpreads` 采用「封面单页 + (2,3)、(4,5)…」配对；每跨按可用宽高比缩放两页，RTL 时交换左右页；跨页整体支持双击缩放。
- **统一体验**：两种格式共用一个阅读器、同一套手势、模式、进度、书签与设置；MOBI 图片解码后以 `ui.Image` 管理生命周期，离屏即释放。
- **进度**：每页变化即时写入书架内存并做 450ms 去抖落盘；退出阅读器 / 应用进入后台时强制 flush。
- **P1 书架**：搜索与筛选在内存中完成，不改动书架顺序；排序 / 视图偏好与书架一起写入 `library.json`（schema `version: 2`）。重命名只改 `title`，原文件名保留用于重复检测。
- **P1 存储与修复**：`storageReport()` 按 `books/`、`covers/`、`cache/` 实际扫描，区分被引用文件、缓存与无引用文件；`cleanupStorage()` 只删除后两类。重定位 / 封面重建使用带时间戳的新文件名，避免 Flutter 图片缓存显示旧图；重定位成功后才删除旧文件并清理越界书签。
- **P1 原子导入**：所有导入先写 `<id>.ext.part`，复制完成后 `rename` 为目标文件；解析或封面失败时统一回滚副本、`.part` 与半成品封面。

## 已知限制

- **加密 PDF**：支持密码输入与错误重试；密码不写入磁盘，仅在本次运行的内存中缓存，应用重启后需要重新输入。受 DRM 保护的 MOBI 仍然无法读取。
- 纯文字 MOBI（小说型）不支持；当前按漫画图片书处理。
- MOBI 章节目前只从 HTML 标题（`<h1>`–`<h6>`）推导，未解析 NCX/INDX 二进制目录；没有章节的卷使用页码目录 + 缩略图回退。PDF 没有 outline 时同样回退。
- 双页模式仅用于横向模式，采用「封面单页」配对；暂不支持自动识别跨页扫描、自动裁边或左右装订方向自动判断。
- 书签名称/备注为纯文本，暂不支持富文本、搜索或跨书签分类。
- 批量操作（删除 / 标记已读）没有撤销；删除前会二次确认。
- Windows **Release** 增量构建在新增 Material 图标后，Flutter 的图标字体子集偶尔不会刷新，表现为按钮空白或图标缺失。遇到时删除 `build/windows/x64/runner/Release` 后重新执行 `flutter build windows --release --no-pub` 即可；Debug 构建不受影响。
- 放大为位图缩放，极限放大的清晰度受当前渲染分辨率限制。
- 暂无注释、夜间滤镜、自动翻页等功能。
- Web 平台未适配（本地文件存储依赖 `dart:io`），当前面向 Android / iOS / Windows。
- 当前环境无 Android SDK / JDK，因此未产出 APK。

## 应用图标

![应用图标](assets/app_icon.png)

`assets/app_icon.png` 为 1024px 主图标；Android mipmap、iOS AppIcon 与 Windows `app_icon.ico` 由 `tool/generate_icon.dart` 生成。

```bash
dart run tool/generate_icon.dart
```

## 说明

- 应用名：**漫阅**；Flutter package 名：`manhua_reader`。
- 运行样本测试前，可将自己的 `VOL.001.pdf` / `.mobi` 放入 `test/`；未放置时相关测试会自动跳过。

## License

本项目采用 [MIT License](LICENSE)。

