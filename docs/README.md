# 文档导航

[返回作品首页](../README.md)

当前正式系统：NEO Dock 31005 + Tang Mega 60K，32 声部钢琴 / 电吉他、三效果、HDMI 显示。阅读专题文档时优先看最新日期的覆盖说明；旧测试、旧接线和旧位流只用于追溯。

## 我现在要做什么

| 任务 | 入口 |
|---|---|
| 了解作品、看指标与主架构 | [作品首页](../README.md) |
| 打开高云 EDA | [正式 HDMI 工程](../projects/hdmi/piano_hdmi.gprj)、[构建脚本](../projects/hdmi/build.ps1) |
| 接按钮、旋钮、滑条、屏幕、蓝牙 | [唯一接线表](keyboard-wiring.md) |
| 修改接线并同步约束 | [接线快速修改](../WIRING.md) |
| 固定按键、板卡与线束 | [装配说明](keyboard-assembly.md) |
| 调试 Windows 上位机 | [上位机说明](../host/README.md)、[串口协议](../host/STUDIO_PROTOCOL.md) |
| 连接鸿蒙手机 | [手机端说明](mobile-app.md) |
| 查比赛差距和团队任务 | [需求核对](contest-metrics-audit-20261025.md)、[计划与分工](../PLAN.md) |

## 按模块阅读

| 模块 | 技术说明 | 主要源码位置 |
|---|---|---|
| 整机音频与有效拍序 | [接口合同](design.md) | `rtl/top/`、`rtl/audio/` |
| 32 声部与双组并行 | [复音设计](polyphony32.md) | `rtl/synth/`、`rtl/control/voice_allocator.v` |
| 钢琴 / 吉他算法 | [合成设计](music-design.md)、[A 集成记录](integration-a.md) | `rtl/synth/`、`model/`、`rtl/rom/` |
| B 版钢琴参数 | [试听与验收](listening-acceptance.md)、[参数源](../model/piano_b_envelopes.json) | `model/gen_piano_v3_rom.py` |
| 明亮度 | [滤波响应](brightness-response.md) | `rtl/synth/`、`model/brightness_response.py` |
| 合唱 / 回声 / 混响 | [Delay 与 Chorus](delay-chorus.md)、[混响](reverb.md) | `rtl/synth/` |
| 输入与 ADS1115 | [C 输入说明](c-input.md) | `rtl/control/` |
| 中文显示 / HDMI | [显示合同](display-rgb.md)、[字体来源](display-font/README.md) | `rtl/display/` |
| USB 触摸 | [USB 驱动说明](usb-touch-driver.md) | `rtl/usb/`、`rtl/control/touch_contact_tracker.v` |
| 曲谱 / 键位 / 导奏 | [控制合同](design.md)、[手机能力](mobile-app.md) | `performance_controls.v`、`performance_store.v`、`timed_practice_guide.v` |

`touch-brightness.md` 保留早期触摸明亮度准备接口的历史设计，不能据此判断当前滑条或触摸驱动是否已接入；当前第三维由 ADS1115 AIN2 实体滑条控制。

## 验证与证据

| 想核对的内容 | 入口 |
|---|---|
| B 参数、正式构建与回归结果 | [piano_b/summary.json](../verification/evidence/piano_b/summary.json) |
| 原绝对时序目标 | [timing_closure/summary.json](../verification/evidence/timing_closure/summary.json) |
| 优化方案与取舍 | [时序优化记录](fpga-optimization-plan.md) |
| 测试入口、历史缺口与实物待办 | [验证说明](verification.md) |
| 自动检查与测试平台 | [scripts](../verification/scripts/)、[tb](../verification/tb/) |
| 引脚的机器可核对合同 | [board_31005_j13.json](../verification/data/board_31005_j13.json) |

证据摘要是指定时间、输入和工具下的记录；历史 `pushed:false` 不代表当前 GitHub 状态，测试通过也不自动等于实物验收。下载文件由正式工程生成，不从证据目录或旧试听包挑选。

## 工程边界

- **整机唯一入口：**`projects/hdmi/`。`boards/tang_mega_60k_31004/` 是历史目录名，当前对应 31005 接线合同。
- **项目目录：**`projects/`只保留`hdmi/`和其中一个`piano_hdmi.gprj`。旧无屏、A试听、显示、检查及演示工程已删除，本地生成输出一起清理；旧版本从Git提交`493c913`恢复。
- **共享工具与测试：**ROM检查、时序报告解析统一在`verification/scripts/`。共享RTL、`verification/tb/`及`upstream/fpga_interaction/`中的队友源码/原TB保留；上游资料不作为整机入口。
- **电脑与手机：**`host/` 只维护电脑程序；鸿蒙 App 是独立工程，本仓库不包含其签名材料或安装包。
- **生成文件：**`build/`、`projects/hdmi/impl/` 不作为源码入口。原资料在 `docs/sources/`，维护规则在根目录 `AGENTS.md`。
