# 2026-10-06 代码审查、资源优化与时序复核

## 结论与范围

按用户要求审查当前 A/B/C 集成代码，本轮 GitHub 交付分支为 `codex/adsr-integration`，不覆盖队友的 `master`。保留并纳入此前未提交的 ADSR 集成成果，没有操作板卡。

修复四项可复现的声部分配逻辑问题；用有界先后排名代替自由运行时间戳，同时减少资源。26项 ModelSim 回归、五个 Python 参考检查通过，串行负向对照正确拒绝；普通／自动版均重新完成综合、布局布线和位流生成。50MHz 现有约束下 Setup/Hold 违例均为0，但仍不是完整外部接口或实物签核。

本轮按 `code-reviewer` 的严重等级、定位和修复建议记录，结合 FPGA 的接口、定点、复位和时序证据复核；没有为了减少资源而改变 A 的采样流水线或放宽 SDC。主观代码质量评分 **8/10**：模块边界和可重复验证较完善；扣分项是队列长期背压合同、外部时序和实物证据仍不完整。此评分不代表赛题完成度或获奖判断。

审查重点：`voice_allocator`、`event_encoder`、`interaction_top`、`instrument_adsr_top`、`voice_bank_adsr`、`adsr_env`、增益／混音、`synth_top`、`sample_tick`、串行发送、CST／SDC及回归脚本。没有发现必须改动当前音频流水线的算术或接口错误；这不等于形式化证明全部输入组合无误。

## 已修复的逻辑问题

下列位置为修复后源码；修复前完整分配器保存在证据目录的 `baseline/voice_allocator.v`，仅用于单独编译复现，不能加入正式工程。

| 等级 | 位置 | 原问题与触发条件 | 修复与证据 |
|---|---|---|---|
| High | `rtl/voice_allocator.v:63`、`:282`、`:330` | 32位时间戳每个系统时钟递增，50MHz下约85.90秒回绕。跨回绕的活跃音符直接比较时间戳，会抢走新音而不是最早的音；不是每隔86秒必然出错，需要满声部及跨回绕音符。 | 改为全部槽的0～N−1唯一排名，0最新；note-on把目标移到首位，其前面的槽后移。四声部排名仅2位，去掉自由运行计数器。`tb_allocator_age` 先用8位旧参数缩短回绕复现，再覆盖重触发、空槽、400次有序分配及复位。 |
| High | `rtl/voice_allocator.v:163`、`:262` | 不同来源接管同音后，旧来源松键能通过“只按音符兜底”关闭新来源声部。 | note-off必须同时匹配source与note；`tb_allocator_owner` 覆盖旧来源、过期音符及正常松键。 |
| Medium | `rtl/voice_allocator.v:168`、`:297` | 表情更新也会只按音符兜底，把旧来源的弯音写入新来源声部。 | 表情仅按当前source匹配，`expr_note`保留兼容但不作为跨来源兜底。`tb_allocator_expression_owner` 覆盖合法更新与旧来源更新被忽略。 |
| Medium | `rtl/voice_allocator.v:145`、`:334` | 同音被不同来源接管，被当成“同一来源重触发”，继承旧来源弯音、触后和颤音状态。 | 同来源重触发保持表情；不同来源接管将四种表情字段归零。`tb_allocator_expression_reset` 用弯音验证保留／清除分支，其他三个字段同分支清零。 |

四个测试在原分配器上分别出现真实 Fatal，日志为 `tb_allocator_*_before.log`，不是根据修改后结果推测原代码会失败。修复后四项及原22项全部通过。参考模型使用64位单调事件序号，不复制 RTL 排名算法。

合同保持：分配优先级仍为同来源→同音→空闲→释放中的槽→最早按下的槽；同音仍只占一个槽，不改成两个同音并发声部。有效/接收握手、逐槽扫描周期、note-on单拍触发、尾音反馈、R3样本有效和R4下游接收均不变。`TIME_WIDTH` 参数仅保留实例兼容，不再决定排序范围。四声部与原32声部分配测试都通过；没有宣称32声部完整合成已实现。

当前两颗板载键音符固定且不同，后三项主要是通用C接口的边界问题；不能把它们描述为当前两键演奏每次都会发生。

## 实测资源与实现时序对比

两次均使用 Gowin V1.9.12.04、GW5AT-LV60PG484AC1/I0、Device Version B、50MHz／20ns，同一 CST／SDC和四声部参数。前值取自当天审查前的 `results/poly-integration-20261006/`；后值取自 `results/code-review-20261006/`。这是工具实现结果，不是仪器测量。

| 指标 | 普通版：前→后 | 自动版：前→后 |
|---|---:|---:|
| LUT | 2251→2119（−132，约5.9%） | 2983→2847（−136，约4.6%） |
| ALU | 607→576（−31） | 604→572（−32） |
| 寄存器总数 | 1147→965（−182，约15.9%） | 985→803（−182，约18.5%） |
| BSRAM／DSP | 4／8→4／8 | 4／8→4／8 |
| 最差Setup裕量 | +6.271→+6.619ns | +5.534→+5.669ns |
| 内部寄存器间最差Setup | +6.271→+7.213ns | +7.308→+6.852ns |
| 最差Hold裕量 | +0.162→+0.125ns | +0.123→+0.123ns |
| 工具报告Fmax | 72.836→78.202MHz | 78.788→76.055MHz |
| Setup／Hold违例数 | 0／0→0／0 | 0／0→0／0 |

普通版资源下降明显，内部Setup改善；自动版内部Setup及工具Fmax略退，仍满足当前50MHz约束。布局布线位置随网表变化，不能把资源减少等同于所有路径变快，也不能把报告Fmax当作建议提高板上时钟。

两版当前全局最差Setup都到 `PA_EN` 输出端，按本地20ns输出预算计算。真正最长的内部数据路径仍在 ADSR 起音初始化：`env_level` → `attack_step`（除以96）→ 加法／状态选择 → `env_level`。普通版报告的此路径为18级逻辑、+7.213ns；资源优化没有“消除除法关键路径”。

## 剩余问题与下一轮优化顺序

1. **Medium：事件队列在长时间堵塞下不是保序的边沿队列。** `rtl/event_encoder.v:26`、`:96`、`:123`、`:134` 用每键on/off各一个待处理位，且所有on先于off。同一键在FIFO满时先松开、后按下，会同时留下两个位，恢复后可能按on→off输出，最终状态与实际按住不符；同类多次边沿也会合并，同拍置位与清除以清除为准。力度／音色是在写FIFO时读取，不是边沿时快照。这是静态审查结果，本轮未加针对该背压情形的新测试或改写模块。当前5ms消抖、两键和四声部正常服务速度远低于队列吞吐限制，未在当前演奏链路复现。下一轮C在接入高频外部事件前明确最大背压时间、溢出策略，补按时间保序及参数快照测试，再决定队列结构；不能仅增大FIFO深度冒充解决。
2. **Medium：时钟路由PR1014仍存在。** 原50MHz V22输入到内部时钟使用通用路由，工具提示可能增加延迟／偏斜。8/8端口物理约束齐全不消除此风险。后续B结合该版本原理图与厂家时钟资源方案验证专用时钟接入；本轮不盲换引脚、供电或删告警。
3. **Medium：DAC外部时序与功放启动未签核。** `boards/tang_mega_60k_31004/demo.sdc:9` 以后仅是寄存器到引脚0～20ns预算，不是相对HP_BCK的完整DAC setup/hold约束。内部单时钟、同步释放复位和数字串行逐字测试已经覆盖，但实际引脚偏斜、PT8211-S LSBJ接口、功放启动／尾音，以及整机≤10ms仍需测量。不能用内部裕量替代这些结论。
4. **Low：ADSR时序进一步优化应单独立项。** `rtl/adsr_env.v:60`、`:62`、`:114` 的初始化除法与幅度更新是下一优先级。可以研究精确商余数分级计算，或在样本间隙复用运算，但现模块允许连续每拍请求，不能偷偷改成需要多个空闲拍。先确定新合同及精确取整、延迟，再改参考模型与集成；不能通过假多周期／假路径约束制造“时序通过”。当前四声部50MHz无需立即承担这项风险。
5. **Low：资源扩展建议。** 当前普通版逻辑约5%、寄存器约2%、BSRAM约4%、DSP约7%，无需为四声部立即共享ROM/DSP。扩到更多声部时再评估时分复用。FIFO深度、消抖／节拍计数位宽和调试统计也可按合同压缩，但必须看综合是否已经优化，不能按源码位数直接宣称节省。`event_encoder` 的深度与指针宽度须匹配（当前64/6合法），参数检查可在后续补齐。

未发现本轮改动包含硬编码访问凭证；Git远程使用普通HTTPS地址，无令牌。SQL/XSS等Web问题不适用本RTL项目，不把这种“不适用”算成安全验收。正式比赛的13键、双旋钮、第二音色和外部实时变调仍未实现，不因本轮代码审查而勾选R1—R7。

## 复现与交付

在仓库根目录运行，其他电脑替换成自己的实际工具路径：

```powershell
.\sim\run_tests.ps1 -Suite Review -ModelSimBin 'C:\Library\modelsim\win64'
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'C:\Library\modelsim\win64'
# 用实际Python 3逐个运行，均须成功：
# model/check_dds.py、model/check_adsr.py、model/check_abc_demo.py、
# model/check_poly_adsr.py、model/check_adsr_mix.py
.\sim\run_tests.ps1 -Suite ADSRDemo -NegativeControl -ModelSimBin 'C:\Library\modelsim\win64'
# 上一条应非零退出，日志须为 intentional ADSR serial mutation，而非编译失败。
Push-Location .\fpga_project
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_auto_demo.tcl
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_demo.tcl
Pop-Location
.\sim\save_adsr_evidence.ps1 -Destination 'results/自己的新证据目录'
```

复现修复前问题时单独编译，勿覆盖正式RTL或复用正常工作库：

```powershell
& 'C:\Library\modelsim\win64\vlib.exe' results/review_baseline_work
& 'C:\Library\modelsim\win64\vlog.exe' -sv -work results/review_baseline_work results/code-review-20261006/baseline/voice_allocator.v sim/tb_allocator_review.sv
& 'C:\Library\modelsim\win64\vsim.exe' -c -lib results/review_baseline_work -wlf results/review_baseline_work/age.wlf tb_allocator_age -do 'do {sim/run_allocator_review.tcl}'
# 同一库换为 tb_allocator_owner、tb_allocator_expression_owner、
# tb_allocator_expression_reset，应分别出现对应Fatal且非零退出。
```

实现脚本共用工程配置，必须串行。最终配置为 `instrument_adsr_top`／`instrument_adsr`，本机新普通文件是 `fpga_project/impl/pnr/instrument_adsr.fs`。大体积位流、波形、工作库和本机rollback不上传；源码、构建脚本、审查、原始报告和哈希上传。原10月2日／10月6日审查前记录保留为历史，不以其哈希验证当前源码。

本轮没有烧录、试听、示波器测量或连续实物演奏。下一最小实验仍是B用现有耳机低音量测试普通版的复位、单键／双键、长按、提前松键和尾音中重按，并记录真实结果。完整证据见 [本轮结果](../results/code-review-20261006/README.md)。
