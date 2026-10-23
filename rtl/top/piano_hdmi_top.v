// 7寸1024x600 HDMI屏候选板级顶层；复用唯一钢琴内核，无CPU/DDR/帧缓存。
// 手册hdmi_cvt 1024 600 60 6 0 0 0推导普通CVT，具体驱动板仍须实屏验证。
// HDMI只发DVI兼容视频；耳机/音箱仍接板载DAC。USB触摸主机未实现。
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
    parameter integer UART_CLKS_PER_BIT=434
)(
    input wire sys_clk,sys_rst_n,
    input wire [1:0] Key_in,
    input wire [12:0] piano_key_n,
    input wire uart_rx,hdmi_hpd,
    output wire uart_tx,HP_BCK,HP_WS,HP_DIN,PA_EN,
    inout wire knob_sda,
    output wire knob_scl,
    output wire [2:0] tmds_data_p,tmds_data_n,
    output wire tmds_clk_p,tmds_clk_n
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
    // Board-side boundary only: replace these constants with a verified USB-host
    // adapter after controller, HID report and wiring are known. HDMI has no touch.
    // Simulations drive this boundary; the present bitstream cannot receive fingers.
    wire touch_connected=1'b0;
    wire touch_report_valid=1'b0;
    wire touch_down=1'b0;
    wire [11:0] touch_x=12'd0,touch_y=12'd0;
    wire [6:0] brightness_target,brightness_current;
    wire touch_available;
    touch_brightness_control u_touch(.clk(sys_clk),.rst_n(core_ready),
        .connected(touch_connected),.report_valid(touch_report_valid),.contact_down(touch_down),
        .contact_x(touch_x),.contact_y(touch_y),.target(brightness_target),
        .available(touch_available),.dragging());
    reg [6:0] volume;
    reg signed [15:0] bend;
    wire signed [15:0] audio_sample;
    wire audio_valid,knob_valid,param_ready,param_fault;
    wire [13:0] knob_value_flat;
    wire [12:0] piano_held_keys,guitar_held_keys;
    ads1115_knob_if u_adc(.clk(sys_clk),.rst_n(core_ready),.sda(knob_sda),.scl(knob_scl),
        .knob_value_flat(knob_value_flat),.knob_sample_valid(knob_valid),
        .param_ready(param_ready),.param_fault(param_fault));
    // 观察已接受的旋钮目标值；音频按原合同平滑，显示不反馈控制。
    wire signed [15:0] mapped_bend;
    display_bend_map u_bend_display(.knob(knob_value_flat[13:7]),.bend(mapped_bend));
    always @(posedge sys_clk) begin
        if(!core_ready) begin volume<=USE_MODAL?7'd8:7'd127;bend<=0;end
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
        .ENABLE_BRIGHTNESS(ENABLE_BRIGHTNESS || ENABLE_TOUCH_BRIGHTNESS),
        .EXTERNAL_BRIGHTNESS(ENABLE_TOUCH_BRIGHTNESS),.ENABLE_OCTAVE_KEY(ENABLE_OCTAVE_KEY),
        .BRIGHTNESS_REPEAT_CYCLES(BRIGHTNESS_REPEAT_CYCLES)) u_core(
        .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.Key_in(Key_in),.piano_key_n(piano_key_n),
        .uart_rx(uart_rx),.uart_tx(uart_tx),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN),
        .knob_value_flat(knob_value_flat),.knob_valid(knob_valid),.param_ready(param_ready),.param_fault(param_fault),
        .control_sustain(1'b0),.control_octave(2'd1),.control_ready(core_ready),.monitor_audio_valid(audio_valid),
        .monitor_audio_sample(audio_sample),.monitor_key_down(held_keys),.monitor_instrument_guitar(instrument_guitar),
        .monitor_piano_keys(piano_held_keys),.monitor_guitar_keys(guitar_held_keys),.monitor_octave(current_octave),
        .control_brightness(brightness_target),.monitor_brightness(brightness_current));
    wire [23:0] rgb;
    wire de,hs,vs;
    // UI=1：正式 2bit 覆盖度界面；旧逐像素帧测试仍用 UI=0 的兼容绘制器。
    instrument_display #(.H_ACTIVE(1024),.V_ACTIVE(600),.WIDE(1),.ENHANCED(1),.UI(1),
        .TOUCH_PANEL(ENABLE_TOUCH_BRIGHTNESS),
        .H_FRONT(40),.H_SYNC(104),.H_BACK(144),.V_FRONT(3),.V_SYNC(7),.V_BACK(14),
        .HS_ACTIVE(0),.VS_ACTIVE(1)) u_display(
        .sys_clk(sys_clk),.pixel_clk(pixel_clk),.rst_n(display_reset),.key_down(held_keys),
        .piano_keys(piano_held_keys),.guitar_keys(guitar_held_keys),
        .volume(volume),.pitch_bend(bend),.octave(current_octave),.sustain(1'b0),.instrument_guitar(instrument_guitar),
        .audio_valid(audio_valid),.audio_sample(audio_sample),
        .brightness(brightness_current),.touch_available(touch_available),
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
