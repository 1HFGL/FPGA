# 中文显示与7寸HDMI接口

正式屏幕为用户提供的 **CLB7INH，7寸1024×600，Rev2.0**，接口HD IN、POWER/DC5V、CTOUCH、Backlight CTR。HDMI输出接HD IN，POWER独立5V供电；USB触摸与背光控制本轮未接。屏幕不承载声音，音频走板载DAC。

## 静奏双模式

主布局为深色中文界面：48像素标题、三块参数卡、大波形/真实电平、下方乐器主体。钢琴用冷青色和8白键/5黑键，吉他用暖琥珀色和六弦0～12品。吉他按标准调弦E4、B3、G3、D3、A2、E2从上到下排列，同音可用位置全部高亮，注明“指位示意”。

![钢琴实际RTL帧](display-piano.png)

![吉他实际RTL帧](display-guitar.png)

画面读取已接受的音色选择和分音色持键状态。模式、标题、配色和高亮在同一个帧边界切换；松键尾音不继续高亮，被抢占的旧音也不再标为按住。当前固定中音区/延音关，没有伪装成可操作的触摸菜单。

## 输入与流水线合同

`instrument_display`的系统输入同步于50MHz：`key_down[12:0]`是当前音区13音窗口的并集（低MIDI48～60、中60～72、高72～84），与音区同拍寄存，新增`piano_keys/guitar_keys[12:0]`分别表示两音色已分配且仍持有的音符；`instrument_guitar`为实际选择状态。音量0～127，弯音有符号显示码−32768～32767对应−2～+2半音，音区/延音为状态字段。`audio_valid/audio_sample`提供最终混音后的16位补码副本。

状态通过66位完整字信箱跨到49MHz像素域，并在帧最后一个消隐像素锁存。音频使用独立16位信箱；信箱忙时`display_sample_drop`仅诊断副本丢失，任何显示等待都不能反馈音频。信箱两端共同复位，各域两拍同步释放；像素停钟/失锁测试不能替代模拟亚稳态可靠性或板外信号验证。

P0锁存坐标并读波形RAM，P1读取同步字库并锁存背景，P2按覆盖度混合并统一输出RGB888、DE、HS、VS和frame_start。DE为0时输出黑色。新增画面没有增加像素流水级或音频等待。

新界面的像素路径全部是常数比较与固定移位：字距用三次阈值比较选槽位，不出现 `/26`、`/52` 通用除法；数字用24px等宽字距，中文用26px字距；弯音小数点、正负号、去饱和星号等符号用几何线段绘制，不占字库槽。

正式入口启用`WIDE=1, ENHANCED=1`。通用800×480入口仍由同一显示总模块的参数配置支持，`ENHANCED=0`保留基础接口测试；它不属于当前屏幕的下载入口。

## 波形与电平

`display_wave_envelope`收集512个连续收到的16位样本，每两个保留最小/最大值，形成256列；绘图区768×136像素，每列3像素。48kHz下覆盖约10.67ms；双页共2KiB，没有整屏帧缓存。

每页完成后冻结，帧边界交换读页并锁定该页峰值/显示倍率。取可使峰值不超过满幅75%的最大2次幂倍率，限制×1～×256；响音立即降倍率，弱音连续8页后每次提高一档，静音保持倍率并画平线。16位负满幅的绝对值32768正确保留，放大后显式饱和，不允许溢出翻转。倍率只改变图像，右侧电平条使用未经显示放大的原始数字峰值；红色表示接近满幅，不宣称检测到了模拟削波。

等待换页期间丢弃显示样本；没有零交越锁相，波形可以横向移动。极弱音达到256倍上限后仍可能很小。输入采样完全停止时保持最后一页，下一完整页为零时显示静音。此图是演奏反馈，不替代测量示波器。

## HDMI时钟、复位和约束

`piano_hdmi_top`使用50MHz系统钟、49MHz像素钟、245MHz串行钟。当前CVT候选：水平1024+40+104+144=1312，垂直600+3+7+14=624，刷新约59.851Hz，HS低有效、VS高有效。用户先前照片已显示画面；本轮新位流尚需实屏确认。

HDMI仅发DVI兼容视频。PLL、TMDS编码和OSER10串行器使用现有Gowin原语，不随本轮界面改造改变复位结构。保留像素下降沿两级释放、每路I/O附近的FF/LUT物理位置约束，以及原SDC/例外和process配置。12个实际落点与五类时序需在本轮构建报告中核对。

`projects/hdmi/build.tcl`将公共piano和HDMI约束合并到build/hdmi；不要手改生成约束。板外HDMI预算、PR1014和其他未闭合项见[验证说明](verification.md)，不能仅凭位流生成宣称全面签核。

## 重现和验收

```powershell
python verification/scripts/run_final_tests.py tb_final_wave_envelope tb_final_display_frame tb_final_display_ui tb_final_hdmi_isolation
python verification/scripts/run_final_tests.py tb_final_wave_envelope --mutation Wave
./verification/scripts/run_hdmi_reset_tests.ps1
./projects/hdmi/build.ps1
python verification/scripts/render_display_frame.py build/regression/final/piano_ui_frame.hex docs/display-piano.png --width 1024 --height 600
python verification/scripts/render_display_frame.py build/regression/final/guitar_ui_frame.hex docs/display-guitar.png --width 1024 --height 600
```

完整帧测试用正式模态合成输出，检查原生CVT时序、标题字形、帧中模式变化、真实波形可见高度、吉他音位以及钢琴旧音隔离。有屏/无屏测试在16声部下逐拍比较UART/音频引脚，覆盖HPD、PLL失锁、像素停钟、旋钮故障与复位。恢复后串行位序由独立17次恢复测试核对。队友原测试保持不变。

## 2bit覆盖度字模与界面参数

正文与标题不再是1bit点阵整数放大。`verification/scripts/generate_ui_fonts.py` 离线把 Noto Sans SC（标题可保留 Medium 字重）按 4 倍超采样渲染，再按面积量化成 2bit 覆盖度：0为背景，1约5/8、2约7/8、3与文字色完全相同。像素端只做“右移+加减”的线性混合，不引入乘法器或除法器。

- 正文层：58个24×24字形（1个空白+57个字），每行48bit，单端口ROM 2048×48；
- 标题层：7个48×48字形，每行96bit，ROM 512×96；
- 两层ROM声明容量合计147456bit（18KiB），物理BSRAM占用还取决于宽深分块；当前完整带屏工程为94/118块，以实现报告为准。生成结果直接写`rtl/display/display_font_ui.v`，FPGA只读片内固定点阵，不读系统字体文件。

`instrument_display` 新增 `UI` 参数：`UI=1` 使用新的 1024×600 排版绘制器（`instrument_panel_ui.v`）与覆盖度字模；`UI=0` 保留原逐像素兼容绘制器与24×24 1bit字库，供旧帧测试继续使用。正式 HDMI 入口为 `ENHANCED=1, UI=1`，输出流水级数、DE/HS/VS 延迟与改造前一致。

字库来源、字体SHA256与OFL许可见[字体说明](display-font/README.md)。

后续USB触摸仍需实际控制器、USB主机/报告解析、来源与坐标合同；显示模块本身不产生音符事件。

## 三音区显示补充（2026-10-17）

KEY1选择的实际音区经原66位状态信箱送入帧状态，不增加音频等待。钢琴白键名随档位显示C3…C4、C4…C5、C5…C6；两个绘制器共用相同音高规则。吉他低/中档显示0～12品，高档滚动到12～24品，左侧E4/B3/G3/D3/A2/E2为标准空弦名。高档不画0品琴枕。旧音超出新窗口仍发声，但不错误映射为新窗口琴键；已有音色分离规则保持不变。
