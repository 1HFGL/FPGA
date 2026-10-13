# 音色设计台与电脑演奏

当前唯一入口是 `run_tone_studio.bat`；旧综合控制台已删除，历史在Git提交 `f513622`。`studio.py` 负责交互，`studio_ui.py` 绘制界面，`studio_transport.py` 串口/模拟设备，`studio_model.py` 保存配置并生成单周期波表。

## 启动

双击 `host/run_tone_studio.bat`，或从仓库根执行：

```powershell
& '.venv-studio/Scripts/python.exe' host/studio.py
```

首次使用其他电脑按 `setup_studio.ps1` 建立虚拟环境，依赖见 `studio_requirements.txt`。模拟设备不发声，只用于交互测试。

连接实际COM口，115200/8N1，收到 `TONE=FIXED_PIANO` 握手后可弹琴、查看状态和全部松键。固定固件无CONFIG能力，应用按钮禁用；修改滑条或载入JSON不会改变板上音色。不要同时用串口终端占用该COM口。

界面可编辑16谐波与包络草稿、保存/读取JSON、导出1024点16位单周期波表；这是开发工具，不是电脑替代FPGA发声。`tone_examples/piano.json` 是当前固件波表生成依据，不是录音PCM。运行时调参、混响及颤音未接入当前FPGA。

## 验证与协议

```powershell
& '.venv-studio/Scripts/python.exe' -m unittest discover -s host -p 'test_*.py' -v
```

协议定义见 [STUDIO_PROTOCOL.md](STUDIO_PROTOCOL.md)，其中CONFIG章节仅为PC/模拟设备能力。实体按键与PC共享四声部；PANIC只清理PC来源，固件包含3秒失联回收。实际串口/音质仍需上板验证，不能用模拟设备状态作为比赛证据。
