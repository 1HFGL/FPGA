# 第三方材料与许可

静奏团队原创源码、约束、参考模型、构建脚本、验证代码和桌面上位机源码使用 [GNU GPL v3.0（GPL-3.0-only）](LICENSE)。完整 FPGA 工程集成 USB 模块，按 GPL v3.0 的条件分发。下列第三方文件保留各自的版权和许可声明。

| 材料 | 来源和许可 |
| --- | --- |
| `rtl/usb/vendor/usbh_sie.v`、`usbh_crc16.v`、`usbh_crc5.v` | [Ultra-Embedded `core_usb_host`](https://github.com/ultraembedded/core_usb_host/tree/81eb9f131dbb434a9047ae074fea5c31ef46ce5d)，[GPL-2.0-or-later](rtl/usb/vendor/COPYING.GPL-2.0)。`usbh_sie.v` 的本地改动见源码标注及[来源清单](rtl/usb/vendor/SOURCES.json)。 |
| `rtl/usb/vendor/usb_fs_phy.v` | 取自 [`nand2mario/usb_host_example`](https://github.com/nand2mario/usb_host_example/tree/4e4eee36b45b5260ef463167750eb087fb9b2b38)。沿用文件中的 Ultra-Embedded [LGPL-2.1-or-later](rtl/usb/vendor/COPYING.LGPL-2.1) 和 Dinesh Annayya [Apache-2.0](rtl/usb/vendor/LICENSE.Apache-2.0) 声明。 |
| 界面字模与对应测试数据 | `display_font24.v`、`display_font_ui.v` 及其字模参考数据源于 Noto Sans SC 和 Red Hat Mono。见[字体来源](docs/display-font/README.md)及 [SIL OFL 1.1](docs/display-font/OFL.txt)。 |
| Windows 上位机依赖 | PySide6 / Qt 与 pyserial 各自的许可及来源见[发行依赖说明](host/distribution/licenses/SOURCES.txt)。 |
| 钢琴参考素材 | [录音来源清单](model/piano_reference_sources.json)记录 University of Iowa Electronic Music Studios 的参考音源。仓库提供拟合参数及生成脚本，原始录音由音源项目提供。 |

`docs/sources/` 的赛事及参考资料和 `upstream/` 中保留的独立历史工程，其材料按各自来源的授权使用。板卡工具链及芯片原语库由厂商提供。
