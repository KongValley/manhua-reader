# 漫阅 · Manhua Reader

<p>
  <img src="assets/app_icon.png" width="88" alt="漫阅图标" />
</p>

面向 Windows、Android 手机与平板的本地漫画阅读器，支持 **PDF、MOBI、CBZ 和图片相册**。深色低光界面，横竖屏自适应，阅读进度自动保存。

## 功能

- **导入本地漫画**：支持多选 PDF / MOBI / CBZ，导入时复制到应用私有目录，不改动原文件。
- **图片相册**：选择一个 JPG / PNG / WebP / GIF / BMP 图片文件夹，作为一本相册引用；不复制图片，点开后先看图片网格。网格支持按名称、创建时间或修改时间升序 / 降序排列，并自动重映射阅读进度和书签。
- **书架**：封面缩略图、格式标签、页数、阅读进度、继续阅读卡片；读到最后一页的漫画显示绿色「已读完」角标与状态文案，续读卡片同步标注完成。卡片提供收藏 / 置顶 / 更多快捷操作（窄卡片自动移到底部），也可长按进入管理（只删应用内副本）。
- **书架整理（P1）**
  - 按书名 / 原始文件名即时搜索，未命中时提示清除筛选。
  - 按最近阅读、最近导入、书名、阅读进度排序；按 PDF / MOBI / CBZ、未读 / 阅读中 / 已读完筛选。
  - 网格 / 列表视图切换，偏好写入 `library.json`，下次启动保留。
  - 长按进入多选，可批量收藏、置顶、标记已读或未读、移动文件夹、设置系列、添加或移除标签及删除。书架确认删除后可在撤销时限内恢复。
  - 重命名只修改书架显示名；丢失文件可重新定位替换，保留进度与书签；封面可手动重建。
  - 存储管理显示总占用、每本书占用、缓存与无引用文件，并支持一键清理。
- **系列与整理（P2）**
  - 每本书可设置系列 / 合集名与最多 20 个标签；同名系列可在「系列合集」页合并展示，并按卷查看。
  - 支持收藏与置顶：网格和列表卡片均可快捷切换，多选可批量设置；置顶书始终排在普通书之前；收藏书可一键筛选。
  - 支持自定义封面（本地图片）与恢复自动生成封面。
  - 搜索索引覆盖书名、原始文件名、系列与标签，并可匹配文件夹名和拼音首字母。例如输入 `hzw` 可搜到「海贼王」。
- **文件夹与拖拽导入**
  - 桌面端可选择文件夹递归导入 PDF / MOBI / CBZ，或把文件 / 文件夹拖进书架。
  - Android 通过 Storage Access Framework 选择文件夹，递归列出并通过原生通道复制导入。
  - 按文件夹导入时保留所选目录为一个书架文件夹；文件夹卡片显示名称、书籍数与平均进度。
  - 已导入的漫画可移动到已有或新建的书架文件夹，也可移回根目录。删除书架文件夹时，其书籍移回根目录并保留进度和书签。
- **阅读统计（P2）**：按本地日期记录每日翻页页数、有效阅读时长与分书阅读历史，支持每日阅读目标；展示今日、本周、累计、连续阅读天数、最近 7 天柱状图，以及支持「近一年」与按年份切换的**年度阅读热力图**（点击格子可联动预览当天阅读书目并定位到每日时间明细）；书架与阅读器顶栏同步显示今日阅读时长进度。
- **备份与恢复（P2）**
  - 导出 JSON：书架、文件夹、进度、书签、系列、标签、收藏、置顶与统计；不含漫画文件。
  - 导出完整 `.mrbackup`（ZIP）：以流式写入包含漫画文件与封面；Android / 桌面端通过系统文件流保存，支持大体积书架导出与流式文件恢复。
  - 恢复时合并到当前书架与同名文件夹，自动跳过重复；JSON 恢复缺失文件时标记「文件丢失」，可逐本重新定位。
- **可靠导入**：多文件顺序导入，显示当前 / 总数 / 成功 / 失败与百分比；支持取消剩余任务；先写 `.part` 临时文件再原子改名，失败自动回滚。
- **阅读器**
  - 横向翻页（PageView）与纵向连续滚动两种模式，切换时保留当前页。
  - **仿真纸张翻页**：横向拖动时纸页随手势卷起，露出纸背与下一页，松手后翻过或回弹。点按页边和使用方向键也可触发，适用于 PDF、MOBI、CBZ 的单页和双页。
  - **阅读设置**：顶栏可调屏幕常亮、画面亮度、暖色滤镜、自动翻页、Android 音量键翻页和纸张 / 滑动动画，设置随书架保存。
  - **按书记忆**：每本书可保留横纵模式、阅读方向、单双页和双页配对，可改回跟随默认设置。双页配对可从首页开始，或让前一页、前两页单独显示。
  - **续卷与导航**：读到本卷末尾可直接打开系列下一卷。顶栏显示当前章节，进度条标出书签位置。
  - **缩放与裁边**：PDF 放大时会重新渲染，图片页按原图分辨率重新解码。设置中的自动裁边可减少连续的空白页边。
  - 点屏幕两侧翻页或纵向滚动，可在设置中调整区域宽度。中间点按切换菜单，工具栏的锁定按钮可防止误触翻页。
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
  - **加密 PDF**：导入或打开时弹出解锁对话框，支持错误密码重试；默认仅在当前运行期间缓存。可在 Windows 或 Android 的解锁对话框中勾选「记住此设备」，以后可在书籍菜单中忘记密码。
  - MOBI：解析 PalmDB / MOBI 头、EXTH 封面与 HTML `<img recindex>` 阅读顺序，按需读取内嵌图片；复用单个文件句柄并用小容量 LRU 缓存最近页面，100 MB 的卷不会整体读入内存，也不会因物理记录乱序而错页。
  - CBZ：使用 ZIP 容器，按中央目录随机读取，图片按文件名自然排序，不整包读入内存；打开时只抽样首页尺寸，其余页面在进入阅读窗口时渐进解析；支持嵌套目录和章节目录。
  - 图片相册：引用原文件夹，可按名称 / 创建时间 / 修改时间升序或降序排列；子文件夹作为章节；文件夹增删图片后下次打开自动生效。
- **手机 / 平板 / 桌面自适应**：Android 手机与平板已合并为单一安装包，按屏幕宽度自动切换 2–6 列书架、横排英雄卡片、双列列表、居中自适应底部弹窗与阅读器工具栏；同时支持桌面窗口自由缩放。
- **隐私**：全部本地处理，运行时不联网；导入文件只保存在本机；PDF 密码不会写入书架或导出的备份。选择记住密码后，凭据由设备的安全存储保护。

> 本仓库不包含用户提供的测试漫画 `test/VOL.001.pdf` / `.mobi`（体积大且含版权内容），也不提交本地截图。将样本放回 `test/` 后即可运行对应测试；界面截图可用 `tool/capture_screens.ps1` 在本地生成。

## 快速开始

### 环境要求

- Flutter **3.47+**（Dart 3.13+）
- Windows 构建需开启 **开发者模式**（Flutter 插件符号链接所需）
- Android 构建需要 **Android SDK 36** 与 **JDK 17**；设置 `ANDROID_HOME` / `JAVA_HOME` 后运行 `flutter doctor` 确认
- iOS 构建需要 macOS + Xcode

### 运行

```bash
flutter pub get

# Windows 桌面
flutter run -d windows

# Android 手机 / 平板（按设备宽度自适应）
flutter run -d android

# iOS（在 macOS 上）
flutter run -d ios
```

### 打包构建

```bash
# PC 桌面端（Windows x64）
flutter build windows --release --no-pub

# Android 通用自适应包（支持手机、折叠屏与平板）
flutter build apk --release --no-pub
```

产物：

| 端 | 产物 | 包名 / 说明 |
| --- | --- | --- |
| PC Windows | `build/windows/x64/runner/Release/` | Windows 10/11 x64 便携版 |
| Android（手机 / 平板自适应） | `build/app/outputs/flutter-apk/app-release.apk` | `com.manhua.manhua_reader`，桌面名「漫阅」 |

- 手机、折叠屏与平板统一使用同一 APK，按屏幕宽度自适应：手机 2 列，平板 / 桌面按宽度 3–6 列，英雄卡片与列表双列自动切换，底部弹窗宽屏居中约束。
- 桌面版为便携 ZIP。需要在资源管理器「打开方式」中出现漫阅时，在「设置 → 存储管理」中打开「注册 Windows『打开方式』」；它只把漫阅加入 PDF / MOBI / CBZ 的候选程序，不改动系统默认应用。
- Android 版本注册了 PDF / MOBI / CBZ 的 `ACTION_VIEW`，可从文件管理器直接交给漫阅打开，重复文件会复用书架中内容一致的副本。
- 当前 Android Release 使用调试签名，适合侧载测试；上架应用商店前需配置正式签名。

> Windows 构建说明：正常情况下开启系统「开发者模式」即可。若无法开启，可手动为 `.flutter-plugins-dependencies` 里的 Windows 插件在 `windows/flutter/ephemeral/.plugin_symlinks/` 下创建目录 junction，然后使用 `flutter build windows --no-pub`（本项目开发环境即采用这种方式）。

## 使用说明

1. 打开应用，点击「导入」，选择 PDF、MOBI 或 CBZ，也可以导入图片相册或文件夹。
2. 加密 PDF 会弹出解锁对话框。密码错误时可以重试，取消会结束此次解锁。
3. 点击封面开始阅读，再次打开会回到上次的页码。文件管理器也可以通过「打开方式」交给漫阅，Windows 命令行可传入带引号的文件路径。
4. 阅读界面：
   - 中间点击：显示 / 隐藏菜单。
   - 横向模式下点击屏幕左右两侧：上一页 / 下一页（双页模式下按跨页翻页）。
   - 双击：放大到 2.4×；再次双击复位。
   - 顶部按钮：返回、收藏 / 取消当前页书签、打开「目录 / 书签 / 缩略图」、切换阅读方向（横向模式）。
   - 底部：进度滑杆、上一页 / 下一页、页码（点击输入跳页）、双页开关（横向模式）、切换横向 / 纵向。
   - 双页模式默认让封面单独显示。可在阅读设置中根据扫描件改为首页起成对，或前两页单独显示。
   - 目录：PDF 优先使用内嵌 outline，MOBI 使用 HTML 标题；没有章节信息时回退到「每 20 页」的页码目录。
   - 书签：顶部书签图标快速收藏；提示条点击「命名」或导航面板的「收藏当前页 / 编辑当前页」/铅笔图标，可设置自定义名称和备注；备注会显示在书签列表中。
   - 桌面键盘支持方向键、`Page Up`、`Page Down`、`空格`、`Home`、`End` 和 `Esc`。纵向模式下，上下方向键、翻页键和空格按视口滚动。

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

选择「记住此设备」的 PDF 密码不写入上表目录、`library.json` 或备份文件：Windows 使用当前用户的 DPAPI 加密后保存在 `%LOCALAPPDATA%\ManhuaReader\PdfPasswords`，Android 使用 Keystore 加密并保存在应用私有目录之外可还原的 `noBackupFilesDir`，卸载应用即失效。

## 项目结构

```
lib/
├─ main.dart                  # 正式入口：初始化 PDFium、路径、书架
├─ main_demo.dart             # 演示/截图入口：导入 test/ 样本，支持 --open=pdf|mobi
├─ app.dart                   # MaterialApp 与鼠标拖动行为
├─ theme/                     # 深色暖色主题
├─ models/                    # ComicBook、LibraryFolder、ReaderSettings、LibrarySettings、ReadingStats、Bookmark
├─ formats/
│  ├─ comic_source.dart       # 统一页面源接口（页面 / 缩略图 / 目录）
│  ├─ pdf_comic_source.dart   # pdfrx 渲染 + PDF outline 解析
│  ├─ mobi_comic_source.dart  # MOBI 图片页懒加载 + 缩略图
│  ├─ comic_source_factory.dart
│  ├─ comic_page_crop.dart    # 每页空白边检测与裁边缓存
│  ├─ page_raster.dart        # 各格式的目标分辨率渲染接口
│  └─ mobi/mobi_book.dart     # PalmDB / MOBI / EXTH / HTML 阅读顺序解析
├─ screens/
│  ├─ library_screen.dart     # 书架、搜索筛选、多选、文件夹、导入、备份、统计
│  ├─ folder_screen.dart      # 文件夹内书籍、重命名 / 删除文件夹
│  ├─ series_screen.dart      # 系列合集与卷列表
│  └─ reader_screen.dart      # 横/纵向、双页、缩放、菜单、跳页
├─ services/
│  ├─ app_paths.dart
│  ├─ library_repository.dart # 导入 / 重定位 / 封面 / 删除 / 文件夹 / 组织 / 统计 / 备份
│  ├─ library_index.dart      # 标题 / 拼音首字母 / 系列 / 标签增量索引
│  ├─ folder_import.dart      # 文件夹 / 拖拽路径扫描
│  ├─ saf_folder_service.dart # Android SAF 文件夹通道
│  ├─ cover_generator.dart    # PDF / 图片封面缩略图
│  ├─ external_open_channel.dart # Windows / Android 文件打开通道
│  ├─ pdf_password_cache.dart # 会话级密码缓存（不落盘）
│  ├─ pdf_password_flow.dart  # 会话、设备存储与输入框的尝试顺序
│  └─ pdf_password_store.dart # 可选设备密码存储（DPAPI / Keystore）
├─ utils/
│  ├─ adaptive_layout.dart       # 手机 / 折叠屏 / 平板 / 桌面自适应断点与弹窗容器
│  ├─ pagination.dart            # 双页跨页配对
│  ├─ reading_clock.dart         # 有效阅读时长
│  └─ series.dart                # 从标题 / 文件名推导系列名
└─ widgets/
   ├─ book_cover.dart
   ├─ bookmark_editor_dialog.dart   # 书签名称 / 备注编辑
   ├─ book_organization_dialog.dart # 系列 / 标签编辑
   ├─ folder_name_dialog.dart       # 文件夹重命名
   ├─ library_storage_sheet.dart    # 存储统计与清理
   ├─ reading_stats_sheet.dart      # 阅读统计
   ├─ backup_sheet.dart             # JSON / ZIP 备份与恢复
   ├─ comic_page_image.dart         # 按缩放请求目标分辨率并套用裁边
   ├─ library_deletion_undo.dart    # 删除撤销条
   ├─ pdf_password_dialog.dart      # 加密 PDF 解锁对话框
   ├─ reader_navigation_sheet.dart  # 目录 / 书签 / 缩略图面板
   └─ slider_ticks.dart             # 进度条上的书签刻度
test/
├─ mobi_book_test.dart        # 真实 196 页 MOBI（含 HTML 阅读顺序）
├─ pdf_render_test.dart       # 真实 196 页 PDF 渲染
├─ pdf_password_test.dart     # 加密 PDF 打开 / 重试 / 带密码导入
├─ pdf_password_dialog_test.dart # 密码对话框输入 / 取消 / 记住设备选项
├─ reader_screen_test.dart   # 点击区域 / 锁定 / 快捷键 / 切卷 / 设置重置
├─ library_p3_test.dart      # 书架移动 / 批量组织 / 撤销 / 时长 / 配对偏移
├─ comic_page_render_test.dart # 四种格式目标分辨率渲染与裁边
├─ reading_clock_test.dart   # 阅读计时区间
├─ bookmark_editor_dialog_test.dart # 书签名称 / 备注对话框
├─ pagination_test.dart       # 双页配对逻辑
├─ reading_stats_test.dart    # 周统计 / 连续天数 / 合并 / 序列化
├─ series_test.dart           # 系列名推导
├─ library_index_test.dart    # 增量索引
├─ folder_import_test.dart    # 文件夹 / 拖拽扫描
├─ library_repository_test.dart # 加载 / 保存 / 进度 / 书签 / 路径迁移
├─ library_p1_test.dart       # 视图/排序、重命名、存储清理、批量删除/已读、原子导入
├─ library_p2_test.dart       # v3 迁移、组织/收藏/置顶、统计、自定义封面、备份
├─ library_folder_test.dart   # 文件夹创建/复用/重命名/删除、备份、v4 迁移
├─ library_repair_test.dart   # 丢失文件重定位、封面重建、文件夹导入、失败回滚
├─ library_p1_screen_test.dart # 搜索筛选、列表、多选、重命名、缺文件、存储面板
├─ library_p2_screen_test.dart # 收藏/系列/标签筛选、系列页、组织编辑、统计/备份面板
├─ library_folder_screen_test.dart # 文件夹分组、重命名/删除、跨文件夹搜索
├─ library_screen_test.dart
├─ daily_reading_time_test.dart # 每日阅读时长记录、阅读目标、分书日志与 UI 展示
├─ adaptive_layout_test.dart  # 手机 / 平板自适应断点、弹窗约束与响应布局测试
├─ bugfix_regression_test.dart # 模型容错、串行存储、安全备份恢复与多选生命周期回归
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

公开仓库不含 `test/VOL.001.*`。缺失样本时，相应测试会自动跳过。本机样本齐全时共 190 项测试。

- 年度阅读热力图与自适应布局：全年 / 跨年贡献网格与区间统计、热力格子联动当日书目明细、手机 / 平板断点、宽屏双列列表、英雄卡片横排及居中弹窗约束。
- 每日阅读时间记录与目标：今日时长进度条、每日目标达成、分书阅读时间日志及统计面板交互。
- 稳定性与安全回归：MOBI LZ77 解压与 `extraDataFlags`、WebP/BMP/EXIF 尺寸解析、有界 ZIP 解压与 ZIP64 越界保护、损坏条目录容错、串行存储操作、流式备份与路径穿越拦截、多选同步与弹窗生命周期。

- 真实样本 `test/VOL.001.mobi`：196 页、EXTH 封面、HTML `<img recindex>` 阅读顺序、尺寸解析、按页懒读取、最近页缓存、关闭后拒绝读取、非法文件拒绝。
- 真实样本 `test/VOL.001.pdf`：打开 196 页文档、确认无内嵌 outline、用 PDFium 渲染首页并读取像素。
- 加密样本 `test/encrypted_sample.pdf`（密码 `manhua123`）：正确密码打开、错误密码重试、取消时抛错、带密码导入并生成封面、未提供密码时清理副本。
- 密码对话框：输入返回、取消返回 null。
- 书签自定义名称与备注：编辑对话框预填 / 保存、空表单默认书签、名称与备注的持久化与清除。
- 双页配对逻辑（封面单页 + 后续成对）。
- CBZ 按需尺寸：打开只抽样页头，其余页按需解析并通知阅读器重排。
- 本地相册按需尺寸：目录列表不再读取每张图片头，进入阅读窗口后再解析并重排。
- SAF 相册头部：原生通道只读取尺寸探测需要的图片前缀。
- 系列完成角标：仅当系列内全部卷都读完时显示，避免继承首卷状态。
- 书架 JSON 的加载 / 保存 / 进度恢复 / 书签增删与持久化 / 损坏容错。
- P1 书架偏好：网格 / 列表与排序方式的持久化；重命名空白规整与持久化。
- P1 批量操作：批量删除文件 / 封面 / 密码缓存；批量标记已读与进度持久化。
- P1 存储管理：引用文件、缓存、无引用文件的统计与清理，清理后保留书架文件。
- P1 导入原子性：失败导入不会留下 `.part` 或半成品副本。
- P1 文件修复：重定位后保留标题 / 进度 / 书签，失败时不动原书；封面重建与源文件丢失处理。
- P1 书架 UI：搜索与空结果、格式 / 状态筛选、列表切换、多选 / 全选 / 退出、重命名、缺失文件提示、存储面板。
- P2 数据与组织：v2 → v3 迁移、系列推导、系列 / 标签 / 收藏 / 置顶持久化、置顶排序。
- P2 统计与封面：日 / 周 / 连续阅读统计、JSON 往返与合并、自定义封面校验。
- P2 备份：JSON 清单、完整 ZIP（文件 + 封面）、重复跳过、缺失文件恢复、无效备份拒绝。
- P2 导入与 UI：文件夹 / 拖拽路径扫描、收藏/系列/标签筛选、卡片快捷收藏 / 置顶、批量收藏 / 置顶、系列合并页、组织信息编辑、统计与备份面板。
- 文件夹：创建/复用、重命名冲突、删除保留书籍、备份恢复、v4 迁移、主页文件夹卡片、文件夹页与跨文件夹搜索。
- 书架管理：移动到文件夹、移回根目录、批量设置系列 / 标签、标记未读、延迟删除与撤销、撤销状态随书架持久化，以及备份恢复与待删除条目的去重。
- 搜索与统计：拼音首字母匹配、有效阅读时长的按日 / 周 / 累计统计。
- 阅读器：按书保存阅读方式、双页配对、点击区域、触摸锁定、纵向滚动与末页、切卷完成状态、章节名、书签刻度、阅读计时边界。
- 页面渲染：四种格式的目标分辨率重新渲染、空白边裁边、缩放请求去重与过期结果释放、裁边后的纸张翻卷。
- 密码记忆：默认关闭、成功后保存、旧密码失效重试、重定位与删除清理、存储不可用时继续解锁。
- 文件打开：Windows 命令行与运行中转发、重名同大小但内容不同的文件、Android 清单与暂存文件。
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
备注：`windows/runner/main.cpp` 支持这两个环境变量，仅用于开发验收，普通启动会恢复上次保存的窗口大小、位置和最大化状态。

## 实现要点

- **MOBI**：读取 PalmDB 记录表、MOBI header、EXTH（含 `kindle:embed` 封面）与 HTML 文本记录；按 `<img recindex>` 顺序映射物理图片记录，修复 Calibre 等工具产生的乱序记录，并排除未引用的封面缩略图；最后把封面放在第一页。页面读取在首次访问时打开文件句柄，之后复用，并以 6 页 / 48 MB 上限缓存最近页面。支持 JPEG / PNG / GIF / BMP / WebP 与 PalmDOC 文本解压；不支持 DRM 与纯文字 MOBI。
- **PDF**：`pdfrx` + PDFium，`PdfPageView` 根据可用尺寸按需渲染；矢量 / 扫描版都能显示。导入时渲染 520px 宽封面；`loadOutline()` 解析内嵌书签为章节目录。
- **加密 PDF**：通过 pdfrx 的异步 `PdfPasswordProvider` 接入密码对话框；密码错误时 pdfrx 会再次调用 provider，因此可以反复重试。成功使用的密码默认由 `PdfPasswordCache` 在本次会话内复用。开启设备记忆后，Android 使用 Keystore，Windows 使用 DPAPI。
- **书签**：书签按页保存名称与备注；顶部图标提供快速收藏，书签面板的编辑按钮 / 铅笔图标打开编辑对话框；名称留空时回退为「第 N 页」，备注显示在书签列表中；`Bookmark` 随 `library.json` 持久化。
- **目录回退**：没有章节信息时生成每 20 页的页码目录，并与缩略图网格共同提供导航；书签可作为自定义章节。
- **双页**：`buildSpreads` 采用「封面单页 + (2,3)、(4,5)…」配对；每跨按可用宽高比缩放两页，RTL 时交换左右页；跨页整体支持双击缩放。
- **统一体验**：两种格式共用一个阅读器、同一套手势、模式、进度、书签与设置；MOBI 图片解码后以 `ui.Image` 管理生命周期，离屏即释放。
- **进度**：每页变化即时写入书架内存并做 450ms 去抖落盘；退出阅读器 / 应用进入后台时强制 flush。
- **P1 书架**：搜索与筛选在内存中完成，不改动书架顺序；排序 / 视图偏好与书架一起写入 `library.json`（当前 schema `version: 5`）。重命名只改 `title`，原文件名保留用于重复检测。
- **P1 存储与修复**：`storageReport()` 按 `books/`、`covers/`、`cache/` 实际扫描，区分被引用文件、缓存与无引用文件；`cleanupStorage()` 只删除后两类。重定位 / 封面重建使用带时间戳的新文件名，避免 Flutter 图片缓存显示旧图；重定位成功后才删除旧文件并清理越界书签。
- **P1 原子导入**：所有导入先写 `<id>.ext.part`，复制完成后 `rename` 为目标文件；解析或封面失败时统一回滚副本、`.part` 与半成品封面。
- **P2 组织与索引**：`LibraryIndex` 在启动时构建，并在导入、删除、重命名、系列/标签编辑时增量更新；搜索覆盖书名、原始文件名、系列与标签，文件夹名在 `matchesSearch()` 中额外匹配。`LibrarySort` 排序前先比较 `pinned`；收藏只影响筛选。
- **P2 系列**：导入时用 `deriveSeriesName()` 从 `VOL.001`、`第12卷`、`v03` 等标题推导系列提示；用户可在「系列与标签」中覆盖。系列名按大小写不敏感分组，卷内按标题排序。
- **P2 阅读统计**：`ReadingStats` 按本地日期记录前进页数（只统计页码增大），提供今日、本周、连续天数、最长连续与最近 7 天数据；无数据时显示空态；批量标记已读不计入翻页统计。
- **P2 备份**：JSON 清单使用相对路径（不含文件字节）；完整备份用 `archive` 流式写入 `cache/` 后再导出 `.mrbackup`。恢复按 id / 原始名+大小跳过重复，ZIP 中的文件逐本写入 `.part` 后改名，统计按每日最大值合并。
- **书架文件夹**：文件夹导入按所选目录 `ensureFolder()`（同名复用）创建 `LibraryFolder`，递归扫描到的文件统一归入该文件夹；`ComicBook.folderId` 随 schema v4 持久化。主页文件夹卡片显示名称 / 数量 / 平均进度，支持重命名与删除（删除时 `folderId` 置空，书籍回到根目录）。搜索 / 筛选激活时隐藏文件夹卡片并跨文件夹平铺结果。
- **文件夹备份**：备份清单包含 `folders` 与每本书的 `folderId`；恢复时按文件夹名复用或新建本地文件夹，并把备份 id 映射到本地 id。
- **P2 导入入口**：FAB 提供「文件 / 文件夹」选择；桌面端文件夹递归扫描，Windows / Linux / macOS 支持把文件或文件夹拖入窗口；Android 使用 `manhua/saf` 原生通道列出并复制 SAF 文档。
- **P2 自定义封面**：`setCustomCover()` 将本地图片解码并缩放到 520px PNG；`customCover` 随书保存，重新生成封面会恢复自动封面。
- **按书阅读偏好**：`ComicBook.readingMode / rightToLeft / doublePage / spreadOffset` 为可空字段，空值表示跟随 `settings` 全局默认；阅读器一次性解析生效值，重置只清除这些字段。
- **页面渲染**：`ComicPageImage` 根据容器尺寸、设备像素比和缩放档位请求目标分辨率，PDF 重新渲染，MOBI / CBZ / 相册从原图重新解码，并按原生尺寸和像素预算截断；新图就绪前保留旧图。`ComicPageLayoutSource` 让 CBZ 与本地相册先使用估算尺寸，在进入阅读窗口时解析真实尺寸并局部重排，避免打开时扫描全书；`PageView` 一屏缓存与纵向 1200px 缓存共同构成有界预加载窗口。`ComicPageCropController` 用低分辨率预览缓存每页裁边比例，静止画面、滑动翻页和纸张翻卷共用同一矩形。
- **撤销删除**：待删除书籍从书架移除但保留文件与密码，截止时间写入 `library.json`；撤销直接放回书架；超过时限（或下次启动时发现已超时）会完成不可逆删除。备份恢复、存储清理和外部打开会把待删除条目视为占用，避免重复条目或误删文件。
- **拼音搜索**：`LibraryIndex` 为书名、原文件名、系列和标签额外保存拼音首字母，查询只含拉丁字母和数字时同时匹配首字母。
- **阅读时长**：`ReadingClock` 用单调时钟累计，只在页面打开、应用在前台且路由可见时计时，跨弹层、切卷和后台按真实区间结算。
- **安全存储**：`PdfPasswordStore` 通过 `manhua/pdf_password_store` 通道访问 Windows DPAPI 与 Android Keystore；只有成功解锁且用户勾选「记住此设备」后才写入，删除最终确认时清理，撤销期间保留。

## 已知限制

- 受 DRM 保护的 MOBI 无法读取。
- 纯文字 MOBI（小说型）不支持；当前按漫画图片书处理。
- MOBI 章节目前只从 HTML 标题（`<h1>`–`<h6>`）推导，未解析 NCX/INDX 二进制目录；没有章节的卷使用页码目录 + 缩略图回退。PDF 没有 outline 时同样回退。
- 双页模式用于横向阅读。跨页扫描和装订方向由用户调整。
- 书签名称/备注为纯文本，暂不支持富文本、搜索或跨书签分类。
- 标记未读会重置阅读进度并保留书签。
- P2 的「增量索引」目前是进程内索引，`library.json` 仍是唯一持久化来源；SQLite / Isar 迁移按方案保留，适合书架超过约 1000 本后再引入。
- 文件夹导入保留**所选目录这一层**，内部子目录会递归合并到同一个书架文件夹，不建立嵌套目录树；删除文件夹只把书籍移回根目录。文件夹名称大小写不敏感去重。
- 完整 ZIP 备份与恢复在 Android 与桌面端均采用原生/临时文件流式读写，避免一次性加载整包到内存；超大书架建议保留充足可用磁盘空间后再导出。
- Android SAF 文件夹导入通过原生 `MethodChannel` 实现，已在 Android 15 模拟器验证文件夹授权、PDF/MOBI 导入、CBZ 单文件导入和图片相册引用；真机外接存储仍建议验收。Windows Release 已验证文件夹选择、拖拽和 CBZ 导入。
- 系列名推导是启发式规则，可能误判特殊标题；可在「系列与标签」中手动修正。
- 阅读统计的页数按翻页页数而非去重页面统计，使用页码滑杆跳页会按跨越页数计入。时长只累计页面已打开、应用在前台且阅读器可见的时间，目录、设置等弹层和阅读器初始加载不计入。
- 删除后的撤销时限约 6 秒；未撤销时书架会随 `library.json` 一起保存待删除状态，关闭应用后按记录的截止时间继续处理。
- Windows **Release** 增量构建在新增 Material 图标后，Flutter 的图标字体子集偶尔不会刷新，表现为按钮空白或图标缺失。遇到时删除 `build/windows/x64/runner/Release` 后重新执行 `flutter build windows --release --no-pub` 即可；Debug 构建不受影响。
- 极限放大的清晰度受原图分辨率和设备渲染预算限制。
- 仅支持 CBZ 图片包；CBR / RAR、普通 .zip 压缩包和加密 ZIP 暂不支持。
- 图片相册只引用原文件夹：文件夹移动、删除或 Android 授权失效后会打不开，需要重新选择文件夹；删除书架条目不会删除原图片。
- 图片相册不随完整备份打包图片，只备份书架信息与封面；GIF / 动画 WebP 只显示第一帧。Android SAF 通常不提供图片创建时间，创建时间排序会回退使用修改时间。
- 自动翻页、画面亮度、暖色滤镜和屏幕常亮为全局设置，阅读方式按书保存并可改回跟随全局。书签随书架备份迁移。
- 自动裁边只处理连续的纯白 / 透明页边，深色扫描件或内容贴近边缘时保留完整页面；放大后的清晰度仍受原图分辨率限制。
- 音量键翻页仅在 Android 阅读器内生效；模拟器按键注入未能验证，需在真机或外接键盘上确认。
- Web 平台未适配（本地文件存储依赖 `dart:io`），当前面向 Android / iOS / Windows。
- 手机 / 平板 APK 已构建并通过 `apksigner` 校验；已在 Android 15 模拟器验证 PDF/MOBI/CBZ 导入、阅读、双页、纸张翻页和图片相册网格，真机外接存储仍建议验收。

## 应用图标

![应用图标](assets/app_icon.png)

[`assets/app_icon.png`](assets/app_icon.png) 是应用内共用的 1024 × 1024 主图标。[品牌标识](assets/branding/README.md) 提供 SVG 源稿和使用预览。更新主图标后，运行以下命令生成 Android mipmap、iOS AppIcon 和 Windows `app_icon.ico`。

```bash
dart run tool/generate_icon.dart
```

## 说明

- 应用名：**漫阅**；Flutter package 名：`manhua_reader`。
- 运行样本测试前，可将自己的 `VOL.001.pdf` / `.mobi` 放入 `test/`；未放置时相关测试会自动跳过。

## License

本项目采用 [MIT License](LICENSE)。

