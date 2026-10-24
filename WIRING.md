# 接线快速修改

以后查接线、改接线，先打开这一页。适用实物：**NEO Dock31005＋Tang Mega60K**；目录中的31004只是历史名称。

这里是入口，不另存第二份引脚表。**当前具体接法只维护在[接线表](docs/keyboard-wiring.md)**；改Markdown不会自动改变FPGA引脚，必须同步约束、验证并重新生成位流。

## 我现在要找什么

| 要查看或修改 | 直接打开 | 注意 |
|---|---|---|
| 八白键、五黑键的丝印／音符／端口 | [琴键接线表](docs/keyboard-wiring.md#按模块k编号接不按半音编号数) | 八键、五键模块各自从K1编号，不按按钮颜色判断音符 |
| 下方40针接口方向、3.3V和GND | [接口定位与电源](docs/keyboard-wiring.md#先定位接口和电源) | 先断电；按丝印核对，J13第11脚是5V |
| 蓝牙RXD／TXD／STATE | [蓝牙接线](docs/keyboard-wiring.md#蓝牙接线新增独立串口需使用本轮固件) | C13/C14/C15，STATE必须接；默认9600，电脑口115200不变 |
| ADS1115、音量／弯音旋钮 | [ADC与其他外设](docs/keyboard-wiring.md#adc与其他外设) | 旋钮模拟SIG接ADC，不直接接FPGA数字引脚 |
| B10K多焊脚裸滑条 | [先认脚再接AIN2](docs/keyboard-wiring.md#b10k裸滑条先认脚再接ain2) | 具体脚序待照片/测量；W→AIN2，两端3.3V/GND；未接时AIN2固定3.3V |
| HDMI屏、USB触摸、耳机／音箱 | [显示与音频接法](docs/keyboard-wiring.md#adc与其他外设) | HDMI负责画面；FPGA独立USB触摸尚未接通 |
| 当前下载文件和验证结果 | [README下载入口](README.md#唯一正式下载入口) | 新接线必须配新位流，不沿用旧下载包 |

## 改一个信号，要同步哪里

| 文件 | 用途与修改位置 |
|---|---|
| [piano.cst](boards/tang_mega_60k_31004/piano.cst) | **实际引脚分配入口**。搜索信号名，核对对应`IO_LOC`及`IO_PORT`；不是改J13针号，而是填FPGA球位。 |
| [ble.cst](boards/tang_mega_60k_31004/ble.cst) | 蓝牙独立约束：`ble_tx=C13 / ble_rx=C14 / ble_state=C15`；只加入HDMI正式工程。 |
| [board_31005_j13.json](verification/data/board_31005_j13.json) | **接线合同**。琴键/ADC在`signals`，蓝牙在`bluetooth`；核对`port / j13_pin / ball / bank / net / btb_pin`整条映射。 |
| [keyboard-wiring.md](docs/keyboard-wiring.md) | **给人看的当前接线表**。同步模块K编号、音符、丝印、位置；相应说明也要一致。 |
| [check_j13_wiring.py](verification/scripts/check_j13_wiring.py) | **防接错检查**。含用户确认的白键球位、`black_keys`、蓝牙位置及负向故障样例；换针经原理图确认后才更新独立预期，不删除断言或放宽电压检查。 |

只移动已存在的琴键信号、音符功能不变，通常不需要改合成RTL或队友TB。若要新增蓝牙、改变按钮功能或交换ADC通道用途，则不只是换针，还需修改并验证相关RTL。

**不要编辑生成文件**：`build/hdmi/piano_hdmi.cst`由[HDMI构建脚本](projects/hdmi/build.ps1)生成，手工修改会被覆盖。不要为外接按键改HDMI、DAC或板载USB串口引脚。

## 最短操作顺序

1. 断电。先在当前接线表找到“模块端子 → RTL端口 → 原丝印”，确认新位置不是电源、地、其他已用信号或预留位置；按31005底板→60K核心板核实Bank供电。
2. 同步上面四处。迁移记录更新到[PLAN](PLAN.md)，下载文件身份与验证结果更新到[验证记录](docs/verification.md)。只调整线束长度、颜色或固定方式且电气连接没变，则无需改CST或重编译。
3. 在仓库根目录执行下列检查；任何一步失败就停，不拿旧报告当新结果。

   ```powershell
   # 本机Python路径；换电脑时改成实际安装位置。
   $pinPython = 'C:/Users/32215/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
   & $pinPython verification/scripts/check_j13_wiring.py
   # 上一步PASS后，重新综合/布局布线；脚本同时检查原约束下的时序。
   ./projects/hdmi/build.ps1
   # 构建PASS后，核对实际落点和故障检出能力。
   & $pinPython verification/scripts/check_j13_wiring.py --report projects/hdmi/impl/pnr/piano_hdmi.rpt.txt --negative-control
   ```

4. 根据[逐键检查步骤](docs/keyboard-wiring.md#下载后逐项核对)低音量试板，记录按下、松开、和弦及高亮是否正确；仿真通过不等于真实线束已经接对。仅修改文档时，不需要重新生成位流。

## 下次让我改，直接这样说

```text
按WIRING.md修改接线：
模块与端子：五键模块K__／八键模块K__／ADC SDA／……
原丝印：____    新丝印：____
用途：保持原音符／改成____功能
实物状态：尚未改线／已断电改线
是否生成新位流：是／否
Git操作：不提交／仅提交／提交并推送（指定分支）
```

选择“不生成新位流”时，只交付方案或源文件修改，不能据此按新位置接线后继续使用旧位流；实际启用新引脚前仍必须构建、检查并下载匹配版本。

没确认的新位置只算方案，不能标成“已验证”。本文链接到当前文件，不复制旧版本或固定某次位流哈希；最新身份始终看README和验证记录。
