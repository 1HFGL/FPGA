# 13 键接线与运行

本地工作工程为 `fpga_piano`，基于 GitHub `1HFGL/FPGA` 的 master 提交 `0406c609` 接入 13 个独立低有效按钮。主工程仍使用队友现有的四声部钢琴近似合成、UART 和 PT8211-S 输出；13 个可选音高不等于 13 个同时发声声部。

正式板级入口：`projects/piano/uart_piano.gprj`，顶层 **`piano_13key_top`**，约束 `boards/tang_mega_60k_31004/piano.cst`。13键成果整理到 master；初始提交为 `b59f8ee7`。尚未接线或下载板卡。

## 按键与引脚

按半音排列，bit0 在最低位，范围 MIDI60～72。白键在前排，黑键在后排：

```text
后排：     C#4  D#4       F#4  G#4  A#4
前排：  C4   D4   E4   F4   G4   A4   B4   C5
```

| 标签/端口位 | 音符 | 颜色 | 模块 OUT/开关信号端接到底板 | FPGA 球位 | Bank |
|---|---|---|---|---|---:|
| K00 / piano_key_n[0] | C4 | 白 | J9 第11脚，PMOD0_IO0 | P19 | 7 |
| K01 / piano_key_n[1] | C#4 | 黑 | J9 第12脚，PMOD0_IO1 | R19 | 7 |
| K02 / piano_key_n[2] | D4 | 白 | J9 第9脚，PMOD0_IO2 | T21 | 7 |
| K03 / piano_key_n[3] | D#4 | 黑 | J9 第10脚，PMOD0_IO3 | U21 | 7 |
| K04 / piano_key_n[4] | E4 | 白 | J9 第7脚，PMOD0_IO4 | P16 | 6 |
| K05 / piano_key_n[5] | F4 | 白 | J9 第8脚，PMOD0_IO5 | R17 | 6 |
| K06 / piano_key_n[6] | F#4 | 黑 | J9 第5脚，PMOD0_IO6 | R18 | 6 |
| K07 / piano_key_n[7] | G4 | 白 | J9 第6脚，PMOD0_IO7 | T18 | 6 |
| K08 / piano_key_n[8] | G#4 | 黑 | J8 第11脚，PMOD1_IO0 | Y21 | 8 |
| K09 / piano_key_n[9] | A4 | 白 | J8 第12脚，PMOD1_IO1 | Y22 | 8 |
| K10 / piano_key_n[10] | A#4 | 黑 | J8 第9脚，PMOD1_IO2 | AB21 | 8 |
| K11 / piano_key_n[11] | B4 | 白 | J8 第10脚，PMOD1_IO3 | AB22 | 8 |
| K12 / piano_key_n[12] | C5 | 白 | J8 第7脚，PMOD1_IO4 | AA20 | 7 |

该 NEO Dock 的 J8/J9 **第1、2脚是 +3V3，第3、4脚是 GND，第5～12脚才是信号**。
按板上1脚标记定位，并按实际针脚编号接，不套用其他 PMOD 板的编号或凭图上左右位置接线。
FPGA 球位列用于 CST，不是杜邦线直接连接的位置。

接线按低有效按钮实现：

- 普通无源开关：一个有效触点接对应信号脚，另一个触点接 GND；FPGA 已启用内部上拉。四脚轻触开关应使用按下才导通的一对触点。
- VCC/GND/OUT 按键模块：VCC 接3.3V、GND共地、OUT接表中信号脚；本固件要求未按为高、按下为低。模块针序按其丝印接，输出不得超过3.3V。
- 所有琴键地可以共用。黑白键的电路和消抖完全一样，音符由端口位编号决定。

## 复用条件与保留接口

四个 PMOD0 引脚 P19/R19/T21/U21 默认属于 CPU 专用脚。工程的受控 `process_config.json` 已设 `CPU=true`，含义是 **Use CPU as regular IO**，不是运行 CPU 发声。构建会复制受控配置并核对实际生效配置哈希。厂商说明见 [Gowin Software User Guide 的 Dual-Purpose Pin](https://cdn.gowinsemi.com.cn/SUG100E.pdf)。

若在 GUI 新建工程，必须在 Configuration → Place & Route → Dual-Purpose Pin 勾选 **Use CPU as regular IO**，并选择正确顶层、ROM、CST/SDC。缺这个选项，布局会报告 CPU 专用脚不可使用。

PMOD 与 SDRAM1/DVP 相机扩展线共用，接琴键期间不要并接相机、PMOD外设或使用这些线的 SDRAM1 电路；J14的对应线也不算额外独立GPIO。旧 C LED 演示约束使用了其中部分球位，不要与此主钢琴约束混用。

时钟、复位、两板载键、音频和UART保留用户给定的10个球位，13键没有占用 LCD RGB/CTP/Joy-Con 线路。J8 的 IO5/IO6/IO7 尚未使用；AA21/AA19 可作为后续 ADS1115 接线的候选保留脚，本轮没有把 ADC 接入主钢琴或改动独立 ADC 工程的历史约束。

板载 KEY1/KEY2 保留 C4/E4 测试功能，在13键模式分别与 K00/K04 合并为同一个逻辑按键；任意一个仍按住时不会因另一个松开而关音。黑键不承担功能设置操作。

## 构建与验证

从本工程根目录运行：

```powershell
./verification/scripts/verify_keyboard.ps1 -ModelSimBin D:/Modelsim/win64
./projects/piano/build.ps1 -Gowin D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe
```

生成位流位于 `projects/piano/impl/pnr/piano_13key.fs`；实际版本/校验值见 `build/piano/artifact.txt`。仅当按本表接线并核对模块电平后，用已有 SRAM Program 流程试板；本次未自动操作下载器或写Flash。

先接 K00 单键，检查 C4；再检查 K01 黑键 C#4、K12 高音 C5，随后补齐其他键。四键和弦应可同时发声，第五个新音会抢占最老声部。PC与琴键共享四声部。

独立新增测试覆盖全部13键音符/来源、逐键非零音频、四键和弦、第五键抢占、旧松键不误关新音、板键别名保持、13键突发和复位。第二项使用真实50MHz/48kHz、2ms消抖及正式钢琴包络，检查1ms脉冲被拒绝、C5稳定按下到PCM和完整左声道数字字。

原有测试文件保持与基线字节一致；重跑 C 7项、钢琴2项、UART7项，加新增2项，共18项通过。全部87个有效Verilog文件严格编译通过。输入扩展使资源发生变化，构建检查验证4个实际音频 pROM 实例、23端口约束、7条激活时序约束及setup/hold/recovery/removal/pulse-width五类路径表；同时检查源码时间和构建输入哈希。

最终核对结果：50MHz周期20ns，setup **+4.519ns**、hold **+0.227ns**，setup/hold违例均为0；recovery/removal/pulse-width表也无负余量。Logic 6225、寄存器2815、BSRAM6、DSP8.5。实际生效配置与受控配置的哈希相同，4个音频pROM实例保留。

单次新C5数字观测：稳定输入到PCM **2.020220ms**，到完整左声道数字字 **2.030880ms**，1ms脉冲不触发。这只是该相位/空声部/无积压用例，不是所有工况上界或整机实测，真实接点抖动与DAC/功放模拟延迟未计入。

随提交保留的验证摘要在 `verification/evidence/keyboard/summary.json`；本机重新生成的摘要与补丁位于 `build/keyboard-verification`。13键原提交保留57份原测试；本次归并保持主Verilog测试原样，在独立C中刷新4份已发布测试接口，来源和哈希在 `verification/c_source_refresh.json`。PR1014与完整DAC外部时序/模拟输出延迟仍待闭合。13键主工程目前尚未移植独立 C 的八度、延音、起音代次与队列故障控制；它们和16声部钢琴合成将在后续统一接口后接入。

## 引脚依据

- [NEO Dock31004 Rev1.4原理图](https://dl.sipeed.com/shareURL/TANG/Mega_138K_60K/02_Schematic)：第6/7页板间连接与第19页 J8/J9接口。
- [60K核心板原理图](https://dl.sipeed.com/shareURL/TANG/Mega_138K_60K/02_Schematic)：球位映射与第6页 Bank6/7/8 的3.3V供电。
- 高云布局后的 `piano_13key.rpt.txt` 再次核对全部13脚均为输入、LVCMOS33、UP、3.3V，并核对正确球位和Bank。

原始原理图与快照保留原样，没有把通用球位表视为新外设已经接好的证据。

本提交通过上述官方资料目录提供原理图，不重复上传PDF。已核对原件的SHA256：

- `tang_mega_neo_dock_60k_schematic.pdf`：`5ca6049ed80bab57bcaa87cc5e58926f569f2ca2aa11b984d52da1782633f976`
- `tang_mega_60k_schematic.pdf`：`f9a1a01862fe8c48cb5461e88f84d61e37d03f2d032e0baee7ef03fb951f6157`
