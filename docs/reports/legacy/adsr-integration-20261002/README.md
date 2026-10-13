# 2026-10-02 四声部 ADSR 集成证据

来源：本地 `codex/adsr-integration` 基于团队 `master/e7dd27a`；整合A的ADSR v2，增加逐声部触发、四声部bank及新板级顶层。未提交、推送、下载或实物测量。

## 已执行

- ModelSim SE-64 10.6e：`sim/run_tests.ps1 -Suite All` 新旧20项通过，正常日志0 Error／0 Warning；另跑 `-Suite ADSR` 三项独立回归通过。
- Python 3整数／数学参考：DDS 1024项波表／4810样本；单声部ADSR 162085时钟／47734样本／14复位；旧ABC 128音符／745混音样本；新四声部61097样本／两个复位／各声部五种状态。
- `-Suite ADSRDemo -NegativeControl`故意翻转串行比较值，于10530ns报告 `intentional ADSR serial mutation`，脚本非零退出；这是预期拒绝，不是正常版本失败。
- 普通／自动版已用Gowin V1.9.12.04、GW5AT-LV60PG484AC1/I0、Device Version B综合、布局布线及生成下载文件，使用31004原有CST／SDC，没有改引脚或放宽时序约束。

| 项目 | 普通ADSR版 | 自动ADSR版 |
|---|---:|---:|
| LUT / ALU | 2983 / 563 | 3725 / 559 |
| 寄存器 | 1356 | 1194 |
| pROM / DSP | 4 / 8 | 4 / 8 |
| 目标系统时钟 | 50MHz | 50MHz |
| 工具报告Fmax | 50.063MHz | 50.167MHz |
| 最差Setup / Hold裕量 | +0.025 / +0.123ns | +0.067 / +0.143ns |
| Setup / Hold违例 | 0 / 0 | 0 / 0 |
| 端口引脚约束 | 8/8 | 8/8 |

这些是工具报告，不是板卡实测性能。报告中主时钟、按键／复位异步例外和输出布线预算均为Actived；例外只针对外部异步端口，后级路径继续约束。PR1014非专用输入时钟路由警告保留，NL0002为各模式未用模块优化。最差裕量很小，后续变更必须重新实现；外部DAC建立／保持与时钟可靠性未签核。

## 文件身份与复现

- `All_sha256.txt`：全回归的RTL、测试、脚本和ROM身份。
- `artifacts_sha256.txt`：工程／约束／模型、两版报告及下载文件身份；大体积 `.fs` 保留在本机工程输出目录，不复制进证据目录。
- 20份正常测试日志和一份预期失败的串行负向日志；三项A日志随后用相同源码的独立ADSR套件再跑通过。
- `instrument_adsr.rpt.txt`／`.tr`、`instrument_adsr_auto.rpt.txt`／`.tr`：原始引脚、资源、约束及完整时序报告。
- 波形和逐样本轨迹在本机 `results/waves/` 与 `results/logs/`，可按 [集成说明](../../docs/adsr-integration.md) 重建；证据保存脚本不代替测试。

新普通版：`fpga_project/impl/pnr/instrument_adsr.fs`；新自动版：`instrument_adsr_auto.fs`。旧 `instrument_demo.fs` SHA256仍为 `7DD5FECCF44F8A4F4B4220ACD6097D80A8EE09DCDAFA6FE5971A07BB2AF51586`，未被本次构建覆盖。

仅证明数字功能和当前约束下实现结果。新版本实物音质、可闻独立四声部、实际采样率、整机≤10ms及比赛演奏维度／I2S口径均未验收，不勾选R1—R7。
