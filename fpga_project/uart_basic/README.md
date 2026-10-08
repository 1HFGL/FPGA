# UART基础演奏版：电脑控制，FPGA发声

2026-10-08：本地代码、仿真、综合、布局布线与位流生成已完成；没有下载、打开实际串口或实物试听。本版固定正弦和ADSR，不是界面上所有调音功能已经实现。

## 打开与下载文件

保持仓库目录结构，在高云EDA打开本目录 `uart_basic.gprj`，顶层 `instrument_uart_top`，输出名 `instrument_uart`。器件为GW5AT-LV60PG484AC1/I0、Device Version B；适用于已核对的NEO Dock31004 Rev1.4。

独立位流：`impl/pnr/instrument_uart.fs`。本轮最终SHA256：

```text
80A1FC70F462B6E74152CE0966B1533D93E28628D3E73C3819C3BF28294578A4
```

重新构建后以新的哈希清单为准，不能仅按文件名识别版本。原普通／自动工程、引脚和两份试听 `.fs` 未覆盖；回退仍可使用原普通 `../impl/pnr/instrument_adsr.fs`。

新接口为RX=V14、TX=U15、LVCMOS33，经底板BL616连接板载DEBUG USB。实际USB转串口通道、COM号、硬件版本和供电电平未实测；JTAG成功不能证明UART已经畅通。不要为了通信自动刷调试器固件、换供电或改拨码。

## 上板应有的效果（待实测）

1. 核对板卡／器件／文件哈希，沿用已使用的 **SRAM Program** 临时下载方式；不是自动写Flash。
2. 松开KEY1／KEY2后复位，应静音。KEY1仍弹C4、KEY2弹E4，KEY0复位全部状态。
3. 重启电脑上的 `fpga_music_tool/run_tone_studio.bat`，选择实际板卡COM、115200，点击连接。不要选“模拟设备”；模拟设备不发声。
4. 正确握手后显示“设备已确认”，演奏琴键／四音和弦可用，“应用到设备”禁用，草稿提示“设备固定正弦 · 界面参数未应用”。
5. 先将耳机放在耳外确认没有异常杂音，再低音量试听单音、四音和弦、松键和“全部松键”。数字低增益不保证听力安全。
6. “全部松键”只释放PC来源，约120ms尾音后回收；未被正常抢占的实体按键继续发声。电脑／实体键共享四个席位，第五音会抢占，不是各自有四个席位。
7. 正常每秒STATUS轮询保持会话。电脑停止通信约3秒后只释放PC音符，再进入尾音；不会立刻切掉所有声音。恢复需重新连接／HELLO。

实际声音仍为简单正弦电子音：约2ms起音、500ms衰减至10%峰值幅度、120ms释放，固定增益100、混音除32。不是逼真钢琴音色；谐波、包络、音量、颤音滑条只编辑草稿，不改变这版硬件。13外接键、旋钮、第二音色和比赛整机延迟验收仍未完成。

## 手动串口检查

115200、8N1、无流控；每条命令发送LF（可用CRLF）。不要让上位机和串口终端同时占用同一COM。

```text
HELLO
STATUS?
NOTE_ON 60 100 0
NOTE_ON 64 100 0
NOTE_ON 67 100 0
NOTE_ON 72 100 0
NOTE_OFF 60 0
PANIC
```

HELLO应回复一整行：

```text
SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=uart-basic-v1 TONE=FIXED_SINE
```

NOTE_ON／NOTE_OFF没有逐条成功回执；发送日志不是执行证明。STATUS读取真实占用数（包括尾音）、峰值和抢占次数。命令末尾source仅支持0，内部按音符转换为独立来源；velocity=0等价松键。

未收到握手时先查文件是否为本UART版、波特率、端口占用和COM通道；不能拿原 `instrument_adsr.fs` 期待串口回应。串口显示打开但无回复，应记录现象，不盲猜COM号或改硬件。错误会话提示“请断开后重连”时重新HELLO，不重放旧按键。

## 模块阅读入口

- `uart_rx.v`／`uart_tx.v`：串口电平与字节互换；RX两级同步，所有逻辑仍用50MHz系统时钟。
- `uart_line_rx.v`：ASCII完整行、整数和错误恢复；不执行半行，不保存整段音频。
- `uart_synth_protocol.v`／`uart_fifo.v`：会话、16项PC事件队列、取消和3秒失联回收。
- `uart_reply_tx.v`：有限回复描述槽、整行发送、状态快照；32拍BCD转换避免长组合除法。
- `uart_event_arbiter.v`：电脑／实体事件轮询，背压锁定，采样边界取消。
- `voice_allocator.v`：新增可选来源取消与同音策略，旧默认不变；UART实例关闭跨来源同音合并。
- `instrument_uart_top.v`：接线入口，复用A合成与B输出；保持R3有效、R4缓存、下一帧输出。

新代码为本项目新增实现，没有复制第三方UART代码或引入外部发声软件。

## 测试与构建

仓库根目录的PowerShell：

```powershell
.\sim\run_uart_tests.ps1
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'C:\Library\modelsim\win64'
& '.\.venv-studio\Scripts\python.exe' -m unittest discover -s fpga_music_tool -p test_studio.py -v
.\fpga_project\uart_basic\build.ps1 -Mode Uart
.\fpga_project\uart_basic\build.ps1 -Mode Legacy
```

工具为ModelSim SE-64 10.6e、项目Python3.12.14、高云V1.9.12.04（64-bit），路径参数可覆盖。Legacy会复制原GPRJ并补齐波表，在results内隔离构建，不覆盖原位流；UART脚本检查波表/DSP、约束、Setup/Hold与构建前后输入哈希，不只看退出码。

实际证据见 [本轮验证记录](../../docs/uart-basic-20261008.md) 和 `../../results/uart-basic-20261008/`。负向测试 `run_uart_tests.ps1 -Tests tb_uart_instrument -SourceMutation` **应失败**，它只改结果目录中的源码副本；不可把注错副本加入EDA。

内部约束下Setup/Hold无违例，仍保留PR1014、完整DAC外部时序、UART实物通道／亚稳态可靠性、板载DAC格式赛题口径和整机延迟风险；这不是完整硬件签核或比赛达标证明。
