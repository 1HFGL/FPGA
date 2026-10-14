# C输入与声部管理

当前聊天用户负责C。本次将已发布的13键输入和独立C演奏控制成果归入master，按仓库现有目录保存。A负责合成与混音，B负责音频输出和顶层集成。

## 从哪里开始看

| 入口 | 用途 | 当前状态 |
| --- | --- | --- |
| [13键接线与运行](keyboard-wiring.md) | 琴键颜色、音符、J8/J9接线、引脚复用及验证 | 主工程已接入，实物待验证 |
| [piano_13key_top.v](../rtl/top/piano_13key_top.v) | 主钢琴板级入口 | 13个实体键，当前四声部 |
| [instrument_uart_top.v](../rtl/top/instrument_uart_top.v) | 同步/消抖、键事件、UART仲裁与A/B连接 | 当前主发声链路 |
| [rtl/control](../rtl/control/) | 主工程C模块 | 8位来源ID，单拍起音通知 |
| [独立C工程](../upstream/fpga_interaction/) | 已验证的八度、延音、队列及声部分配算法 | 尚未适配主钢琴 |
| [独立C接口合同](../upstream/fpga_interaction/doc/c_control_progress_20261014.md) | 起音/完成代次、延音、来源清理、溢出行为 | 供下一步对接 |

两套同名模块属于不同工程入口，禁止一起编译或直接相互覆盖。本次是成果归并，不把源码位于master说成全部功能已经接入主钢琴。

## 你负责的已有成果

- 主13键：独立低有效输入、2ms消抖、C4～C5半音映射、板载C4/E4别名、按下/松开事件；实体键与电脑共享四声部。13个可选音高不是13复音。
- 独立C：按下音符/参数快照、八度切换后按原音符松键、每键四项队列与64项FIFO、轮转调度、溢出锁存及本地来源清理。
- 独立分配器：严格按来源和音符匹配、同音重触发、保留尾音、延音、来源掩码清理、16位起音/完成代次校验，以及不依赖运行时间戳的抢占次序。
- ADS1115：原量程、有符号数据与故障处理成果保留；旋钮仍未接入主钢琴，第二旋钮旧亮度映射不能当作全局弯音完成。

## 运行验证

从仓库根运行，按安装位置设置ModelSimBin：

```powershell
./verification/scripts/verify_keyboard.ps1 -ModelSimBin D:/Modelsim/win64
./verification/scripts/check_c_rtl.ps1 -ModelSimBin D:/Modelsim/win64
./verification/scripts/run_c_control_tests.ps1 -ModelSimBin D:/Modelsim/win64
./upstream/fpga_interaction/scripts/run_modelsim.ps1 -ModelSimBin D:/Modelsim/win64 -SimDirectory ./build/c-independent
./projects/piano/build.ps1 -Gowin D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe
```

独立C的15份RTL和三份新增控制测试严格使用Verilog-2001检查；旧SV测试按历史版本保留，独立C全量回归单独运行，不与主工程混编。三份新增测试从原SV版本调整声明和失败报告语法，检查条件保持。

13键原阶段验证：87文件严格编译、18项相关回归、23端口布局布线与内部时序通过。本次归并会重跑相关回归。最新记录见[验证说明](verification.md)及[主键盘证据](../verification/evidence/keyboard/)、[独立C证据](../verification/evidence/c-independent/)。原独立A/B夹具及其8项联合回归保留在Git提交[8b0d12f](https://github.com/1HFGL/FPGA/tree/8b0d12fdb225436112c203cc194b9b72ce47cc06)，当前工作目录不再复制。

## 下一步对接

1. 统一主工程8位来源布局和独立C参数，分别保留实体、触摸和电脑身份。
2. 将独立C的起音代次接入主A采样节拍，A返回已消费代次后才能安全回收。
3. 对接八度、延音和队列故障清理；操作入口仍待确定，实体琴键保持演奏用途。
4. A扩展合成与混音到16声部，C同步配置并做联合测试；主钢琴当前仍为四声部。
5. 后续落实触摸控制器和旋钮接口，开发板到位后验证接点抖动、接线、音频及整机延迟。

没有开发板，本次不进行接线、下载或整机验收。2ms消抖尚需结合实际按键抖动验证。
