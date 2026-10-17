# 中文界面点阵来源

新界面（`UI=1`）使用 2bit 覆盖度字模：58 个 24×24 正文字形与 7 个 48×48 标题字形，由 `verification/scripts/generate_ui_fonts.py` 离线生成到 `rtl/display/display_font_ui.v`。48px 标题为原生渲染，不再把 24px 点阵整数放大。旧 `UI=0` 兼容绘制器仍使用下述固定24×24点阵。当前57个字符含中文状态与音名；EXTENDED=1启用新增字符，基础31字符编号和旧测试参考保持不变，不是通用中文输入系统。

字体来源为 [Google Fonts 的 Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)，源许可为 [SIL Open Font License 1.1](https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/OFL.txt)，完整许可保存在本目录 `OFL.txt`。保留 Adobe 版权及 Reserved Font Name 声明；本项目点阵模块名是 `display_font24`。

2026-10-15数字改用本机canvas-design技能附带的Red Hat Mono Regular，来源[Red Hat官方字体仓库](https://github.com/RedHatOfficial/RedHatFont)，Copyright 2024 The Red Hat Project Authors，SIL OFL 1.1；版权声明合并在同目录OFL.txt。中文字形保持Noto Sans SC，等宽数字提高参数可读性，数字字体哈希也写入RTL头部。

2026-10-13使用本机已有 `C:/Windows/Fonts/NotoSansSC-VF.ttf`，24px、可变字重500、二值阈值96，按字形边界居中至24×24。字体SHA256写在生成RTL头部。本仓库不复制完整字体，只保留所需点阵、许可和转换脚本。

可重复生成（Python需Pillow）：

```powershell
python verification/scripts/generate_display_font.py C:/Windows/Fonts/NotoSansSC-VF.ttf rtl/display/display_font24.v --digits-font C:/Users/YUAN/.codex/skills/canvas-design/canvas-fonts/RedHatMono-Regular.ttf --reference verification/data/display_font_golden.mem
```

字形编号0为空白，1～31依次为：`电子钢琴吉他音量弯低中高区延开关实时波形1234567089半`。32～57为`静奏拨弦指位示意输出平倍率复声部就绪CDEFGABx`。正式同步ROM为2048×24，基础配置仍为1024×24；两个1024次初始化循环遵守Gowin默认展开限制。新增字形参考用--extended-reference生成，不覆盖旧参考以迎合结果。

FPGA硬件不运行Python，也不读取操作系统字体；绘制器将字符编号送入常量点阵表。增加文案时同步更新此序列、字库与绘制器，不将UTF-8字节直接当成字形编号。

2026-10-14审查优化：`display_font24` 的同步模式按字符/行读取1024×24位片内ROM，再选列，延迟一拍；原组合模式只服务无时钟单元检查，在生产显示中被裁剪。`verification/data/display_font_golden.mem` 是同一许可字体的64项整字形参考数据，用于独立验证组合/同步两种寻址及越界空白，不是旧版RTL。生成脚本可用 `--reference` 重建参考数据。

## 2bit 覆盖度字模（新界面）

```powershell
python verification/scripts/generate_ui_fonts.py C:/Windows/Fonts/NotoSansSC-VF.ttf rtl/display/display_font_ui.v --digits-font C:/Users/YUAN/.codex/skills/canvas-design/canvas-fonts/RedHatMono-Regular.ttf
```

生成器以 4 倍字号渲染后按面积降采样，再量化为 0/1/2/3 四级覆盖度；满墨像素与文字色完全相同。正文字形编号与旧字库不同，绘制器以 `instrument_panel_ui.v` 内的编号为准；字体 SHA256 写在生成文件头部。许可与来源仍是本目录的 Noto Sans SC / Red Hat Mono（SIL OFL 1.1）。
