# 高云 FPGA 钢琴／摇滚电子乐器

当前版本 **music-classic16**：钢琴 v3＋经典摇滚、共享 16 复音、UART 演奏、全局音量及连续 ±2 半音弯音。声音由 FPGA 逐样本实时合成，电脑只发送控制事件。

用户在经典摇滚新版试听后反馈“应该是可以了”，记录为初步可用；没有据此勾选完整音质、长时间稳定性和整机延迟验收。

## 唯一主工程与目录

沿用队友 master 的目录分工。本地基线 `0406c609afe2cdc1a204b719dedf3054cb4c2157`；本次获取远程失败，不能确认远程是否有更新。保留本地集成修改，未提交或推送。

| 目录／入口 | 当前用途 |
| --- | --- |
| [projects/piano/uart_piano.gprj](projects/piano/uart_piano.gprj) | 唯一可烧录主工程，顶层 `music_uart_top` |
| [rtl/synth](rtl/synth/) | A：`voice_bank_music_pipe.v`＋`instrument_env.v`，一套合成与包络实现 |
| [rtl/rom](rtl/rom/) | 四份有效表：模态参数、正弦、失真、弯音比例 |
| [model](model/) | A 的参数生成、参考来源、独立定点模型和音域／音色分析 |
| [rtl/control](rtl/control/) | 事件、声部分配、UART及参数平滑；保留C模块测试入口 |
| [rtl/audio](rtl/audio/)／[rtl/top](rtl/top/) | B 的音频输出及公共系统／板级／显示接入 |
| [projects/display](projects/display/)／[rtl/display](rtl/display/) | B 的独立RGB显示工程；屏幕引脚和触摸仍待接入 |
| [boards/tang_mega_60k_31004](boards/tang_mega_60k_31004/) | 当前板卡约束 |
| [verification](verification/) | 当前核心与B/C支持模块测试，旧实现专用测试已移除 |
| [host/run_tone_studio.bat](host/run_tone_studio.bat) | 唯一上位机入口；钢琴／摇滚、五度／四音／16音演奏 |
| [upstream/fpga_interaction](upstream/fpga_interaction/) | C 原始独立工程，保持原样，不与主工程同名模块混编 |
| `build/` | 生成物、日志、波形及烧录包，不作为源码提交 |

旧DDS、四声部波表、弦乐演示、旧UART顶层及其专用工具已从有效源码移除，不另建A工程副本。历史从Git `0406c60`／`f513622`查询；精简清单与哈希在`build/cleanup_a/`。旧`deliveries/`、`results/`、`fpga_project/`及退役工程中的残余生成物暂未删除，已排除源码提交，不是当前入口。

## 复现与启动

在仓库根运行。Python模型需要NumPy（`model/requirements.txt`），上位机使用`host/studio_requirements.txt`。工具路径按实际安装覆盖。

```powershell
python verification/scripts/check_source_layout.py
./verification/scripts/check_verilog.ps1 -ModelSimBin D:/modelsim1/win64
./verification/scripts/run_tests.ps1 -Suite A -ModelSimBin D:/modelsim1/win64 -Python python
./verification/scripts/run_tests.ps1 -Suite All -ModelSimBin D:/modelsim1/win64 -Python python
& '.venv-studio/Scripts/python.exe' -m unittest discover -s host -p 'test_*.py' -v
./projects/piano/build.ps1 -Gowin C:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe
```

`A`运行7组当前核心回归和独立模型／音域对照；`All`包含A、B、C、UART字节、显示及当前16声部功放排空测试，不必先跑A再跑All。单独套件同名可选。ROM重建入口：`model/gen_piano_v3_rom.py`、`model/gen_pitch_bend_rom.py`和`model/gen_sine.ps1`；`gen_rock_v2_rom.py`是共用吉他公式库，不再产生旧模态表。

双击上位机启动脚本，实际COM、115200/8N1。进入“演奏”页选音色，总音量从8开始；工作台草稿不会修改板上预设。KEY1=C4、KEY2=E4、KEY0复位到钢琴／音量8／弯音居中。16声部包含尾音，满载第17音抢占；PANIC／失联只释放电脑来源。

## 已试听位流与边界

继续使用 `build/audition/music_classic16_20261014_201505/music_classic16.fs`，SHA-256：`55ddab166832b0df000993de6f9ce1d6465862ad961595e29ee67376ac2b1cce`。本次精简不改变综合RTL、四份ROM、GPRJ或板级约束，无需为整理目录重新烧录。原发布包保持交付时快照。

使用已确认板卡的 **SRAM Program**。现有约束下构建通过，但PR1014和DAC完整外部时序仍未闭合；13实体键、触摸、两旋钮、延音和整机延迟仍待集成／测量。PT8211-S当前为LSBJ右对齐格式，赛题I2S口径仍需核对。

接口与A交接清单见[设计说明](docs/design.md)，验证见[验证说明](docs/verification.md)，实际试听见[试听指导](docs/listening-acceptance.md)，后续分工见[PLAN](PLAN.md)。


2026-10-14补充：用户已明确确认删除旧产物。三个空退役工程目录已删除；deliveries/results/fpga_project的递归删除仍被执行工具策略拦截，三个目录仍在。无需再次索要用户授权，后续需解决执行限制。92个保护输入及完整classic16发布包经哈希复核未变。
