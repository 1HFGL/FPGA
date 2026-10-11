# 两套乐器预设验证记录：2026-10-08

基于 `feat/a-dds-core` 的 `7d8a67a` 增量开发，保留既有柔和／明亮核心。新增拨弦／弦乐四声部核心、独立数学模型与试听、高云注册接口时序工程。功能、接口、默认参数与使用步骤见 [实现说明](../../a-instruments.md)。

## 实际完成的验证

| 验证 | 结果 |
|---|---|
| ModelSim SE-64 10.6e 全部回归 | 25/25，旧 22 项全部保留 |
| 四声部新核心逐时钟参考 | 47695 个时钟、18341 个样本、42 次复位全部一致 |
| 配置 | 短段、0/1边界及超范围保持、S=0、32位极大时长有限前缀 |
| 饱和 | SHIFT=0 时正饱和332次、负饱和206次；默认安静混音无饱和 |
| 新波表 | 独立数学公式逐点核对2048个新数据；ROM读出覆盖两预设和保护两状态共4096组合 |
| 阈值/流水线 | 直接测试 `0x0fffffff/0x10000000/0x10000001`，验证单声部R2、混音R4 |
| 实际RTL试听 | 长音2×96000点、旋律2×120000点，共432000点完全一致 |
| 图形脚本 | 实际以source运行，四组均完成，全部信号路径可解析 |
| 旧数学参考 | DDS、ADSR、ABC、四声部、旧两音色及旧试听继续通过 |

极大时长测试只核对有限推进、跨预设重触发及释放初段，最后显式复位清空；没有运行数十亿采样的完整段。随机测试不是穷举。新核心是独立实现，旧 `instrument_demo_top` 通过回归不意味着它已经连接本次新核心。

`all_regression.log` 保存全套命令和输出，`simulation/` 为各项原始日志，`python_validation.log` 为11条实际数学核验命令。`All_sha256.txt` 记录本次参与回归的源文件/ROM哈希。`traces/` 保存四组新核心轨迹和真实试听CSV的gzip压缩副本，可解压后交给相应checker复核。

负测试实际改坏输入证据，确认检查器会失败：银行轨迹的样本、preset、tone、valid和完成footer共5项；波表的错值、缺行、越界词、错表共4项；试听的1LSB、索引缺口、截短共3项；网表ROM、选择LUT和截断共3项。分别见本目录的 negative 记录和 `timing/checker_negative.txt`。

## 仿真试听与数值差异

- [拨弦旋律](audio/instrument_guitar_melody.wav)
- [弦乐旋律](audio/instrument_strings_melody.wav)
- [拨弦A4长音](audio/instrument_guitar_probe.wav)
- [弦乐A4长音](audio/instrument_strings_probe.wav)

四个文件为单声道PCM16、48kHz。旋律是相同 C4/D4/E4/G4/C5，使用每预设固定增益对齐整段RMS约2000，避免仅凭响度误判音色；各自相同增益也施加于长音。原始RTL并未加这个播放增益。详细原始幅度、增益、峰值、SHA256见 `instrument_preview_report.json`。

拨弦H2/H1在Hann窗测量中从早期0.448934降到后期0.031216；弦乐保持阶段为0.187439，两个持续窗RMS比1.000000。它们证明本次波形和时间变化不同，不代表主观逼真度或实物试听已经验收。播放工具也没有用软件生成替代声源。

## 高云综合与布局布线

Gowin V1.9.12.03，GW5AT-LV60PG484AC1/I0。独立工程 `fpga_project/instruments_check` 在所有同钟输入/输出加寄存器，使用唯一有效 `create_clock -period 20.000`；启用 timing-driven 和 hold correction，没有 false-path/multicycle 例外。

| 项目 | 最终结果 |
|---|---:|
| Setup / Hold 裕量 | +8.184 / +0.226 ns |
| Setup / Hold 违例 | 0 / 0 |
| 最小脉宽裕量 | +7.122 ns |
| 报告Fmax | 84.630 MHz |
| LUT / ALU / 寄存器 | 2622 / 626 / 1043 |
| 锁存器 | 0 |
| BSRAM / DSP | 12 / 20 |

最差Setup路径从声部2亮度常量计算 `guitar_product_0_s/DOUT[15]` 到亮度乘法 `n682_s/B[16]`。资源包含外壳寄存器；20个DSP也包含每路两套亮度常量运算，不能只按三个动态增益乘法估为12个。

综合有4条 `NL0002 u_strings` 层级合并提示。网表审计逐字验证12个物理pROM的12288个映射值，其中正弦表被优化成15位半幅值，拨弦／弦乐完整数据均在；同时检查128个选择LUT位的1024组真值，以及四路事件快照和亮度/包络连接。提示移除的是层级包装，弦乐数据没有被删除。布局布线没有告警。该审计是综合网表结构与内容检查，不是门级时序仿真。

`timing/` 保存原始综合、P&R、HTML时序、配置、压缩网表及JSON审计。复现时从仓库根目录运行：

```powershell
& 'C:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' fpga_project/instruments_check/run.tcl
python model/check_instrument_timing.py
python model/check_instrument_netlist.py
```

修改源码后必须重新执行构建，不能只执行checker来复用旧报告。checker会拒绝时间戳晚于报告的源码，完整证据仍以构建命令、成功退出码和对应哈希为准。

## 范围与下一步

这次通过的是功能仿真、独立数学核对及同钟注册接口模块时序。没有板级CST、外部I/O延迟约束或整机B/C连接证明；不能直接下载这个时序外壳。80ns核心输出延迟也不能替代整机演奏延迟。

B/C需要接入新 `voice_bank_instruments`、逐声部乐器选择、R4输出有效和释放反馈，重新跑整机联合仿真/P&R，然后上板进行同响度试听。吉他感／弦乐感是合成预设描述；混响、全局音量平滑、实时变调和实物音色验收不在本轮已完成范围。本轮没有提交或推送GitHub。

工具环境备注：旧ModelSim和Icarus在受限沙箱启动时发生系统DLL/访问异常；同一安全测试在沙箱外执行后成功。没有修改工具安装或系统配置。报告中的通过结论来自实际成功运行，不采用崩溃退出作为证据。
