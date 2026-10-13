# 中文界面点阵来源

屏幕使用固定24×24点阵；仅包含界面需要的20个汉字和7个简谱数字，不是通用中文输入系统。

字体来源为 [Google Fonts 的 Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)，源许可为 [SIL Open Font License 1.1](https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/OFL.txt)，完整许可保存在本目录 `OFL.txt`。保留 Adobe 版权及 Reserved Font Name 声明；本项目点阵模块名是 `display_font24`。

2026-10-13使用本机已有 `C:/Windows/Fonts/NotoSansSC-VF.ttf`，24px、可变字重500、二值阈值96，按字形边界居中至24×24。字体SHA256写在生成RTL头部。本仓库不复制完整字体，只保留所需点阵、许可和转换脚本。

可重复生成（Python需Pillow）：

```powershell
python verification/scripts/generate_display_font.py C:/Windows/Fonts/NotoSansSC-VF.ttf rtl/display/display_font24.v
```

字形编号0为空白，1起依次为：`电子钢琴吉他音量弯低中高区延开关实时波形1234567`。

FPGA硬件不运行Python，也不读取操作系统字体；绘制器将字符编号送入常量点阵表。增加文案时同步更新此序列、字库与绘制器，不将UTF-8字节直接当成字形编号。
