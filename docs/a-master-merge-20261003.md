# A 分支合入团队 master：2026-10-03

本次把团队现有集成代码合入本地 `feat/a-dds-core`，保留 A 已验证的单声部 ADSR 时序优化。这里只同步代码、解决冲突并验证功能；四声部完整 ADSR 尚未接入，也没有重新生成板级下载文件。

## 合并范围与冲突处理

合并前 A 为 `8032be88501a36e3ba09bb6091e410afeaa3dda9`，本次成功获取并合入的 `origin/master` 为 `e7dd27a4f8d2aeaee4081b947abfa869b530c9a5`。合并提交保留两个父提交，便于追溯来源。

团队新增的 B/C 控制与输出、四声部 demo、128 音符步长表、高云工程、约束、集成测试及历史报告均保留。没有用 A 的旧目录整体覆盖团队文件。

七处冲突的处理如下：

| 文件 | 保留与调整 |
|---|---|
| `rtl/adsr_env.v`、`sim/tb_adsr_env.v` | 保留 A 时序优化及 10 组参数边界测试；master 的文件与优化前版本相同 |
| `docs/a-adsr.md`、`docs/a-adsr-validation.md` | 保留 A 当前说明和历史验证记录 |
| `README.md`、`PLAN.md` | 保留 master 的团队方案与集成记录，补回 A 最新优化结果及本次同步状态 |
| `sim/run_tests.ps1` | 合并两边入口，保留 A/ADSR 和 B/C/AB/Demo/All；修复独立 ADSR 依赖，恢复 ADSR 轨迹导出 |

`-Suite A` 仍执行 DDS 与 ADSR 共 6 项；`-Suite ADSR` 执行 3 项。共享 DDS 源码去重编译，ROM 仍包含在源码哈希清单中。没有改变 ADSR 端口、默认参数、包络时长或流水线延迟，也没有放宽已有测试。

优化后的 `adsr_env.v` SHA256 保持为：

```text
A2B80DC2C5B47C64B9FF538612412C44F919765D87EC7303467D78D6E45B41DC
```

## 本次实际验证

使用 ModelSim SE-64 10.6e 和 Python 3.12。以下结果是本次合并后重新运行所得。

| 检查 | 结果 |
|---|---|
| ModelSim `-Suite All` | 17 项全部通过：A 6、B 2、C 6、AB 1、四声部 demo 2；各仿真日志 Errors/Warnings 均为 0 |
| ADSR 参数与边界 | 10 组参数、1905232 项包络检查通过 |
| 音量乘法 | 458757 项检查通过 |
| Python DDS | 1024 个 ROM 值、4810 个 RTL 样本、6 次复位记录一致 |
| Python ADSR | 162085 个时钟、47734 个样本、14 次复位、全部 5 个状态一致；A/D/R=96/24000/5760 点 |
| Python ABC | 128 个音符步长、745 个四声部混音样本、2 次复位一致 |
| 全新目录独立 ADSR | 没有旧编译库的条件下 3 项均通过，确认脚本已显式包含 DDS 依赖 |
| AB 负向验证 | 故意翻转测试平台观察到的串行位，产生 `expected=0000 actual=8000`；回归脚本正确报错并拒绝通过 |

负向验证仅污染测试平台观察值，使用独立工作库，不修改可交付 RTL。其日志中的 1 个错误是预期检测结果，不属于正常回归错误。

原始仿真日志、输入哈希清单及结果摘要保存在 [本次证据目录](reports/master_merge_20261003/)。大体积波形和采样轨迹留在本机忽略目录中，可用下面的命令重新生成。

在仓库根目录执行：

```powershell
.\sim\run_tests.ps1 -Suite All -ModelSimBin 'D:\modelsim1\win64'
python model/check_dds.py
python model/check_adsr.py
python model/check_abc_demo.py
```

独立 ADSR：

```powershell
.\sim\run_tests.ps1 -Suite ADSR -ModelSimBin 'D:\modelsim1\win64'
python model/check_adsr.py
```

AB 负向检查：

```powershell
.\sim\run_tests.ps1 -Suite AB -NegativeControl -ModelSimBin 'D:\modelsim1\win64'
```

最后一条应在 `tb_single_tone_ab` 因串行不匹配报错，不能当成要求全部通过的普通回归。

## 保留的时序证据与下一步

A 单声部已有的 Setup +8.265 ns、Hold +0.247 ns 是此前 `voice_adsr`、50 MHz 下的独立实现结果，记录见 [时序优化说明](a-adsr-timing-20261003.md)。本次合并保留该优化与原始报告，但没有重新对合并后的整机顶层进行综合、布局布线或实物测量，不能用该单声部结果代替整机时序结论。

目前 `rtl/demo_voice_bank.v` 的四个声部仍采用原来的简单起音/释放渐变包络。下一项开发是在这套已同步的集成代码上接入四路完整 ADSR，检查独立包络、松键尾音、重触发、第五键抢占和混音边界。

本次代码合并不需要队友先在电脑上操作。后续接入四声部时，与 C 核对每声部独立触发和真实释放完成反馈，与 B 核对增加的请求到样本有效延迟。公共接口确认后再更新联合测试及板级时序。

此次只完成本地合并提交，未推送到 GitHub。推送 A 分支后队友才能获取此次合并结果；不会因此自动把 A 的新实现合回 master。
