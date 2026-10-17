# C输入与声部管理

本文说明C的输入/声部职责。C控制成果保留，2026-10-16已通过适配层接入master `e18160e` 的16声部钢琴v3／经典摇滚电吉他核心；A/B/C职责按PLAN执行。

## 从哪里开始看

| 入口 | 用途 | 当前状态 |
| --- | --- | --- |
| [13键接线与运行](keyboard-wiring.md) | 31005/J13琴键与ADC接线，J8/J9仅供3.3V/GND | 主工程已接入，实物待验证 |
| [piano_performance_top.v](../rtl/top/piano_performance_top.v) | 主钢琴板级入口 | 13实体键＋UART共享16声部＋ADS1115双旋钮 |
| [instrument_uart_top.v](../rtl/top/instrument_uart_top.v) | 同步/消抖、键事件、UART仲裁与A/B连接 | 当前主发声链路 |
| [rtl/control](../rtl/control/) | 主工程C模块 | 8位来源ID，16位起音/完成代次；兼容单拍起音通知 |
| [独立C工程](../upstream/fpga_interaction/) | 已验证的八度、延音、队列及声部分配算法 | 队列、八度锁存、延音和代次规则已适配主钢琴，独立工程不改 |
| [独立C接口合同](../upstream/fpga_interaction/doc/c_control_progress_20261014.md) | 起音/完成代次、延音、来源清理、溢出行为 | 主工程适配依据 |

两套同名模块属于不同工程入口，禁止一起编译或直接相互覆盖。主工程保留必要兼容参数，正式配置启用16声部、代次匹配与全局旋钮控制，独立工程不参与主工程混编。

## 你负责的已有成果

- 主13键：独立低有效输入、2ms消抖、每档13个半音、KEY1循环中C4～C5／高C5～C6／低C3～C4、按下/松开事件；正式入口KEY2改模式键、KEY0复位回钢琴，外接13键完整保留。实体键与电脑共享16声部，13个可选音高不是13复音。默认兼容测试入口仍保留原C4/E4别名。
- 独立C：按下音符/参数快照、八度切换后按原音符松键、每键四项队列与64项FIFO、轮转调度、溢出锁存及本地来源清理。
- 独立分配器：严格按来源和音符匹配、同音重触发、保留尾音、延音、来源掩码清理、16位起音/完成代次校验，以及不依赖运行时间戳的抢占次序。
- ADS1115：原量程、有符号数据与故障处理成果保留；主工程已接入ADC；第二旋钮改为全局弯音，独立工程旧亮度映射保持原样。
- 10月15日主工程采集配置改为860SPS、1.5ms转换等待、350kHz I2C请求、2对预热；ADC端不重复平滑，保留48kHz音频斜坡。C独立快照与队友TB不动。数字响应预算、转换时间模型及实物抗抖待验事项见[当前设计](design.md)。

## 运行验证

从仓库根运行，按安装位置设置ModelSimBin：

```powershell
./verification/scripts/verify_keyboard.ps1 -ModelSimBin C:/Library/modelsim/win64
./verification/scripts/check_c_rtl.ps1 -ModelSimBin C:/Library/modelsim/win64
./verification/scripts/run_c_control_tests.ps1 -ModelSimBin C:/Library/modelsim/win64
./upstream/fpga_interaction/scripts/run_modelsim.ps1 -ModelSimBin C:/Library/modelsim/win64 -SimDirectory ./build/c-independent
./projects/piano/build.ps1 -Gowin D:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe
```

独立C的15份RTL和三份新增控制测试严格使用Verilog-2001检查；旧SV测试按历史版本保留，独立C全量回归单独运行，不与主工程混编。三份新增测试从原SV版本调整声明和失败报告语法，检查条件保持。

13键原阶段验证：87文件严格编译、18项相关回归、23端口布局布线与内部时序通过。本次归并会重跑相关回归。最新记录见[验证说明](verification.md)及[主键盘证据](../verification/evidence/keyboard/)、[独立C证据](../verification/evidence/c-independent/)。原独立A/B夹具及其8项联合回归保留在Git提交[8b0d12f](https://github.com/1HFGL/FPGA/tree/8b0d12fdb225436112c203cc194b9b72ce47cc06)，当前工作目录不再复制。

## 已适配与下一步

主工程沿用8位来源：实体0..12；16..127预留其他输入；电脑128..255。实体队列故障只清0..15，PC失联只清最高位为1的来源。起音代次只在实际采样后确认，回收同时检查代次和真实尾音完成；排序沿用主工程无回绕的年龄排列，并按C规则优先抢最老已松开声部。

每键四项暂存、64项FIFO、八度按下快照、延音/按住状态分离及故障隔离已接入；板级KEY1已接入三档音区、复位中档，延音关闭。旋钮0音量、旋钮1全局弯音接到真实音频计算。新增主Verilog联合测试见 `run_performance_tests.ps1`，本轮所有既有tb和C独立脚本与基线保持字节一致。

KEY2模式在分配器接受音符事件时写入4位`timbre`的最低位：0钢琴、1吉他，其余位0；适配层转换为A核心的相反编号，不改变C合同。R0锁存音符、参数及整批代次，R923原始结果有效，正式音区版旁路明亮度，R924缓存；确认只对应这批结果，忙时屏蔽旧release_done，避免旧代次回收新声部。

已有声部保留原音色快照，两音色共享同一16席位，模式切换不清队列、不产生E4，不取消本地或电脑尾音。显示分别读取钢琴/吉他仍持有的已分配音符，整帧切换主体及高亮；音符不等待帧刷新，触摸来源仍未实现。正式新核心联合测试见run_final_tests.py，原R7测试仅作为显式兼容配置回归。

下一步确定触摸控制器和延音入口；实体八度入口已确定为KEY1，仍需实物验收，核对实物旋钮行程、按键抖动、接线及整机模拟延迟。用户持有板卡；本轮没有操作下载器，也没有实物验收。


## 历史记录：第三表情维度（已由当前 KEY1 音区方案取代）

> 以下仅适用于旧 expression3 位流。当前正式入口停用明亮度，KEY1 切三音区，缓存恢复 R924；不再执行短按调暗／长按恢复。

正式两入口KEY1改为明亮度，KEY2继续切乐器，外接13键和两个旋钮职责不变。KEY1短按调暗16级、到0后回127，长按0.5秒恢复127。它不生成音符或占用声部；滤波与步进平滑在FPGA内完成。操作与验证见design.md、keyboard-wiring.md及verification.md。
