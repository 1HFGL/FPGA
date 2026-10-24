// 7寸1024x600 HDMI屏候选板级顶层；复用唯一钢琴内核，无CPU/DDR/帧缓存。
// 手册hdmi_cvt 1024 600 60 6 0 0 0推导普通CVT，具体驱动板仍须实屏验证。
// HDMI只发DVI兼容视频；音频仍接板载DAC。USB为1A86:E5E3专用触摸主机。
module piano_hdmi_top #(
    parameter ROM_FILE="../../rtl/rom/piano_1024.mem",
    parameter integer VOICES=32,
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer DISPLAY_LOCK_CYCLES=100000,
    parameter integer ENABLE_BRIGHTNESS=0,
    parameter integer ENABLE_TOUCH_BRIGHTNESS=1,
    parameter integer ENABLE_OCTAVE_KEY=1,
    parameter integer BRIGHTNESS_REPEAT_CYCLES=25000000,
    parameter integer ENABLE_REVERB=1,
    parameter integer ENABLE_CHORUS=1,
    parameter integer ENABLE_DELAY=1,
    parameter integer USE_MODAL=1,
    parameter integer UART_CLKS_PER_BIT=434,
    parameter integer ENABLE_SLIDER_BRIGHTNESS=1,
    parameter integer ENABLE_BLE=1,
    parameter integer BLE_CLKS_PER_BIT=5208,
    parameter integer ENABLE_GUIDE=0,
    parameter integer ENABLE_USB_TOUCH=1
)(
    input wire sys_clk,sys_rst_n,
    input wire [1:0] Key_in,
    input wire [12:0] piano_key_n,
    input wire uart_rx,hdmi_hpd,
    output wire uart_tx,HP_BCK,HP_WS,HP_DIN,PA_EN,
    inout wire knob_sda,
    output wire knob_scl,
    output wire [2:0] tmds_data_p,tmds_data_n,
    output wire tmds_clk_p,tmds_clk_n,
    input wire ble_rx,ble_state,
    output wire ble_tx,
    inout wire usb_touch_dp,usb_touch_dm
);
    wire pixel_clk,serial_clk,pll_locked,display_reset;
    hdmi_clock_60k u_video_clock(.sys_clk(sys_clk),.rst_n(sys_rst_n),
        .pixel_clk(pixel_clk),.serial_clk(serial_clk),.locked(pll_locked));
    hdmi_reset_guard #(.LOCK_CYCLES(DISPLAY_LOCK_CYCLES)) u_guard(.sys_clk(sys_clk),
        .rst_n(sys_rst_n),.pll_locked(pll_locked && hdmi_hpd),.display_rst_n(display_reset));
    wire [12:0] held_keys;
    wire instrument_guitar;
    wire [1:0] current_octave;
    wire core_ready;
    wire touch_event_valid,touch_event_ready,touch_event_on,touch_event_guitar;
    wire [7:0] touch_event_source;
    wire [6:0] touch_event_note,touch_event_velocity;
    wire touch_cancel_valid,touch_cancel_ready,usb_touch_available;
    generate if(ENABLE_USB_TOUCH)begin:g_usb_touch
        touch_usb_system u_usb(.sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.core_ready(core_ready),
            .usb_dp(usb_touch_dp),.usb_dm(usb_touch_dm),.instrument_guitar(instrument_guitar),.octave(current_octave),
            .available(usb_touch_available),.event_valid(touch_event_valid),.event_ready(touch_event_ready),
            .event_on(touch_event_on),.event_guitar(touch_event_guitar),.event_source(touch_event_source),
            .event_note(touch_event_note),.event_velocity(touch_event_velocity),
            .cancel_valid(touch_cancel_valid),.cancel_ready(touch_cancel_ready));
    end else begin:g_no_usb_touch
        assign usb_touch_dp=1'bz;assign usb_touch_dm=1'bz;
        assign usb_touch_available=0;assign touch_event_valid=0;assign touch_event_on=0;
        assign touch_event_guitar=0;assign touch_event_source=0;assign touch_event_note=0;
        assign touch_event_velocity=0;assign touch_cancel_valid=0;
    end endgenerate
    wire guide_note_on,guide_valid;
    wire [6:0] guide_played_note;
    wire [3:0] guide_index,guide_progress;
    generate if(ENABLE_GUIDE)begin:g_guide
        practice_guide u_practice(.clk(sys_clk),.rst_n(core_ready),
            .note_on(guide_note_on),.played_note(guide_played_note),.octave(current_octave),
            .target_valid(guide_valid),.target_index(guide_index),.target_note(),
            .progress(guide_progress),.complete());
    end else begin:g_no_guide
        assign guide_valid=0;assign guide_index=0;assign guide_progress=0;
    end endgenerate
    // Board-side boundary only: replace these constants with a verified USB-host
    // adapter after controller, HID report and wiring are known. HDMI has no touch.
    // Simulations drive this boundary; the present bitstream cannot receive fingers.
    wire touch_connected=1'b0;
    wire touch_report_valid=1'b0;
    wire touch_down=1'b0;
    wire [11:0] touch_x=12'd0,touch_y=12'd0;
    wire [6:0] brightness_target,brightness_current;
    wire [6:0] touch_brightness_target,slider_brightness;
    wire slider_valid,slider_ready;
    // 实体滑条优先；未就绪/ADC故障退回中性值（物理USB仍未实现）。
    // 保留规范化触摸测试边界，不把这条备用接口说成USB已接通。
    assign brightness_target=(ENABLE_SLIDER_BRIGHTNESS && slider_ready) ?
        slider_brightness : touch_brightness_target;
    wire touch_available;
    wire touch_brightness_available;
    assign touch_available=touch_brightness_available || usb_touch_available;
    touch_brightness_control u_touch(.clk(sys_clk),.rst_n(core_ready),
        .connected(touch_connected),.report_valid(touch_report_valid),.contact_down(touch_down),
        .contact_x(touch_x),.contact_y(touch_y),.target(touch_brightness_target),
        .available(touch_brightness_available),.dragging());
    reg [6:0] volume;
    reg signed [15:0] bend;
    wire signed [15:0] audio_sample;
    wire audio_valid,knob_valid,param_ready,param_fault;
    wire [13:0] knob_value_flat;
    wire [12:0] piano_held_keys,guitar_held_keys;
    // 与无屏入口显式使用同一主配置，避免依赖ADC模块未来的默认值。
    ads1115_knob_if #(.I2C_HZ(350000),.CONV_WAIT(75000),.DR(3'b111),
        .READY_SAMPLES(2),.FILTER_SHIFT(0),.SLEW_STEP(127),
        // 15-bit normalized input: 384 codes = 1.5 of the 7-bit display steps.
        // Actual motion crosses the held reference immediately; no extra ADC wait.
        .HYSTERESIS_COUNTS(384),
        .ENABLE_BRIGHTNESS(ENABLE_SLIDER_BRIGHTNESS)) u_adc(
        .clk(sys_clk),.rst_n(core_ready),.sda(knob_sda),.scl(knob_scl),
        .knob_value_flat(knob_value_flat),.knob_sample_valid(knob_valid),
        .param_ready(param_ready),.param_fault(param_fault),
        .brightness_value(slider_brightness),.brightness_valid(slider_valid),.brightness_ready(slider_ready));
    // 观察已接受的旋钮目标值；音频按原合同平滑，显示不反馈控制。
    wire signed [15:0] mapped_bend;
    display_bend_map u_bend_display(.knob(knob_value_flat[13:7]),.bend(mapped_bend));
    always @(posedge sys_clk) begin
        // piano_controls复位为单位增益65536，对应旋钮127；显示须与真实启动状态一致。
        if(!core_ready) begin volume<=7'd127;bend<=0;end
        else if(knob_valid && param_ready && !param_fault) begin
            volume<=knob_value_flat[6:0];
            bend<=mapped_bend;
        end
    end
    instrument_uart_top #(.ROM_FILE(ROM_FILE),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .FIXED_PIANO(1),.ATTACK_SAMPLES(96),.DECAY_SAMPLES(57600),.SUSTAIN_LEVEL(0),.RELEASE_SAMPLES(8640),
        .REQUEST_LEAD_HALF_EDGES(USE_MODAL?60:((ENABLE_REVERB || ENABLE_CHORUS || ENABLE_DELAY)?3:2)),.EXTERNAL_PIANO_KEYS(1),.VOICES(VOICES),
        .ENABLE_CONTROLS(1),.ENABLE_GUITAR(1),.USE_MODAL(USE_MODAL),.ENABLE_REVERB(ENABLE_REVERB),
        .ENABLE_CHORUS(ENABLE_CHORUS),.ENABLE_DELAY(ENABLE_DELAY),
        .ENABLE_BRIGHTNESS(ENABLE_BRIGHTNESS || ENABLE_TOUCH_BRIGHTNESS || ENABLE_SLIDER_BRIGHTNESS),
        .EXTERNAL_BRIGHTNESS(ENABLE_TOUCH_BRIGHTNESS || ENABLE_SLIDER_BRIGHTNESS),.ENABLE_OCTAVE_KEY(ENABLE_OCTAVE_KEY),
        .ENABLE_BLE(ENABLE_BLE),.ENABLE_TOUCH(ENABLE_USB_TOUCH),.BLE_CLKS_PER_BIT(BLE_CLKS_PER_BIT),
        .BRIGHTNESS_REPEAT_CYCLES(BRIGHTNESS_REPEAT_CYCLES)) u_core(
        .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.Key_in(Key_in),.piano_key_n(piano_key_n),
        .uart_rx(uart_rx),.uart_tx(uart_tx),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN),
        .knob_value_flat(knob_value_flat),.knob_valid(knob_valid),.param_ready(param_ready),.param_fault(param_fault),
        .control_sustain(1'b0),.control_octave(2'd1),.control_ready(core_ready),.monitor_audio_valid(audio_valid),
        .monitor_audio_sample(audio_sample),.monitor_key_down(held_keys),.monitor_instrument_guitar(instrument_guitar),
        .monitor_piano_keys(piano_held_keys),.monitor_guitar_keys(guitar_held_keys),.monitor_octave(current_octave),
        .control_brightness(brightness_target),.monitor_brightness(brightness_current),
        .ble_rx(ble_rx),.ble_tx(ble_tx),.ble_state(ble_state),
        .monitor_note_on(guide_note_on),.monitor_event_note(guide_played_note),
        .touch_event_valid(touch_event_valid),.touch_event_ready(touch_event_ready),
        .touch_event_on(touch_event_on),.touch_event_guitar(touch_event_guitar),.touch_event_source(touch_event_source),
        .touch_event_note(touch_event_note),.touch_event_velocity(touch_event_velocity),
        .touch_cancel_valid(touch_cancel_valid),.touch_cancel_ready(touch_cancel_ready));
    wire [23:0] rgb;
    wire de,hs,vs;
    // UI=1：正式 2bit 覆盖度界面；旧逐像素帧测试仍用 UI=0 的兼容绘制器。
    instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),
        .TOUCH_PANEL(ENABLE_TOUCH_BRIGHTNESS),.ENABLE_GUIDE(ENABLE_GUIDE),
        .BRIGHTNESS_PANEL(ENABLE_SLIDER_BRIGHTNESS),
        .H_FRONT(40),.H_SYNC(104),.H_BACK(144),.V_FRONT(3),.V_SYNC(7),.V_BACK(14),
        .HS_ACTIVE(0),.VS_ACTIVE(1)) u_display(
        .sys_clk(sys_clk),.pixel_clk(pixel_clk),.rst_n(display_reset),.key_down(held_keys),
        .piano_keys(piano_held_keys),.guitar_keys(guitar_held_keys),
        .volume(volume),.pitch_bend(bend),.octave(current_octave),.sustain(1'b0),.instrument_guitar(instrument_guitar),
        .audio_valid(audio_valid),.audio_sample(audio_sample),
        .brightness(brightness_current),.touch_available(touch_available),
        .guide_valid(guide_valid),.guide_index(guide_index),.guide_progress(guide_progress),
        .lcd_rgb(rgb),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.frame_start(),.display_sample_drop());
    // 在像素域同步释放编码器/OSER复位；锁丢失同时清掉显示信箱两端。
    reg [1:0] video_release;
    always @(posedge pixel_clk or negedge display_reset)
        if(!display_reset) video_release<=0;
        else video_release<={video_release[0],1'b1};
    dvi_tx_gowin u_tx(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst_n(video_release[1]),
        .rgb(rgb),.de(de),.hsync(hs),.vsync(vs),.tmds_data_p(tmds_data_p),
        .tmds_data_n(tmds_data_n),.tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n));
endmodule
