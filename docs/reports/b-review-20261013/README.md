# B通路基线复核：尾音关闭、时序与构建证据

检查日期：2026-10-13；HEAD `69110f5`，另有未提交中文显示实现。未修改RTL、测试平台、工程约束或队友目录；未迁移、删除、推送或上板。这里是审查与诊断结果，不是修复完成报告。

## 1. 本轮实际执行

| 检查 | 结果与范围 |
| --- | --- |
| `sim/check_verilog.ps1` | 96文件严格Verilog-2001编译通过，未用SV模式 |
| `sim/run_tests.ps1 -Suite All` | 34项原有测试通过，退出0；不包含新增真实消抖延迟验收 |
| `fpga_project/uart_piano/build.ps1` | 综合、布局布线、位流生成与既有实现检查通过；未下载 |
| `tb_uart_instrument`原测试 | 通过；短包络/短消抖配置，不代表默认钢琴延迟 |
| UART顶层尾音观察 | 发现PA已经关闭但当前串行样本非零，诊断主动退出2 |
| 钢琴wrapper尾音观察 | 默认钢琴ADSR也复现，诊断主动退出2；测试消抖仍为4拍 |

原始证据保存在[baseline](baseline/)：34项回归日志和源清单、严格编译记录、钢琴实现报告、尾音诊断日志。诊断只在ModelSim外加观察条件，未force信号、未改参数、未改RTL或原tb。退出2表示命中待修缺陷，不是工具崩溃。

## 2. 审查发现

### B-01／Medium：UART钢琴顶层提前关闭功放

位置：`rtl/instrument_uart_top.v:69`直接把`sounding`接给`audio_enable`；`rtl/synth_top.v:77`立即生成低有效PA使能。`rtl/voice_bank_adsr.v:95`附近的`mixed_nonzero`只保留最后参与混音的样本状态，不包含B正在串行发送的旧帧。

根因：合成器“已输出零样本”和发送器“已完成最后一个非零帧”不是同一时刻。B缓存/活动帧在A静音后仍可能非零，当前顶层没有等待这部分排空。现有`instrument_presets_top.v:61`已有另一条演示路径的排空处理，但UART/钢琴顶层没有相同保障。

稳定复现结果：

| 观察配置 | PA关闭时刻 | 当前发送样本 | 当前帧切换为零的时刻 | 间隔 |
| --- | --- | --- | --- | --- |
| 原`tb_uart_instrument` | 1,000,530ns | 99 | 1,021,290ns | 20.760µs |
| 原`tb_uart_piano_board` | 198,042,190ns | −1 | 198,062,970ns | 20.780µs |

两次命中均处于非复位、audio_ready=1、右声道、bit_index=0；观察持续到活动样本清零，不是同一仿真时刻中的临时delta变化。Tcl `$now`原始单位为ps，表内换算为ns。

影响：尾音最后一帧尚未完整发送就关闭PA。默认钢琴此用例最后样本仅−1，不能由数字仿真推断听得见的杂音或量化音质损失；这是接口时序缺陷，不是“钢琴完全不能发声”。

建议修复：在板级集成处加入有界的输出排空策略，兼顾待发样本、左右完整字以及送出零帧；复位仍立即关闭。排空计时应依据真实发送帧语义，不能在提前请求后继续误用“请求就是发送边界”的假设。优先简单计数，不改A音色或包络，不增加新音启动等待。

验证缺口：原钢琴测试在PANIC后5帧和8650帧检查PA，只证明中途保持及最终关闭；逐字检查只看数字数据，不检查发送非零帧期间PA是否仍开着。因此原回归通过和这个缺陷可以同时存在。

### B-02／Medium：钢琴构建清单未记录实际process配置

位置：`fpga_project/uart_piano/build.ps1:11`起的输入清单包含GPRJ、脚本、源码、ROM及上位机预设，但未包含`impl/uart_piano_process_config.json`。`build_piano.tcl`只显式设置顶层及输出名，不能从这些信息完整恢复其余实现选项。

现场文件在Git忽略目录中，含`Correct_Hold_Violation`、`Run_Timing_Driven`、I/O寄存器放置、综合语言等设置。重整目录时若把它当缓存直接删掉，或换机器后使用不同默认值，旧报告不能独自证明复现配置相同。

本轮把构建后文件原样保存为[process_config_postbuild.json](baseline/piano-build/process_config_postbuild.json)，SHA256为`E605E933D74ACA2A95F9B227F362EFB7FA01ECC597443A47CA94D8E5FC4A5F52`。这是构建后快照，不伪称已经具备构建前后配置哈希检查。

建议修复：把必要选项写入受控配置/脚本，并纳入构建输入哈希及前后检查；迁移后做不依赖旧impl缓存的干净构建。

### B-03／Low：默认ModelSim/VS Code入口仍指向缺失练习

位置：根`run_modelsim.ps1`的默认Top/Sources，以及`.vscode/tasks.json`两项默认任务。此前已复现`rtl/dds_sine.v`不存在导致编译入口报错；本轮确认引用仍未改变。

建议：目录迁移时改为当前B音频测试的严格编译/运行入口，不保留一个打开即失败的默认任务。

### B-04／Medium，验证缺口：默认配置整机延迟仍未证明

位置：`sim/tb_uart_piano_board.v:24`消抖覆盖为4拍；现有板级测试没有稳定物理按键到可识别模拟输出的测量。真实默认100000拍消抖为约2ms，且还需等待事件、采样和输出。

建议：按已批准设计补真实配置的分段测试、最坏相位分析与硬件测量。不能将本轮尾音排空间隔、R0→R4计算时间或正时序裕量当作整机≤5/10ms证据。

总体代码质量暂评7/10：原回归和接口说明有基础，但PA排空边界、默认验证入口及构建配置可复现性仍有明确缺口；这是审查判断，不是比赛评分。

## 3. 本轮实现基线

50MHz、GW5AT-LV60PG484AC1/I0、Version B；Gowin V1.9.12.04。

- 5211 LUT＋692 ALU，合计5903逻辑单元；2708寄存器；4 BSRAM、8 DSP。
- 最差setup裕量+6.726ns，hold+0.247ns；当前报告中setup/hold违例端点均为0。
- 最差setup路径为UART接收FIFO读指针到行解析器参数寄存器使能，不是A音频乘法器路径。不能据“资源有剩余”就认定需复制音频运算单元或提频。
- 6条现有约束均显示Actived；PR1014通用时钟路由警告仍在。DAC只有寄存器到引脚min/max预算，完整相对BCK外部时序未闭合。

原始[资源报告](baseline/piano-build/instrument_uart_piano.rpt.txt)、[时序报告](baseline/piano-build/instrument_uart_piano.tr)、[构建日志](baseline/piano-build/build.log)、[输入清单](baseline/piano-build/build_inputs.txt)、[位流身份](baseline/piano-build/artifact.txt)。以上是修改前基线，不是优化后的收益，不是全部板级时序签核。

## 4. 复现尾音观察

先在仓库根编译现有RTL/测试并运行原用例：

```powershell
./sim/run_uart_tests.ps1 -Tests tb_uart_instrument -OutputDirectory build/b-review-20261013/baseline/uart-tail
```

该脚本也编译`tb_uart_piano_board`。随后使用同一工作库启动ModelSim，`-voptargs=+acc`保留内部观察对象。完整实际命令在[UART诊断日志](baseline/pa-tail/pa_tail_duration.log)和[钢琴诊断日志](baseline/pa-tail/piano_pa_duration.log)首段；核心观察条件如下，未修改DUT：

```tcl
when -label pa_tail_probe {
  /tb_uart_piano_board/pa == 1 &&
  /tb_uart_piano_board/rst == 1 &&
  /tb_uart_piano_board/dut/u_core/audio_ready == 1 &&
  /tb_uart_piano_board/dut/u_core/u_b/u_i2s_tx/active_sample != 0
} {
  echo OBSERVED_PIANO_PA_OFF_WITH_ACTIVE_SAMPLE
  echo time_ps=$now
  echo active=[examine -radix decimal /tb_uart_piano_board/dut/u_core/u_b/u_i2s_tx/active_sample]
  nowhen pa_tail_probe
  when -label drained {
    /tb_uart_piano_board/dut/u_core/u_b/u_i2s_tx/active_sample == 0
  } {
    echo ACTIVE_CLEARED_AT_PS=$now
    quit -code 2 -f
  }
}
run -all
quit -code 0 -f
```

诊断编译输入见[normal_inputs.txt](baseline/pa-tail/normal_inputs.txt)。该原UART清单未列钢琴ROM，补充其当前哈希：`rtl/rom/piano_1024.mem`为`B3ABCC11A9302601C994AFCE9161258DA1A80EF247E2D4F745275ECAF4826F1B`，并已包含于本轮钢琴构建输入清单。后续正式新增测试必须自动记录它，不能依赖人工补注。

## 5. 下一步与未执行事项

用户已选择按实施计划在当前对话连续执行。先把B-01变成正式Verilog自检并修复，再比较提前请求；按设计门槛验证后才做目录迁移。B-02/B-03纳入构建与入口重整。

未执行：上述缺陷修复、真实消抖延迟新测试、请求时刻优化、目录迁移/清理、合并显示进物理顶层、GitHub推送、板卡下载和实际延迟/音质测量。队友测试原样保留，未重新运行。
