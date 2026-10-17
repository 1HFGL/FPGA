# 高云 FPGA 双音色电子乐器

当前正式版本：**钢琴v3＋经典摇滚电吉他，13实体键和UART共享16声部，两旋钮控制总音量及全局±2半音弯音，7寸1024×600 HDMI中文显示**。

2026-10-16已接入队友master `e18160e` 的模态核心与配套ROM；钢琴显示琴键，吉他显示六弦指板。KEY2切换新音的预设，旧音/尾音保留原音色；KEY1按次切换中→高→低→中音区，KEY0复位回钢琴和中音区。新位流的八白键连续接下方40针接口1～8，五黑键接9、10、13、14、15，ADC仍接16/17。具体见[唯一接线表](docs/keyboard-wiring.md)。

实物是 **NEO Dock31005＋Tang Mega60K核心板**。约束目录保留历史名称31004，内容按31005底板与60K核心板核对。J8/J9仅取3.3V/GND，下方接口11脚为5V，不能接3.3V信号或模块电源。

## 最新：触摸明亮度准备版

按用户确认，明亮度移到屏幕上方滑条和“原音”按钮，KEY1仍切三音区、KEY2仍切乐器。FPGA坐标处理、音频平滑和显示已接入；当前触摸线未接，USB主机／HID解析尚未实现，界面显示“触摸关”，此时手指不会改变参数。最终运行方案不依赖电脑。详细接口、验证及所需资料见[触摸明亮度说明](docs/touch-brightness.md)。

HDMI准备版默认127保留原音，缓存改为R927；无屏入口继续R924。新的预览位流仅用于核对画面和原有演奏功能，USB接收端接通后还需重新实现及实物验收。下面三音区包是此前发布包，不包含本轮控件。

本次控件预览包：`build/audition/touch_brightness_prepare_20261017/hdmi_touch_brightness_preview.fs`。162文件严格编译、9项仿真及预览配置当前约束检查通过，仍未烧录或接通USB；详见[最新验证记录](docs/verification.md)。

## 当前：KEY1 三音区

两个正式入口默认开启 `ENABLE_OCTAVE_KEY=1`，复位为钢琴、中音区。KEY1每次有效按下只前进一档，长按不连跳；KEY2切换乐器但保留音区。

| 音区 | 13个实体键依次发音 | MIDI |
|---|---|---|
| 低 | C3、C#3、D3…B3、C4 | 48～60 |
| 中（开机） | C4、C#4、D4…B4、C5 | 60～72 |
| 高 | C5、C#5、D5…B5、C6 | 72～84 |

按住旧音再切音区，旧音保持音高，松键按原音符释放；新按键使用新音区。HDMI同步切换音区名称、琴键音名与持键窗口；吉他高音区显示12～24品。换区后越出当前窗口的旧音仍会发声，不显示为新音区的琴键。

本机当前试听包：`build/audition/octave3_j13_20261017/`，带屏选 `hdmi_octave3_j13.fs`，无屏选 `piano_octave3_j13.fs`。接线、双旋钮、16声部及钢琴/经典摇滚合成参数保持原样。验证与上板边界见[验证记录](docs/verification.md)。用户已确认此前音色异常来自音响；本次新增音区仍需实物试听。该历史包的明亮度暂缓；本轮触摸准备见上节，八度选音不计为第三表情维度。

## 两个下载入口

| 工程 | 顶层 | 位流 |
|---|---|---|
| [带屏主工程](projects/hdmi/piano_hdmi.gprj) | `piano_hdmi_top` | `projects/hdmi/impl/pnr/piano_hdmi.fs` |
| [无屏入口](projects/piano/uart_piano.gprj) | `piano_performance_top` | `projects/piano/impl/pnr/piano_performance.fs` |

两个入口共用一套模态核心、输入和音频输出。带屏入口首次打开EDA前运行PrepareOnly，生成合并约束；最终下载文件和SHA256见[验证记录](docs/verification.md)。先用SRAM Program低音量试板，本轮不自动操作硬件。

```powershell
./projects/hdmi/build.ps1 -PrepareOnly
./projects/hdmi/build.ps1
./projects/piano/build.ps1 -EvidenceDirectory build/final-noscreen
```

本机Gowin1.9.12.04：`D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe`；ModelSim10.6e：`C:/Library/modelsim/win64`。脚本支持覆盖工具路径。仿真器在受限环境无法加载DLL时，需在正常PowerShell终端执行。

## 看见和听见什么

![钢琴模式：真实RTL像素](docs/display-piano.png)

![吉他模式：真实RTL像素](docs/display-guitar.png)

两图为此前中音区RTL完整帧及实际模态合成输出的示例，不是软件仿画；新音区的标签和吉他品位以当前RTL为准。界面使用离线生成的2bit覆盖度字模，48px标题为原生渲染，不是把24px点阵放大。波形显示512样本/约10.67ms，自动倍率×1～×256；右侧电平条直接反映音频数字峰值，显示放大不改变声音。高亮只表示仍持有的已分配音符，旧钢琴音不会被画到吉他指板上。

钢琴含48个模态槽，吉他含31个分量、拨弦噪声、失真和箱体处理；ROM是合成参数/单周期正弦/传递曲线，不是整音PCM录音。A核心保持队友原输出，试听仍需按相同音高和接近响度与实物对照。钢琴松键释放约85.33ms，吉他约42.67ms再加箱体收尾；按住时分量自然衰减，没有旧版固定1.2秒清零。

音频50MHz系统/48kHz采样/16位，16声部R923原始样本有效，无屏及此前音区包R924缓存，新HDMI触摸准备配置R927缓存（默认明亮度127保持样本相同），提前60个半位边沿准备。PT8211-S使用LSBJ右对齐格式；模块名I2S不自动证明标准Philips格式或赛题接口口径已闭合。

音量复位为满增益（既有集成测试合同），ADC就绪后平滑采用旋钮值；掉线保持最后有效参数。ADC为ADS1115，860SPS/每通道等待1.5ms/实际约347.22kHz I2C；AIN0音量、AIN1弯音。串口115200/8N1，保留NOTES/STATUS及`TONE=PIANO_GUITAR`识别，音色由KEY2选择。板级KEY1选择低C3～C4／中C4～C5／高C5～C6，各13音；延音关闭。电脑UART发送绝对MIDI音符，仍由上位机自己的音区选择控制。

## 验证入口

```powershell
./verification/scripts/check_verilog.ps1
python verification/scripts/run_final_tests.py tb_panel_octaves tb_performance_octaves tb_hdmi_octaves tb_final_display_ui tb_final_hdmi_isolation
python verification/scripts/run_final_tests.py tb_final_performance --legacy
python verification/scripts/run_music_tests.py --bin C:/Library/modelsim/win64
python model/check_music_pipe.py build/regression/music/tb_music_pipe.csv
./verification/scripts/run_hdmi_reset_tests.ps1
```

使用实际Python路径或已配置的Python。原R4/R6/R7测试通过明确兼容参数验证，队友TB和黄金数据不改；它们不替代新正式入口的R924三音区联合验收。完整命令、当前结果、资源/五类时序、负向对照和受保护文件检查见[验证记录](docs/verification.md)。

## 项目导航

```text
rtl/           audio、control、synth、display、top、rom；当前共享源码
projects/      带屏/无屏正式入口，以及必要的独立兼容检查
boards/        公共引脚、时序和HDMI复位布局约束
verification/  Verilog测试、参考数据、运行脚本及可审计摘要
upstream/      C独立工程，保留接口与TB原样；不与主工程整目录混编
host/、model/  电脑演奏台、离线定点参考和参数生成依据
docs/          当前说明、原始资料、字库许可
build/         日志、波形、临时故障注入及编辑器生成物；不提交
```

主工程只综合模态声部池；基础波表/包络模块仍用于独立教学和兼容回归，C独立工程由用户要求保留。旧工作区副本和生成清单不作为下载入口。

master同时保留队友A的 `projects/music/uart_music.gprj` 独立试听工程，与上述两个正式入口分开。电脑端按实际握手兼容两类固件，详情见[上位机说明](host/README.md)。2026-10-17合并验证：149文件严格编译、8项正式回归及85项PC测试通过；正式RTL／TB／构建约束与已验证整合提交一致，未重新运行布局布线，见[合并记录](verification/evidence/final/master_merge.json)。

[PLAN](PLAN.md)维护目标/分工；[音频合同](docs/design.md)、[显示合同](docs/display-rgb.md)、[接线](docs/keyboard-wiring.md)、[装配](docs/keyboard-assembly.md)、[上位机](host/README.md)各维护一份说明。

当前尚需实物验收新音色、逐键接线/K6、旋钮噪声/中心校准和模拟总延迟。USB触摸、混响、32声部不属于本轮；完整比赛目标仍在PLAN中。PR1014、DAC完整外部时序和其他板外预算未闭合，当前约束检查通过不等于全面签核。


## 历史记录：第三表情维度（已由当前 KEY1 音区方案取代）

> 以下仅适用于旧 expression3 位流。当前正式入口停用明亮度，KEY1 切三音区，缓存恢复 R924；不再执行短按调暗／长按恢复。

本次在队友最新master `aef94e5`上接入明亮度，保留31005底板J13接线、模态钢琴／经典摇滚、16复音和HDMI画面。两个正式入口均启用：旋钮0音量、旋钮1弯音、KEY1明亮度；KEY2继续切换乐器。KEY1短按每次调暗16级，到0后再次短按回127；长按约0.5秒恢复127，复位也恢复127。KEY1不再兼作C4，外接13琴键映射不变。两键同时按下仍会触发KEY2切音色，不再作为第三维恢复手势。

明亮度由FPGA混音后定点低通实现，默认127逐样本保持原PCM；三拍音频流水线使正式缓存合同由R924变为R927，原60个半边沿请求提前量保留，尾音归零后再关闭功放。屏幕观察过滤后的音频，显示不反馈控制。明亮度改变谐波比例和部分能量，不能称为真实力度传感或模拟底噪修复。

新验证入口`verification/scripts/run_expression_tests.ps1`；整合结果与新位流身份见`verification/evidence/expression/summary.json`。旧e18160e基线的31004／旧接线试听包不适用于当前J13接线；请从本次整合后的正式工程构建或使用新包。既有PR1014、DAC完整外部时序、模拟总延迟及新增听感仍需实物验收。PPT第12页的≥3维是扩展目标，基础要求仍为≥2维。


历史三维试听包（不是当前推荐下载入口）：`build/audition/expression3_j13_20261017/`（无屏／HDMI各一份），适用当前31005/J13接线。代码与证据通过整理分支及PR交付，GitHub合并记录为最终发布状态。
