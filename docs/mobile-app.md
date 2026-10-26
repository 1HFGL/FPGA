## 2026-10-25 手机端0.3.0（未安装）

新增板端曲谱上传、13个实体键映射编辑、实际状态回读，以及音色/音区/延音/导奏控制。手机保存键位草稿；下发后由FPGA RAM保留，断电复位后须重新下发。下载曲用于固定节拍屏幕导奏，不自动发声；原手机实时自动演奏仍保留。旧固件无GUIDE/KEYMAP能力时禁止新操作。

41项独立检查、严格类型/静态检查、原生ArkTS构建及签名核验通过。包：`D:/Project/jingzou_harmony/build/packaging/dist/jingzou-0.3.0-debug.hap`，SHA256 `30be0081de6ad49deab9e8723690a47b133675e6b3c8471c0901a6866c04e149`。证据：`D:/Project/jingzou_harmony/build/verification/summary.json`与`D:/Project/jingzou_harmony/build/packaging/summary.json`。尚未安装、未真机BLE联调、未验收实际折叠屏显示；FPGA功能已合并并完成离线实现，位流身份见verification/evidence/timing_targets/summary.json；手机与实物BLE联调仍待验收。下面旧0.2.0已安装记录仅为历史。


# 手机 App 已迁出

2026-10-19按用户确认，手机蓝牙App已独立迁至 `D:\Project\jingzou_harmony`，FPGA仓库仍在原位置。

- [手机工程与构建说明](../../jingzou_harmony/README.md)
- [完整手机端设计与使用说明](../../jingzou_harmony/docs/mobile-app.md)

最新0.1.1通过原生ArkTS构建、25项独立检查及签名核验，已通过命令行更新安装并启动。初次部署的Profile/手机授权、进程及FOREGROUND证据在独立工程`build/install/summary.json`；0.1.1修复无过滤BLE扫描参数后，用户确认能扫描或显示设备、401消失，证据在`build/ble-fix/summary.json`。完整GATT连接和FPGA实物联调仍待验收。原位于本仓库`host/harmony/`的源码与手机预览图已迁出，继续开发只改独立工程。

命令行流程已整理为个人技能：[harmony-hap-deploy](C:/Users/YUAN/.codex/skills/harmony-hap-deploy/SKILL.md)。

2026-10-23板卡侧新增独立BLE UART与来源隔离，接线和默认9600波特率见[当前接线表](keyboard-wiring.md#蓝牙接线新增独立串口需使用本轮固件)。已有App的HELLO／NOTE_ON／NOTE_OFF／PANIC／STATUS?报文可复用；App不需要改成音频播放器。服务FFE0/特征FFE1只是目前预设，须实物发现确认；手机连接时必须看到FPGA握手才算协议通，不能以“扫描到HC-08”代替。本文不宣称本轮已真机联调，也没有修改独立手机工程。
