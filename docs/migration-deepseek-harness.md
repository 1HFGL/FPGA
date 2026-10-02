# FPGA 电子乐器项目迁移与 DeepSeek Harness 接手说明书

编写日期：2026-10-02。适用环境：Windows，使用 DeepSeek Harness 接手开发，现有板卡与音频硬件一并迁移。

## 1. 阅读方式与交付边界

这份说明书用于把当前项目完整迁移到另一台电脑，恢复已有开发基线，并让新助手继续开发。按“完整备份 → 环境恢复 → 数字验证 → 工程构建 → 实物复测 → 后续开发”顺序执行，每一步保存证据。

**本次实际交付是说明书及 PLAN.md 文档入口。没有执行项目复制、软件安装、功能回归、综合、下载或硬件测量。** 下文的命令是迁移时执行的步骤，不是已经运行成功的记录。

新电脑先阅读 [AGENTS.md](../AGENTS.md)、[PLAN.md](../PLAN.md)、[README.md](../README.md)，再读本说明书。本文中的相对路径均相对于仓库根目录，正文链接相对于本文件。

### 信息分类

| 分类 | 含义与来源 |
|---|---|
| 官方要求 | 本地高云选题指南与正式补充通知；条目及来源见 PLAN.md 的 R1—R7 |
| 用户确认 | 最新13键、四复音、双旋钮方案；现有 demo 基本发声反馈 |
| 项目建议 | 同版本恢复、完整目录备份、小步开发和交叉检查 |
| 待验证 | 新电脑工具兼容性、实物四声部、DAC外部时序、整机延迟与比赛接口口径 |

有冲突时先查日期与来源。PLAN.md 顶部最新方案优先于旧的压力/触摸开发安排；现有原始报告不改写。

## 2. 项目现状与必须保留的上下文

### 2.1 项目方向

本项目是高云 FPGA 实时多音色合成电子乐器。HDL 是硬件描述语言，RTL 是描述寄存器和数据传输逻辑的源码。音频核心必须由 FPGA 的 HDL 实时生成；Python 只用于波表生成、参考模型和开发验证，不参与最终发声计算。

三名成员均按 FPGA、Verilog 和音频 DSP（数字信号处理）新手推进。A/B/C 是职责分工，不代表姓名或能力。保留学习安排，不要求为了迁移重新开发已经存在的模块。

| 下一版项目目标 | 用户已确认的方案 |
|---|---|
| 演奏输入 | 13个普通按键，C4～C5，音符编号60～72 |
| 复音 | 四个独立声部同时发声 |
| 旋钮 | 整体音量、实时变调各一个 |
| 音色 | 柔和、明亮两种可辨别合成音色 |
| 包络 | 完整 ADSR：起音、衰减、保持、释放 |
| 搭建 | 免焊连接；新增器件及运费低于200元 |
| 本版不做 | 压力、每键力度、电子鼓、延音踏板、屏幕 |

48kHz采样率和16位输出是当前工程起点，不是官方强制规格；名义50MHz系统时钟仍需要实物核对。

### 2.2 已有成果与限制

| 内容 | 已有证据 | 仍需注意 |
|---|---|---|
| A 波表合成 | phase_acc、wave_lut、voice_dds 与 Python 对照记录 | DDS（直接数字合成）已有；完整ADSR和第二音色未实现 |
| B 采样与发送 | sample_tick、i2s_tx、synth_top 与联合测试 | 外部DAC时序没有完整实测验收 |
| C 输入与分配 | 原模块及六项回归记录 | 压力/表情接口保留，但没有接入当前demo |
| ABC demo | 四路DDS、简单渐变包络、混音、板级工程 | 普通模式只有两个演奏键 |
| 历史数字回归 | 2026-09-30记录为14项通过，两份Python参考通过 | 新电脑需重新运行，不能借用旧日志宣称本轮通过 |
| 历史高云构建 | 普通版和自动版均有综合、布局布线及时序报告 | 保留PR1014告警，不能等同外部时序与整机验收 |
| 实物声音 | 用户确认已下载且耳机能听到简单电子音 | 没有独立四声部频谱、整机延迟或稳定性数据 |
| 13键、ADC、双旋钮、完整ADSR、两音色 | 方案已确定 | 尚未实现 |

当前包络只有起音/释放渐变，不能称为完整 ADSR。旧 C 模块存在32声部参数和测试名称，不能据此称整个发声系统已有32复音。

I2S 是常用数字音频串行接口。当前名为 i2s_tx 的模块对 PT8211-S 使用 LSBJ（右对齐）格式，不是 Philips 标准 I2S；正式比赛口径仍待确认。PC控制台具备串口命令界面，不代表当前FPGA已实现对应UART协议（通用异步串行通信协议）。

### 2.3 版本基线

写作开始前的仓库状态：分支 codex/abc-demo；提交 88d36c332b3833094fa4af8e0e9bc4957043bda4；README.md 和 PLAN.md 有用户未提交修改。本次新增说明书并在 PLAN.md 添加入口；实际打包时重新记录完整 Git 状态。

原始ABC验证证据对应提交7921519。后续注释与KEY命名改动会改变源码字节哈希，不能拿现有文件直接套用旧哈希。Git换行转换也会改变字节，迁移完整副本以迁移时清单为准。

## 3. 文件清单、完整备份与恢复

### 3.1 必须保留的资料

| 内容 | 作用 |
|---|---|
| .git、.gitignore | 历史、分支、忽略规则 |
| .vscode | 编辑器配置；保留后按新电脑修正路径 |
| AGENTS.md、PLAN.md、README.md | 协作约定、进度、最新分工 |
| rtl，包含rtl/rom/sine_1024.mem | 合成、输入、输出源码及1024项正弦波表 |
| sim、tb、model、scripts、根目录脚本 | 仿真平台、参考模型、执行入口 |
| fpga_project | 当前集成工程、构建脚本及工程选项 |
| boards | 当前板卡CST引脚约束与SDC时序约束 |
| docs、doc、gowin、根目录旧工程 | 说明、原始PDF、用户资料和历史参考 |
| results | 原始日志、trace、哈希、构建与时序证据 |
| fpga_music_tool | PC辅助软件、依赖清单和协议草案 |

**特别保留 fpga_project/impl/fpga_project_process_config.json。** 它包含活动顶层、ROM搜索路径等工程选项，不能因位于impl目录就丢弃。

工作库、波形、Python缓存及下载文件可以重新生成，但第一次备份完整保留。旧 fpga_project.fs 原样留存供追溯，不继续下载。

### 3.2 旧电脑执行顺序

1. 停止编辑和构建，等待仿真器、高云工具退出；备份期间不继续修改项目。
2. 记录 Git 分支、提交和修改状态，不强制提交用户文件，不更换分支。
3. 将整个 D:\Project\fpga_contest 复制到项目目录外的新备份目录，包含隐藏的.git和.vscode。
4. 为备份创建包含相对路径、文件长度和SHA256的清单。SHA256是文件内容校验值，用于发现传输遗漏或损坏。
5. 使用移动硬盘传输备份及清单；若另行压缩，确认隐藏文件已包含，并单独记录压缩包SHA256。
6. 原电脑保留原目录，直到新电脑迁移验收通过。

以下是可选的完整副本命令，**不要改成带删除语义的 /MIR**。目标必须是新目录；下列路径是旧电脑示例，先确认磁盘空间。

```powershell
$MigrationSource = 'D:\Project\fpga_contest'
$MigrationBackup = 'D:\FPGA_Migration\snapshot-20261002'
if (-not (Test-Path -LiteralPath $MigrationSource -PathType Container)) {
    throw '项目源目录不存在'
}
if (Test-Path -LiteralPath $MigrationBackup) {
    throw '备份目录已存在，请使用新的备份目录'
}
$MigrationSourceFull = [IO.Path]::GetFullPath($MigrationSource).TrimEnd('\')
$MigrationBackupFull = [IO.Path]::GetFullPath($MigrationBackup).TrimEnd('\')
if ($MigrationBackupFull.Equals($MigrationSourceFull, [StringComparison]::OrdinalIgnoreCase) -or
    $MigrationBackupFull.StartsWith($MigrationSourceFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw '备份目标不能位于项目源目录内'
}
robocopy $MigrationSourceFull $MigrationBackupFull /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ
if ($LASTEXITCODE -ge 8) { throw '备份失败，检查robocopy报告' }
```

robocopy返回0～7时仍检查其汇总及后续清单；8及以上表示失败。/XJ不跟随目录联接，若项目有指向外部的联接或链接，先核实外部资料并单独纳入迁移，不擅自遍历其他目录。

可以用PowerShell生成清单，**清单放在备份目录外**：

```powershell
$MigrationManifest = 'D:\FPGA_Migration\manifest-20261002.csv'
if (Test-Path -LiteralPath $MigrationManifest) { throw '清单已存在' }
Get-ChildItem -LiteralPath $MigrationBackupFull -Force -File -Recurse |
    ForEach-Object {
        [pscustomobject]@{
            RelativePath = $_.FullName.Substring($MigrationBackupFull.Length + 1)
            Length = $_.Length
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    } | Export-Csv -LiteralPath $MigrationManifest -NoTypeInformation -Encoding UTF8
```

清单证明备份到新电脑的传输完整性；还需对照源目录检查备份是否有遗漏。对源码、未提交文档、ROM、工程配置、约束和原始资料重点逐项核对。

### 3.3 新电脑恢复

默认恢复至 D:\Project\fpga_contest；没有D盘时使用 C:\Project\fpga_contest。不覆盖已有项目目录，内部结构必须保持。

先逐项核验清单，再执行git命令和打开工程，因为工具可能改变.git内部状态或缓存。若使用压缩包，先核验包哈希，再解压、核验文件清单。清单发现缺文件或哈希不符时停止验证，重新复制相应资料，不用修改源码去掩盖传输问题。

在新电脑项目根目录执行：

```powershell
git status --short --branch
git rev-parse HEAD
git diff --stat
```

分支和提交应与打包记录一致；用户原有未提交修改、新说明书和文档入口应保留。不执行git reset --hard、git clean或重新git init。需要远程协作时使用现有远程配置与个人账户，不自动推送或公开仓库。

## 4. 软件恢复与 DeepSeek Harness 配置

### 4.1 工具与路径

| 工具 | 旧电脑核对情况 | 新电脑处理 |
|---|---|---|
| Git | 仓库已存在 | 安装后核验版本与项目状态 |
| ModelSim | SE-64 10.6e；C:\Library\modelsim\win64 | 优先同版本，确认合法许可及vlib/vlog/vsim可用 |
| Gowin EDA | 工程记录使用1.9.12.04；D:\Gowin\Gowin_V1.9.12.04_x64 | 优先同版本，确认GW5AT-60B器件支持 |
| Python | python命令报告3.14.5；旧D:\python路径已失效 | 使用真实解释器并记录版本、路径 |
| PowerShell | 7.6.5 | 优先同版本，确认脚本能运行 |
| VS Code | 编辑器与旧任务配置已存在 | 编辑器可用后修正旧路径和任务 |
| Programmer与驱动 | 目标电脑尚未检测 | 核对官方驱动、板卡识别和下载连接 |

重新安装软件、配置许可和驱动；仅复制工具目录不作为安装完成的证据。软件安装、账户登录和许可配置由用户执行，不修改许可文件或调试器固件。

```powershell
Get-Command git,python,py,vsim,gw_sh,code -ErrorAction SilentlyContinue |
    Select-Object Name,Source
git --version
python --version
py -0p
$PSVersionTable.PSVersion
```

旧电脑PATH中的vsim来自另一套ModelSim，不应照搬。对选定目录再运行vsim.exe -version，检查vlib.exe、vlog.exe也存在。高云版本通过IDE的About界面核实；不要只凭安装目录名称确认。

核心两份Python参考只使用标准库，不需要先安装GUI依赖。PC控制台可放入单独虚拟环境，依赖见其requirements.txt；MIDI为可选项，不阻塞FPGA迁移。

### 4.2 Harness安装与模型

主方案：从[DeepSeek Harness官方页面](https://deepseek.com/harness/)获取Windows桌面端，按安装向导安装并记录版本。迁移验收期间保持版本稳定。不要默认改用第三方桌面封装。

备用方案：安装Node.js后，按[官方仓库](https://github.com/deepseek-ai/deepseek-harness)执行：

```powershell
npx @deepseek-ai/dsh web
```

备用方案默认启动本机Web界面。只在桌面方案无法使用时选择备用方案；不需要为了FPGA项目构建Harness源码。

按[官方使用指南](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/index.md)在Settings → Models配置内置DeepSeek提供方，再添加并选中项目目录。模型使用已配置可用的DeepSeek条目，记录实际名称，不硬编码未来可能失效的模型名。

API Key在Harness用户配置中保存，不写入项目或说明书，不拷贝他人的账户令牌。内置提供方配置依据[官方模型说明](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/providers.md)。

首次会话先授权读取项目并运行只读检查；确认正确工作区后再授权项目内开发与构建结果输出。工具执行错误属于环境问题，模型能聊天不代表它已能读取文件或运行仿真。

### 4.3 上下文恢复

Codex聊天记录、全局技能、插件和账户不会自动迁移进Harness。以仓库资料和第8节提示词为接手入口。

首次要求助手报告：绝对工作区、Git状态、最新方案、已有成果、缺失工具、活动工程及主回归入口。未完成这些核对前不修改RTL或扩大需求。

可建议接手助手使用与其环境兼容的技能：FPGA/Verilog开发、系统化调试、文档编写。技能并非必须依赖；无法使用时直接遵守AGENTS.md。若希望迁移本机技能，另行核对路径、来源、许可证与外部脚本依赖，不整体拷贝Codex用户配置。

## 5. 数字回归与工程重新构建

### 5.1 正确入口

当前活动工程为 fpga_project/fpga_project.gprj。不是根目录旧C交互工程，也不是旧单音工程。

| 工程项目 | 当前设置 |
|---|---|
| 器件 | GW5AT-60B；GW5AT-LV60PG484AC1/I0；Device Version B |
| 普通版 | instrument_demo_top；instrument_demo.fs |
| 自动版 | instrument_demo_auto_top；instrument_demo_auto.fs |
| ROM搜索 | Include Path为..，保留rtl/rom/sine_1024.mem |
| 约束 | boards/tang_mega_60k_31004/demo.cst和demo.sdc |
| 系统 | 名义50MHz；目标48kHz；16位有符号输出 |

### 5.2 先正式回归，再Python对照

从项目根目录执行，下列路径是旧电脑示例，必须换成新电脑检测确认的值：

```powershell
$MigrationModelSimBin = 'C:\Library\modelsim\win64'
& (Join-Path $MigrationModelSimBin 'vsim.exe') -version
.\sim\run_tests.ps1 -Suite All -ModelSimBin $MigrationModelSimBin
```

预期最后出现 PASS: suite All (14 testbenches). 每项均须出现对应PASS标记，不仅检查退出码。脚本会检查错误与失败标记。测试覆盖模块、联合数据、边界、复位、释放与事件分配；具体契约见[demo说明](abc-demo.md)。

第一次执行使用新电脑新建的工作库。若完整副本含旧results/regression_work，先将其保留并改名为历史缓存，再运行；不要把旧库当作新编译证据。原results/abc-demo-20260930保持不动。

仿真通过且生成本轮trace后执行：

```powershell
python model/check_dds.py
python model/check_abc_demo.py
```

若python是不能启动的别名，使用检测确认的解释器绝对路径。不得使用python -O执行检查，因为ABC参考包含assert断言。

预期DDS核对1024波表项、4810样本及复位记录；ABC核对128音符步长、745混音样本和2次复位。缺trace时先修复仿真，不把旧trace复制成新结果。

### 5.3 负向检错对照

```powershell
.\sim\run_tests.ps1 -Suite AB -ModelSimBin $MigrationModelSimBin -NegativeControl
```

此命令预期因故意翻转串行观察位而失败，被脚本拒绝是正确结果。环境缺失或编译失败不算成功检错，必须确认失败来自预期的串行样本不匹配。负向库与日志独立，不放宽正式判据。

### 5.4 两种demo顺序构建

先在Gowin GUI打开工程，核对器件、顶层、ROM搜索及约束。之后可在项目根目录执行：

```powershell
$MigrationGowinShell = 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe'
if (-not (Test-Path -LiteralPath $MigrationGowinShell)) { throw '高云路径未确认' }
Push-Location .\fpga_project
try {
    & $MigrationGowinShell build_demo.tcl
    if ($LASTEXITCODE -ne 0) { throw '普通版构建失败' }
    & $MigrationGowinShell build_auto_demo.tcl
    if ($LASTEXITCODE -ne 0) { throw '自动版构建失败' }
}
finally { Pop-Location }
```

路径仍需替换成新电脑实际安装位置。两版共享工程与输出目录，不能同时运行。自动构建可能使工程配置显示自动顶层，后续GUI普通版操作须重新核对顶层与输出名。

旧impl/gwsynthesis、impl/pnr、impl/temp产物保留为历史备份；首轮验证使用重新生成的结果，并检查文件时间、内容及报告中的顶层，防止误用旧.fs。仅退出码为0不够。

必须核对两版新报告：生成文件存在；8个端口有正确物理约束；20ns主时钟有效；setup/hold无违例；约束覆盖及新增警告已检查；四个声部ROM存在。保留PR1014时钟路由告警并说明影响。输出布线预算不等于外部DAC建立/保持时序验收。

资源、Fmax与哈希可以因版本、机器、换行或构建变化而不同。不用字节一致替代功能验收，不把工具内部Fmax写成板卡实测性能。

### 5.5 本轮证据保存

在results下建立新的migration-日期-运行编号目录，避免覆盖。保存工具版本、Git状态、源码/ROM/约束哈希、14项日志、两份trace与Python输出、负向检错日志、新综合/布局布线/时序报告，以及新.fs哈希。

正式回归先完成并归档，再执行负向对照。当前脚本输出到results/logs和results/waves；迁移时将本轮证据复制到新记录目录。大体积下载文件可放在仓库外的迁移备份，不自动提交。

## 6. 板卡、下载与实物复测

以现有NEO Dock 31004为前提；接手时再次核对实物版本。当前8个端口约束来自现有工程，不包含13键或ADC新增接线。

| 信号 | 引脚 | 当前用途/电平 |
|---|---|---|
| sys_clk | V22 | 名义50MHz，3.3V |
| sys_rst_n | AA13 | KEY0低有效复位，1.5V |
| Key_in[0] | AB13 | KEY1演奏C4，1.5V |
| Key_in[1] | Y12 | KEY2演奏E4，1.5V |
| HP_BCK | Y17 | DAC位时钟，3.3V |
| HP_WS | AB17 | DAC声道选择，3.3V |
| HP_DIN | AA16 | DAC数据，3.3V |
| PA_EN | AB16 | 功放控制，1关闭/0开启，3.3V |

1. 用户核对供电、公共地、USB数据线、板卡识别及音频输出接法。
2. 使用本轮instrument_demo.fs，在Programmer选择匹配器件的SRAM Program。
3. KEY0复位后应静音；低音量测试KEY1、KEY2及同时按下，松键应渐出。
4. 普通版正常后，用本轮instrument_demo_auto.fs测试KEY0复位后播放一次约1秒，再静音。
5. 保存下载日志、板卡版本、源码及.fs哈希、操作与实际声音反馈。

SRAM配置断电丢失属于正常现象。本次不要求刷Flash、不改调试器固件。耳机先低音量试听；桥接扬声器J27/J28不能直接连接接地示波器地夹。模拟测量先核实负载和安全接法。

自动版使用原测试音符36/37/38/39，不能用是否悦耳判断失败。听到声音也不能替代四路独立可闻声部频谱、实际采样率或整机延迟测量。失败时先检查时钟、复位、功放及串行数据，不先提高增益。

## 7. 路径问题、排障与回退

| 现象 | 优先检查与处理 |
|---|---|
| 克隆后缺最新方案 | 克隆不含未提交修改，恢复完整备份中的文件 |
| VS Code默认任务找不到DDS | 根脚本引用不存在的旧DDS；切换到sim/run_tests.ps1，不创建假文件凑任务 |
| 文件树顶层不存在 | .vscode/config.json仍指向旧bcd_counter.v，指向活动顶层或停用旧配置 |
| 单文件检查报红 | 修正ModelSim路径，以统一完整编译/仿真结果判断 |
| 保存产生大量源码差异 | 核对formatOnSave；迁移期间关闭自动格式化，保留用户排版 |
| 找不到ROM | 仓库结构、Include Path和rtl/rom/sine_1024.mem齐全 |
| Python找不到trace | 先运行成功的All回归，核对本轮输出位置 |
| ModelSim无法启动 | 检查明确路径、版本、合法许可，不修改授权文件 |
| Gowin器件不匹配 | 检查软件器件支持、版本及.gprj器件字段，不擅自换型号 |
| GUI控制台不能启动 | run_fpga_tool.bat里的D:\python\pythonw.exe过期，改成确认的解释器；核心迁移不受此阻塞 |
| 串口连接后命令无效 | 当前RTL未证明有控制台UART协议，不能以COM口打开判断功能已实现 |
| Harness只回复不执行 | 确认工作区、文件/终端能力和权限；先用只读操作验证 |
| 新报告与旧哈希不同 | 核对源版本、注释、换行和工具；保留差异，不重写旧报告 |

环境适配阶段不修改RTL端口、采样契约或测试判据。一次改变一个主要因素，保留失败日志。工具版本改变时单独记录并重新完整回归；无法复现就标记阻塞，不宣称迁移完成。

回退使用原电脑原目录或独立备份。新电脑失败工作副本仍保留，不覆盖唯一备份，不删除用户资料。硬件版本不同或新增引脚不明时停在仿真/构建阶段，先取得正确资料。

## 8. DeepSeek首次接手提示词与协作规则

在Harness选择项目工作区后粘贴：

```text
请接手当前工作区中的高云FPGA实时多音色电子乐器项目。
先阅读AGENTS.md、PLAN.md顶部最新方案、README.md及
docs/migration-deepseek-harness.md，再核对实际文件与Git状态。

下一版为13个普通按键（音符60～72）、四复音、整体音量和实时变调
两个旋钮、柔和/明亮两音色、完整ADSR，免焊搭建，新增器件及运费
低于200元。不做压力、每键力度、电子鼓、延音踏板或屏幕。

已有两键和自动四声部demo、历史数字验证及高云报告；
用户确认已有基本实物发声。13键、ADC、完整ADSR和第二音色未实现。

首任务是恢复和验证现有基线。先报告绝对工作区、Git状态、当前目标、
工具路径/版本、活动工程和主回归入口，不修改RTL。
核对后运行sim/run_tests.ps1的All回归，生成本轮trace，
运行两份Python参考，再顺序构建普通版和自动版。
负向AB对照必须因预期串行不匹配被拒绝，不能把环境失败算成检错成功。

保留未提交修改和原始资料。不放宽测试，不使用旧日志或下载文件
声称本轮通过。区分历史报告、用户反馈、本轮结果和待验证事项。
当前i2s_tx对PT8211-S使用LSBJ；PC控制台界面不是FPGA协议实现证据。
不自动采购、对外发送、上传作品、公开仓库或操作连接不明的硬件。

使用中文，三人均按新手教学。每次一个小任务，说明目的、输入输出、
前置知识、步骤、预期现象、验证方法和常见错误。
完成后报告改动、实际检查和待验证项，据实更新PLAN.md。
```

每次新会话重新检查最新文件，不用本说明书的旧状态覆盖后来的进度。每次任务结束形成简短记录：目标、修改文件、运行命令、结果路径、未验证项、最小下一步。按“代码已写/仿真/综合/布局布线及时序/实物”分别标记。

## 9. 迁移后项目开发安排

先通过第10节的迁移检查，再启动功能开发。每步约30～90分钟的小实验仅作学习建议，不是交付时间承诺。

| 顺序 | 主责与工作 | 验证与交付 |
|---|---|---|
| 1 | A：单声部完整ADSR | 起音、衰减、保持、释放；提前松键；重触发；复位；Python逐样本参考 |
| 2 | A/C：四声部包络与释放反馈 | 独立状态，真实release_done，尾音不被提前当空闲 |
| 3 | C：13键事件及分配 | 60～72映射、抖动、四键、第五键抢占、被抢占旧键松开 |
| 4 | C/B：ADS1115双旋钮 | I2C读写（双线控制总线）、初始化、轮询、数值映射、失效检测 |
| 5 | A：音量/变调与两音色 | 参数平滑、有限谐波/波表依据、位宽及饱和、音色切换 |
| 6 | B与全组：完整集成 | 新接线表、顶层、CST/SDC、联合回归、构建与实物测量 |

器件方案及采购边界详见README。预计新增13路按键输入与2路I2C信号；新接线先核对31004原理图和模块资料。ADS1115只采集慢变化旋钮，不承担音频采样。模块供电和I2C上拉不得误接5V，PMOD与复用排针不能重复计数。

A输入各声部控制与音量/变调，输出16位有符号混音样本及有效信号；B负责请求、缓存、串行输出、复位/静音与系统约束；C负责事件、声部分配、ADC及故障状态。各人负责本模块说明与测试，三人都逐步掌握构建和下载。

下一版实现前，接口两端共同确认字段位宽、符号、单位、握手、有效时刻和延迟，写入接口说明及测试。持续高电平不能单独表示重触发；变调不改变松键匹配用原始音符；空闲、释放中、最老活动声部按顺序分配；旧键松开不能关闭抢占后的新音。

沿用单50MHz系统时钟与采样使能；I2C时钟只作外部信号，不另建内部逻辑时钟域。混音显式扩位、缩放/舍入与饱和，避免隐式截断。ADC初始化失败、持续通信失败或数据长期失效时静音，恢复后先松键再演奏。

README给出的初始ADSR目标为起音2ms、衰减500ms、保持约峰值10%、释放120ms；松键从当前值释放。下一版KEY0复位、KEY1切换音色、KEY2预留；当前demo仍是KEY1=C4、KEY2=E4。音色切换只影响新触发声部，旧尾音保留原音色。

首次开发任务建议单声部ADSR，先观察正常按下/松开，再改变一个参数，再覆盖提前松键。迁移阶段不一并加入32复音、复杂效果器、网络服务或电脑播放器。

最终延迟验收需记录真实输入、采集/滤波、包络与输出条件，明确起止点和阈值，保留同步测量。内部请求到混音有效仅几个周期不能替代整机≤10ms要求。演奏维度认定、PT8211-S接口口径继续列待确认，不擅自宣称R1—R7全部通过。

## 10. 完成标准与记录模板

- [ ] 完整备份、关键源文件及传输清单核验通过。
- [ ] Git历史、分支和全部未提交修改保留。
- [ ] ROM、工程配置、约束、原始PDF与用户资料齐全。
- [ ] 工具路径、版本、许可及执行能力核对完成。
- [ ] Harness能读取正确工作区并说明项目现状。
- [ ] 14项正式回归通过；两份Python核对通过。
- [ ] 负向对照因预期串行不匹配被拒绝。
- [ ] 两种demo重新构建，约束覆盖、时序和告警核对完成。
- [ ] 本轮普通版、自动版下载及既有演示流程复测完成。
- [ ] 新证据独立保存，旧报告未覆盖。
- [ ] PLAN.md仅根据实际证据更新，不勾选未经验证的比赛验收项。

检查全部通过后可记录“迁移完成、现有开发基线恢复”。13键新版本、完整ADSR、两音色、独立可闻四声部、DAC外部时序、整机延迟仍分别验收。

每次运行记录至少包含：日期及机器；项目绝对路径；Git提交/分支和未提交修改；工具路径/版本；源码/ROM/约束哈希；命令及退出状态；正式PASS/FAIL与负向对照说明；证据目录；下载文件哈希及板卡版本；实际现象；未验证事项；下一步。

## 11. 资料入口与本次实际检查

- [项目计划与赛题来源](../PLAN.md)、[协作规范](../AGENTS.md)、[最新器件与分工](../README.md)。
- [ABC demo接口、数值契约和上板说明](abc-demo.md)、[高云工程复现说明](../fpga_project/README.md)。
- [历史数字验证证据](../results/abc-demo-20260930/README.md)、[A验证记录](a-dds-validation.md)、[原C交互说明](c-interaction.md)。
- DeepSeek安装、配置与工作区使用的官方来源见第4节；资料核对日期为2026-10-02，后续执行核对所安装版本的说明。

本次实际检查为仓库状态、现有文档、测试脚本参数、模型输入、工程配置及约束；生成后检查本说明书UTF-8、内部文件链接与文档变更范围。未执行本轮功能仿真、Python算法回归、综合、布局布线、下载或实物测量。
