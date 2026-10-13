# 迁后 host/model 文本验证证据

归档日期：2026-10-13。五份日志原样复制自 `build/b-review-20261013/migration-host-model/`；本次只归档与核对哈希，没有重跑测试、构建或操作板卡。先前测试使用本机 `.venv-studio/Scripts/python.exe`（Python 3.12.14）。

| 检查 | 实际结果 | 原始日志 |
| --- | --- | --- |
| Python语法 | host/model共29份Python源码通过语法编译；不等于所有模块运行依赖齐备 | [syntax.log](syntax.log) |
| 上位机单测 | 32项通过，耗时4.230秒；含预设、数据模型与Qt界面测试 | [host-unittest.log](host-unittest.log) |
| 基础双波表 | soft/bright各1024点精确匹配，并核对直流与谐波 | [timbre-rom.log](timbre-rom.log) |
| 乐器波表 | guitar/strings共2048点精确匹配，基频及谐波检查通过 | [instrument-rom.log](instrument-rom.log) |
| 钢琴模型预览 | 169920帧，3.540秒，峰值3093，RMS 501.221 | [piano-preview.log](piano-preview.log) |

单测原命令为 `.venv-studio/Scripts/python.exe -B -m unittest discover -s host -p 'test_*.py' -v`；波表检查对应 `model/check_timbre_rom.py` 和 `model/check_instrument_roms.py`。语法日志只记录总数，不冒充包含逐文件源哈希的原始测试清单。

## 字节保留核对

[hash-audit.json](hash-audit.json)记录本次实算SHA256：5个ROM、5个预设JSON、2个模型源码（`host/studio_model.py`、`host/wavetable.py`），合计12份，全部与[迁移前清单](../../migration/migration-manifest.json)一致。这里不是“12个ROM再加2个模型”，也不证明所有host/model源码均未改动。

同一JSON还记录五份源日志与归档日志的SHA256，复制前后全部一致。ROM检查中的正弦、明亮、吉他、弦乐只代表数字波表数学特性，不证明真实乐器音质。

## 验收边界

钢琴预览由Python参考模型生成，是纯模型输出，**不是硬件录音，也不是FPGA上板验收**。其WAV保留在本机 `build/audio/piano_preview-migration-20261013.wav`，不在本目录归档；截图、工作库、缓存及虚拟环境也未复制。

此证据不包含Gowin实现、RTL数字链路的新回归、实体按键／旋钮、屏幕硬件、模拟输出或整机延迟测量。旧版 `host/main.py` 的可选依赖未安装，本轮未启动该旧入口；不能把32项测试通过推广成全部历史界面均可运行。
