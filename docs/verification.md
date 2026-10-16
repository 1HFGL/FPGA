# 验证入口与结果边界

当前主工程是`music-classic16`：钢琴v3／经典摇滚、16复音、音量及±2半音弯音。用户在新版试听后反馈“应该是可以了”，记初步试听可用；不是完整稳定性、延迟或音质测量结论。

## 本次A工程精简后的实际验证

沿用本地master `0406c60`的目录，删除99个退役源码／ROM／工程及专用测试文件。远程获取失败，未宣称同步最新远程。当前综合RTL、四份ROM、GPRJ、约束和已试听位流均与清理前逐文件哈希一致；C独立快照原样保留。

| 检查 | 本轮结果 |
| --- | --- |
| 工程依赖 | 27个有效RTL模块无重名，2个GPRJ路径完整；A合成2文件、ROM4文件 |
| 严格Verilog-2001 | 50个当前RTL／TB文件通过，无SystemVerilog模式 |
| 主工程7组RTL | 协议、4/16参数化合成、UART16、显示隔离、参数控制、C同步接口、连续恢复全部通过 |
| 独立音频模型 | 4/16声部各11,400采样精确匹配；旧曲线重放原黄金摘要、300帧纯钢琴一致；未改黄金摘要 |
| 控制及音域 | 7,500采样逐位匹配；74组C3～C6预设参数通过；弯音ROM最大误差0.014559音分 |
| UART16 | 54,614个串行字匹配，16摇滚声部、预设切换、第17音抢占、来源隔离与看门狗通过 |
| 显示联合隔离 | 2020个R924样本、4041个DAC字；显示停钟／复位不阻塞音频 |
| 连续操作恢复 | 64轮和弦／重触发、16次看门狗恢复，21,139个R924样本通过 |
| B／C支持回归 | B音频3项、C事件／分配7项、UART字节1项通过 |
| 功放排空 | 测试迁移到当前16声部顶层，lead=60，短尾音13点／默认4096点两项通过；仍检查DAC左右字与待发帧，不仅检查最终静音 |
| 上位机 | 59项测试通过；移除的1项仅验证退役`piano_1024.mem`，现行演奏测试未删 |

证据集中在`build/cleanup_a/`：`plan.json`删除理由与哈希、`source_layout.json`当前工程清单、`summary.json`保护文件核对及结果、各项运行日志。完整主回归捕获在`build/regression/music/`。旧目录批量删除未获自动审批，历史生成物暂留并排除提交。

旧DDS／四声部波表专用脚本不再是有效入口；旧R4延迟模型已退役，不用它证明16复音延迟。保留的4声部测试使用当前同一核心的参数化实例R251/R252。测试用旧失真曲线由解析式临时生成，仅用于原摘要回归，不进入板级综合。

## 复现

仓库根运行；Python安装`model/requirements.txt`，上位机另按`host/README.md`准备Qt环境。

```powershell
python verification/scripts/check_source_layout.py
./verification/scripts/check_verilog.ps1 -ModelSimBin D:/modelsim1/win64
./verification/scripts/run_tests.ps1 -Suite All -ModelSimBin D:/modelsim1/win64 -Python python
& '.venv-studio/Scripts/python.exe' -m unittest discover -s host -p 'test_*.py' -v
./verification/scripts/check_audio_parameters.ps1 -ModelSimBin D:/modelsim1/win64
./verification/scripts/check_c_rtl.ps1 -ModelSimBin D:/modelsim1/win64
./projects/piano/build.ps1 -Gowin C:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe
```

仅复验A选`-Suite A`，其他可选B/C/UART/Display/PA。负向串行对照为`python verification/scripts/run_music_tests.py tb_music_uart16 --negative --bin D:/modelsim1/win64`。本次不重复运行未受影响的显示独立6项、音频参数3合法／12非法、C快照严格编译及负向串行测试；原通过记录仍在build，不能称为本次重新运行。

ROM重建：`python model/gen_piano_v3_rom.py`、`python model/gen_pitch_bend_rom.py`、`./model/gen_sine.ps1`。第一条使用已保存参考参数并生成共享钢琴／吉他模态表及失真表；吉他公式库已删除无人调用的旧钢琴分支和旧模态ROM输出入口。独立模型对全部预设／音符重新编码并核对当前ROM，确保清理不改变数据。

参考录音只供离线提取，常规构建不联网。来源为`model/piano_reference_sources.json`，提取脚本为`fetch_piano_reference.py`／`analyse_piano_reference.py`；提取还需Python 3.12的aifc和NumPy。

## 保留的已试听构建

位流：`build/audition/music_classic16_20261014_201505/music_classic16.fs`，SHA-256：`55ddab166832b0df000993de6f9ce1d6465862ad961595e29ee67376ac2b1cce`。本次整理未改综合输入，不重新烧录、不重复生成位流；原发布包保持交付时快照。

该次Gowin 1.9.12.03构建目标GW5AT-LV60PG484AC1/I0 Version B、50MHz，综合／布局布线和现有约束检查通过：12,681逻辑（10,499 LUT＋2,182 ALU）、5,625寄存器、79 BSRAM、11 DSP、10个已约束信号。最差setup +2.832ns、hold +0.085ns、recovery +17.340ns、removal +0.701ns、脉宽余量 +6.809ns。受控配置与实际配置一致，详见发布目录及`build/piano/`。

PR1014通用时钟布线告警及完整DAC外部时序尚未闭合，以上不是完整板级签核。屏幕接入尚无实际引脚／PLL／触摸驱动。13实体键／触摸／两旋钮接入后，仍需分别测物理输入至模拟输出的延迟；R924内部缓存合同不能替代整机≤10ms／≤5ms验收。

## 经典摇滚参数依据

传递表由12000*tanh(x/900)改为16100*tanh(x/1400)，减轻驱动并补偿参考单音RMS；模态／箱体／拨弦／钢琴路径保持基线。默认音量8，主音量在失真后，不能用降低主音量等同于降低失真驱动。

参考模型固定力度100，保持375ms、释放125ms，统计64～17999帧：C3/C4/C5/C6新旧RMS差−0.109/+0.024/+0.069/+0.046dB；五度+0.456dB、四音+0.560dB、16音压力+1.503dB。500ms整段中四音接近失真曲线上限95%的插值点比例由5.732%降到1.153%；这是驱动诊断，不是PCM削波率或音质评分。

36组相干正弦诊断的非预期频点能量变化中位数+0.253dB，范围−2.560～+1.835dB，仅9组下降；不能宣称杂散全面降低或抗混叠已完成。下一轮需结合实际高音／弯音听感评估查表量化、重采样滤波。

分析脚本`model/analyse_classic_rock.py`；原结果`build/analysis/classic_candidate/analysis.json`及新旧参考WAV。WAV是模型预览，每段0.5秒依次C3/C4/C5/C6/五度/四音，共同额外增益8；不是板卡录音，也不会装入FPGA播放。本次未改变分析算法，原结果的源码哈希是生成当时的记录。


2026-10-14补充：用户已明确确认删除旧产物。三个空退役工程目录已删除；deliveries/results/fpga_project的递归删除仍被执行工具策略拦截，三个目录仍在。无需再次索要用户授权，后续需解决执行限制。92个保护输入及完整classic16发布包经哈希复核未变。
