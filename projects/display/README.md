# 800×480中文RGB显示：仅综合工程

高云EDA打开 `display_rgb.gprj`，顶层为 `instrument_display`。目标器件沿用GW5AT-LV60PG484AC1/I0/B，屏幕未选定。没有CST、板级SDC和像素PLL，不直接上板。

仓库根目录运行：

```powershell
./verification/scripts/check_verilog.ps1
./verification/scripts/run_display_tests.ps1
./projects/display/build.ps1
```

脚本只执行 `run syn`，不会布局布线、烧录或覆盖原钢琴位流。六个显示RTL位于 `rtl/display/`，提供中文钢琴/吉他标题、13琴键、音量、弯音、音区、延音、实时波形。

详见 [接口与接入说明](../../docs/display-rgb.md) 和 [验证证据](../../docs/reports/display-20261013/README.md)。界面吉他状态不意味着已将吉他音色接入主钢琴工程。

构建前恢复本目录受控`process_config.json`；默认证据目录为`build/display/synthesis/`，可用`-EvidenceDirectory`更改。原显示报告保留其原日期与源哈希，路径迁移后须重新综合，不能沿用旧报告声称当前构建已通过。
