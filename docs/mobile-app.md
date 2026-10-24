# 手机 App 已迁出

2026-10-19按用户确认，手机蓝牙App已独立迁至 `D:\Project\jingzou_harmony`，FPGA仓库仍在原位置。

- [手机工程与构建说明](../../jingzou_harmony/README.md)
- [完整手机端设计与使用说明](../../jingzou_harmony/docs/mobile-app.md)

最新0.1.1通过原生ArkTS构建、25项独立检查及签名核验，已通过命令行更新安装并启动。初次部署的Profile/手机授权、进程及FOREGROUND证据在独立工程`build/install/summary.json`；0.1.1修复无过滤BLE扫描参数后，用户确认能扫描或显示设备、401消失，证据在`build/ble-fix/summary.json`。完整GATT连接和FPGA实物联调仍待验收。原位于本仓库`host/harmony/`的源码与手机预览图已迁出，继续开发只改独立工程。

命令行流程已整理为个人技能：[harmony-hap-deploy](C:/Users/YUAN/.codex/skills/harmony-hap-deploy/SKILL.md)。

2026-10-23板卡侧新增独立BLE UART与来源隔离，接线和默认9600波特率见[当前接线表](keyboard-wiring.md#蓝牙接线新增独立串口需使用本轮固件)。已有App的HELLO／NOTE_ON／NOTE_OFF／PANIC／STATUS?报文可复用；App不需要改成音频播放器。服务FFE0/特征FFE1只是目前预设，须实物发现确认；手机连接时必须看到FPGA握手才算协议通，不能以“扫描到HC-08”代替。本文不宣称本轮已真机联调，也没有修改独立手机工程。
