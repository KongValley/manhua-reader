# 漫阅品牌标识

[完整预览](manhua-logo/preview.png)

标志是一张向右上倾斜的三格漫画页。主格的柠檬绿爆炸星和左下格的速度线表现动作，右下折角呼应翻页。

| 版本 | 文件 |
| --- | --- |
| 应用图标 | [SVG 源稿](manhua-logo/app-icon.svg) · [1024 × 1024 PNG](manhua-logo/app-icon.png) |
| 透明标志 | [SVG](manhua-logo/logo.svg) · [PNG](manhua-logo/logo.png) |
| 横版中英文组合 | [SVG](manhua-logo/logo-lockup.svg) · [PNG](manhua-logo/logo-lockup.png) |
| 单色标志 | [SVG](manhua-logo/logo-monochrome.svg) |

主色为蓝紫 `#3726CF`，纸白背景为 `#FFFAEF`，爆炸星为柠檬绿 `#DDF34D`。横版组合中的文字已经转为路径。

## 生成脚本

[初稿脚本](../../tool/branding/draft.py) 生成方案对照图 `build/branding/draft.png`。[导出脚本](../../tool/branding/export_logo.py) 生成正式 SVG、PNG 和预览图，输出目录由命令参数指定。

在项目根目录使用 Python 3.10 或更高版本运行。

```bash
python -m pip install PyMuPDF Pillow fonttools
python tool/branding/draft.py
python tool/branding/export_logo.py build/branding/manhua-logo
```

导出脚本从 `C:/Windows/Fonts` 读取 `SourceHanSansSC-Heavy.otf`、`SourceHanSansSC-Medium.otf` 和 `SourceSans3-Regular.ttf`，用于横版组合和预览中的文字。

将导出的 `app-icon.png` 同步到 [`assets/app_icon.png`](../app_icon.png) 后，在项目根目录运行 `dart run tool/generate_icon.dart`，即可更新 Android、iOS 和 Windows 的图标资源。
