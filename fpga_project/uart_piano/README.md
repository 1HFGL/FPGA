# UART钢琴感 v1：固定音色试听候选

2026-10-08：用户批准沿用单周期波表和ADSR制作固定钢琴感版本。代码、功能仿真、综合、布局布线和位流生成已验证；**未烧录、未打开实际COM、未实物试听**。PR1014和完整DAC外部时序仍未解决，不属于完整板级时序签核。

## 文件选择

高云EDA打开本目录 `uart_piano.gprj`，顶层 `instrument_uart_piano_top`，输出名 `instrument_uart_piano`。器件保持 **GW5AT-LV60PG484AC1/I0，Version B**，适用于此前核对的NEO Dock31004 Rev1.4。CST/SDC直接引用 `../uart_basic/` 的已核对约束；本次没有改引脚、时钟或电平。

新文件：`impl/pnr/instrument_uart_piano.fs`，本次SHA256：

```text
D5D871E4CA945BB46C080D175CCCF5F0D425E8EB4E20EF48144F56CDA26601ED
```

**不是** `instrument_uart.fs`，也不是 `instrument_adsr.fs`。重新构建后以 `results/piano-20261008/artifact.txt` 的新哈希为准。旧UART正弦和普通／自动位流未覆盖；若需回退，原UART正弦文件在 `../uart_basic/impl/pnr/instrument_uart.fs`。

## 预期效果与试听步骤

1. 核对板卡、器件和文件哈希；沿用原来的SRAM Program临时下载方式，不自动改Flash。
2. KEY0复位；KEY1=C4、KEY2=E4。新音色快起音，按住约1.202秒后衰减为零；松开从当时幅度用180ms淡出。已经衰减完时松开不会凭空再响尾音。
3. 重启 `fpga_music_tool/run_tone_studio.bat`，选择实际板卡COM、115200并连接；模拟设备不发声。不要与串口终端同时占用COM。
4. 握手成功后提示“设备固定钢琴感 · 界面参数未应用”；演奏琴键／四音和弦可用，“应用到设备”仍禁用。**不会因载入JSON或移动滑条而改变板上的音色**。
5. 先将耳机放在耳外确认没有异常杂音，再低音量试听单音、四音和弦、松键与“全部松键”。数字低增益不保证听力安全，不为听清而直接把音量拉满。
6. PC和实体键共享四个声部；第五音仍按原策略抢占。PANIC只释放PC来源，实体键不被整体清空；3秒失联保护仍保留。

这是**固定谐波比例＋线性包络的钢琴近似**，更偏简单合成键盘感；不是高保真原声钢琴，也没有分音独立衰减、琴弦共鸣、击槌噪声、踏板、混响或运行时音色切换。建议先在C4～C5试听；固定8次谐波在MIDI103以上会超过24kHz奈奎斯特频率，可能产生混叠，本次没有新增分区带限波表。无新增硬件要求。

持续电平为0，但按住的键仍保留声部所有权直到松键或抢占，防止状态自动回收后把长按误当再次击键。STATUS的VOICE_COUNT是占用数，**不等于当前可闻声部数**。

## 参数与生成依据

- 波表：`rtl/rom/piano_1024.mem`，1024点、16位有符号、单周期，仍MSB先出、PT8211-S LSBJ。
- 第1～8谐波相对系数：`255, 95, 48, 26, 15, 9, 5, 3`；第9～16项为0。系数是本项目原创试听起点，不是从钢琴录音测得。
- 每点按 `sum(a[h]*sin(2*pi*h*n/1024))` 计算，整周期峰值归一化，再乘32767、舍入到最近整数（正好半整数时取偶数）；数值范围-32767～32767，无直流偏置。
- 48kHz：Attack=96点（2ms），Decay=57600点（1200ms），Sustain=0，Release=8640点（180ms）。相位、包络、增益和混音全部仍在FPGA实时执行，没有PCM录音存储。
- 固定实体／上位机默认velocity=100、混音除32；JSON的volume=8是低音量草稿值，不与固定硬件音量建立运行时映射。主机也可通过既有NOTE_ON命令发送0～127的velocity。
- JSON草稿入口：`fpga_music_tool/tone_examples/piano.json`。载入后可以看波形／包络和导出波表；上位机不自动替换用户当前草稿。
- A/B流水线仍为R0请求→R3有效→R4缓存→下一帧串行输出，没有添加新时钟域。

`results/piano-20261008/piano_preview.wav` 是3.54秒的**数字参考试听，不是板卡录音**。它按相同定点规则生成逐音C/E/G/C和四音和弦，没有模拟UART调度、DAC模拟滤波／放大或实际延迟；不会放入FPGA发声链路。

## 验证与复现

从仓库根目录执行：

```powershell
.\sim\run_piano_tests.ps1
.\sim\run_uart_tests.ps1
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'C:\Library\modelsim\win64'
& '.\.venv-studio\Scripts\python.exe' -m unittest discover -s fpga_music_tool -p 'test_*.py' -v
.\fpga_project\uart_piano\build.ps1
```

本次：2项新RTL测试、7项旧UART、27项旧RTL、32项PC／波表测试通过。新测试包含66453次四声部逐点数值检查、真实默认段长、保持衰减到零、重触发／中途复位；板级测试使用真实50MHz／48kHz／434拍串口比例，检查握手、四复音、默认180ms尾音、实体键和19360个DAC串行字。故意将合成器改用旧正弦波表后，测试在R3数值检查拒绝，脚本非零退出；正式版本未保留错误替换。

参考试听重建（脚本拒绝覆盖已有输出，可另选新文件名）：

```powershell
& '.\.venv-studio\Scripts\python.exe' model/render_piano_preview.py --output results/piano-20261008/piano_preview_new.wav
```

Gowin V1.9.12.04：5142 LUT、692 ALU、2710寄存器、4 BSRAM／pROM、8 DSP，10/10端口有物理约束。50MHz下Setup/Hold违例0/0；最差Setup +6.237ns（到PA_EN引脚），内部寄存器路径+6.468ns，Hold +0.223ns，Recovery +17.279ns，Removal +0.631ns，脉宽+7.077ns；6条SDC均激活。

**这些仅证明现有约束下的静态检查**：DAC的DIN／WS相对BCK外部建立／保持模型仍不完整，PR1014仍存在；实际COM、硬件音质、温度稳定性、整机延迟与比赛验收仍待验证。本轮没有推送GitHub或下载硬件，不勾选R1—R7。
