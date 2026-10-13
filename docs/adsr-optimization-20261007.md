# 2026-10-07 ADSR 等价优化试验

> 2026-10-13路径维护：本页功能状态、资源／时序数字、日志与哈希仍对应原记录日期，不代表当前版本的新验收。可复用的主工程命令已改用新目录；新运行结果写入 `build/`，不覆盖历史证据。当前工程及完整验证入口见 [目录迁移说明](repository-layout.md) 与 [README](../README.md)。

## 结论

三种候选均通过算术与包络测试，但没有取得适合当前四声部工程的资源／时序综合收益，因此**全部退出正式RTL，恢复 `d909b17` 的 `adsr_env.v`**。这次交付是更强的回归测试和可复现的取舍证据，不是已达成新一轮资源或时序优化。

遵守用户确认的边界：包络逐点数值、A/D/R时长、连续每拍请求能力、复位、重触发和输出流水线均不变；不改音色、按键、引脚、SDC或系统时钟。事件队列不在本轮修改范围。没有上板、Git提交或推送。

按 FPGA 验证流程保留失败的优化候选；三次没有得到合适替换后停止继续试改，不把其中的局部收益夸大成整机改善。

## 开源参考与来源边界

- [gundy/tiny-synth 的包络实现](https://github.com/gundy/tiny-synth/blob/1621a8dd0d4ca56507947d2d086deacc4cc9bdd4/hdl/envelope_generator.vh)：参考其将固定参数换算放到常数表、运行时使用累加器的思路，但没有复制源码。该项目是8位包络、指数衰减／释放，与本项目Q1.16线性、精确段长合同不同，不能直接替换。版本为 `1621a8dd0d4ca56507947d2d086deacc4cc9bdd4`；[许可证](https://github.com/gundy/tiny-synth/blob/1621a8dd0d4ca56507947d2d086deacc4cc9bdd4/LICENSE)为 CERN OHL v1.2。本项目没有引入其代码或IP，也不把对方许可证附会为本项目许可证。
- [alexforencich/verilog-axis 的 axis_fifo](https://github.com/alexforencich/verilog-axis/blob/48ff7a7e2ef782cf778d47910cf85835c64b1bce/rtl/axis_fifo.v)采用MIT许可，可作后续队列握手、满载／溢出处理的阅读参考，本轮未接入。该仓库提示已被后继项目替代，所以这里只作已有Verilog实现的参考，不新增依赖。

本轮三种算术变换与测试为本项目编写。常数表来自整数除法，不是录制的音频样本；没有导入外部预录音、CPU音源或厂商无关的引脚约束。

## 对照方法和实际结果

同一工程、Gowin V1.9.12.04、GW5AT-LV60PG484AC1/I0、Device Version B、50MHz／20ns、默认A96/D24000/S6554/R5760、相同CST/SDC及工具选项。各候选只进行一次普通版布局布线，不在多次运行中挑最好值。工具布局会受网表变化影响，以下是这几次具体实现结果，不是普适性能结论。

| 普通版实现 | LUT | ALU | 寄存器 | BSRAM / DSP | 内部最差Setup | 工具Fmax |
|---|---:|---:|---:|---:|---:|---:|
| 原版，恢复后重建 | 2119 | 576 | 965 | 4 / 8 | +7.213ns | 78.202MHz |
| 分离2的幂因子 | 2118 | 576 | 965 | 4 / 8 | +6.966ns | 76.724MHz |
| 小常数表分解 | 2340 | 652 | 965 | 4 / 8 | +7.484ns | 79.900MHz |
| 精确倒数乘法 | 1857 | 600 | 965 | 4 / 16 | +5.417ns | 68.573MHz |

全部实现的Setup／Hold违例都是0。全局最差Setup含PA_EN输出预算，分别为+6.619、+6.252、+6.364、+5.417ns；不能用全局输出路径与内部路径混作同一指标。

1. **分离因子**：96=3×32，5760=45×128；低位直接组成余数，高位只做12位÷3、10位÷45。算术正确，但资源几乎没变，说明当前综合结果已经包含类似简化；不能仅因RTL写窄就宣称减少硬件。
2. **常数表**：起音高12位分成两组6位查商余数，释放高10位分成两组5位后做进位校正。内部裕量只多0.271ns，LUT却多221，约10.4%；四声部当前已满足50MHz，没有理由为这点裕量保留更多逻辑。
3. **倒数乘法**：`floor(h*2731/8192)`替代÷3，`floor(h*1457/65536)`替代÷45，并用乘回后相减求余数。常数在相应12位／10位范围内精确，不是误差可见的近似；LUT少262，但DSP增加8，最差内部路径变成释放余数计算中的两级未寄存DSP串联，内部裕量损失1.796ns。实测没有达到本轮目标，未保留。

第三版的具体路径是 `env_level` → `g_release_5760.product` → `g_release_5760.multiple` → 余数减法 → `error_acc`；两级DSP单元延迟分别约3.824ns、3.779ns。这说明“乘法一定比除法快”不成立，还要看工具映射及流水线。

## 保留的验证改动

- 新增 `sim/tb_adsr_arithmetic.sv`：对0～65536全部65537个合法幅度，分别验证默认起音／释放的商、余数和下一点幅度，共131074组算术检查；结束后检查同步复位。
- 使用仅在测试平台中的层次force注入幅度，参考值用整数`/`和`%`直接计算；不把force或新的组合时钟带入正式设计。该检查不是完整状态空间形式化证明，时序行为由原包络回归继续负责。
- 原 `tb_adsr_env` 从10组扩到12组参数，增加默认起音与默认释放分支分别单独启用的组合，总计1929506项检查；原测试条件未放宽。
- 新增 `ADSRMath` 套件和对应负向控制。故意翻转观察商的最低位，在21ns被正确拒绝；正式RTL不含该错误。
- `save_adsr_evidence.ps1` 保存27项回归，并检查正常和两个负向测试的源码哈希与预期故障，防止混入旧负向日志。

最终恢复后的全量结果：27项ModelSim回归、5个Python参考程序通过；算术负向和串行负向分别在21ns／10530ns正确失败。普通与自动工程均重新综合、布局布线并生成正式位流，不留下候选版作为默认输出。

恢复后普通版Setup/Hold为+6.619/+0.125ns，自动版为+5.669/+0.123ns，50MHz下均无违例，与10月6日基线的资源／时序数字一致。8/8端口有物理约束，活动主时钟和原例外／预算未变。PR1014、完整外部DAC时序、功放启动和整机延迟仍待验证。新位流有本轮独立哈希，不声称与旧位流字节相同。

## 复现

在仓库根目录运行，工具路径按本机安装修改：

```powershell
.\verification\scripts\run_tests.ps1 -Suite ADSRMath -ModelSimBin 'C:\Library\modelsim\win64'
.\verification\scripts\run_tests.ps1 -Suite All -ModelSimBin 'C:\Library\modelsim\win64'
# 用实际Python 3运行 check_dds.py、check_adsr.py、check_abc_demo.py、
# check_poly_adsr.py、check_adsr_mix.py（均在model目录）。
.\verification\scripts\run_tests.ps1 -Suite ADSRMath -NegativeControl -ModelSimBin 'C:\Library\modelsim\win64'
.\verification\scripts\run_tests.ps1 -Suite ADSRDemo -NegativeControl -ModelSimBin 'C:\Library\modelsim\win64'
# 两个负向命令必须非零拒绝，且日志应是相应算术／串行故障，不是编译错误。
Push-Location .\projects\examples\adsr
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_auto_demo.tcl
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' build_adsr_demo.tcl
Pop-Location
.\verification\scripts\save_adsr_evidence.ps1 -Destination 'build/regression/自己的新证据目录'
```

三个候选源码及实现报告分别位于结果目录的 `factor_trial/`、`table_trial/`、`reciprocal_trial/`。它们只是实验快照，**不加入正式GPRJ，也不能用递归通配符与正式同名模块一起编译**。需要复现实验时，在独立工程副本内单独替换 `adsr_env.v`，保持其他源码和约束为 `d909b17`，运行上述测试／普通版构建。

## 下一步建议，尚未实施

没有证据表明原实现已经是最优。下一轮可针对已定位的DSP串联，研究显式移位加法或厂商支持的算术映射控制；这些仍需重新验证资源与时序，不能先承诺收益。

若追求更明显的时序提升，再与A/B确认是否允许把包络初始化分多拍计算：真实48kHz采样有系统时钟间隙，但当前核心合同允许每拍请求。利用间隙意味着要明确最小请求间隔、触发暂存和有效信号对齐，不能直接加寄存器却声称接口毫无变化。

完整记录见 [本轮证据目录](reports/legacy/adsr-opt-20261007/README.md)。未修改事件队列、时钟引脚或外部接口，也未勾选赛题实物验收。
