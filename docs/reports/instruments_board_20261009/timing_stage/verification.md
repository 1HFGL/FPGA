# 两乐器板级试听工程验证记录（2026-10-09）

工具：Gowin V1.9.12.03 (64-bit)。器件：GW5AT-LV60PG484AC1/I0，B版本。
顶层：`instrument_presets_top`。工程：`fpga_project/instruments_board/instruments_board.gprj`。
实际完成综合、布局布线、位流生成，工具返回0；没有下载到开发板。

## 验证范围

仅 KEY1 演奏固定 C4、力度100的一条声部；KEY2切换下次起音的吉他/弦乐预设，复位后默认吉他。KEY2不直接重置正在播放的尾音。其余三条声部输入为静音，虽然部分逻辑仍保留，但不据此宣称此按键工程可演奏四声部。
50 MHz主时钟，音频请求目标48 kHz；输出沿用团队原B模块和同板原引脚电气值。

## 时序结果

| 检查 | 最差余量 |
|---|---:|
| Setup（含输出20 ns预算） | +5.885 ns |
| 寄存器间Setup | +9.201 ns |
| Hold | +0.216 ns |
| Recovery | +17.330 ns |
| Removal | +0.858 ns |
| 最小脉宽 | +6.809 ns |

时钟周期20.000 ns；报告Fmax92.601 MHz；3008条路径、3040端点；setup/hold违例0/0，TNS均0。
总体最差Setup来自 `u_bank/g_voice[3].u_voice/env_d1_9_s0/Q` 到 `PA_EN_obuf/O`；内部最差Setup来自lane0亮度计算DSP到亮度混合DSP。

五条SDC约束全部Actived；只有外部按键和外部复位设置false path。没有内部false path或multicycle；同步链内部仍参与时序分析。所有实际映射CLK输入只有sys_clk_d或DSP未使用的接地时钟。

四个输出的20 ns max-delay / 0 ns min-delay是沿用旧板工程的寄存器到管脚预算。此记录不等于外接DAC的完整建立/保持签核，也不代替真实开发板试听。

## 引脚和资源

8个端口全部Constraint=Y，按键/复位LVCMOS15，主时钟和音频输出LVCMOS33。对应位置为 V22 / AA13 / AB13 / Y12 / Y17 / AB17 / AA16 / AB16；输出DRIVE=8，复位与按键上拉。
资源：1219 LUT、535 ALU、774触发器（771逻辑+3IO）、0锁存器、9 pROM/BSRAM、14 DSP。

## 综合网表复核

对9块pROM的9216个初始化字逐字核对。lane0保留half-sine、guitar、strings三张表；三个静音lane各保留half-sine和guitar两张表。
追踪KEY2输入缓冲、消抖输出、选择翻转寄存器、lane0事件快照、注册ROM选择、亮度和包络通路。16位吉他/弦乐选择128种LUT真值组合与16位基础/完整波形选择128种组合均通过；预设选择没有被常量折叠。此为结构/内容核查，不是门级时序仿真。

综合有14条NL0002：固定音符的note_phase_lut 4条、静音lane的velocity层3条、静音lane的u_sine层3条、u_strings层4条。已检查实际ROM内容，移除/合并层级不等于lane0弦乐表丢失。
布局布线保留1条PR1014：V22主时钟使用普通布线资源而非专用时钟管脚，可能增加延迟或偏斜。此版本仍通过上述时序，但不能写成“无警告”或据此改动实际板脚。

## 复现和GUI设置

首次使用或新克隆，先通过本工程run.tcl构建一次。脚本根据自身位置定位仓库，将共享process_config.json写到impl/instruments_board_process_config.json，并显式设置顶层、输出名和ROM搜索路径。之后打开本工程.gprj可使用生成的配置；不要只复制旧impl配置到不同路径，重新运行脚本即可重新定位ROM路径。无需手写未知格式的.gprj.user。

审计命令：`python model/check_presets_board.py`。默认读本工程的新报告；JSON包含源文件、ROM和位流SHA256，避免将旧结果当作新结果。
位流：`fpga_project/instruments_board/impl/pnr/instruments_board.fs`，17962083字节。
SHA256：`e7fea198c3db7ee225cf51ebbc002226ed19fa1a3a49de95a9f535d96fb4e73a`。
原始报告、审计JSON和压缩综合网表随本记录保存，构建位置为独立Temp工程，未修改团队仓库或烧录硬件。
