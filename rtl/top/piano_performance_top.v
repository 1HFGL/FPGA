// 正式主工程：13实体键+UART共享16声部；KEY2切钢琴/吉他，KEY1短按调暗/长按恢复明亮度。
// ADS1115 AIN0音量/AIN1全局弯音；松键后的旧音色尾音自然结束。
// B10K两端接3.3V/GND，滑端接AIN；I2C上拉必须到3.3V。
// 触摸型号尚未确定；延音/八度内部接口本轮默认关闭/中档。
module piano_performance_top #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer UART_CLKS_PER_BIT=434,
    parameter integer WATCHDOG_CYCLES=150000000,
    parameter ROM_FILE="../../rtl/rom/piano_1024.mem",
    parameter [31:0] ATTACK_SAMPLES=96,DECAY_SAMPLES=57600,RELEASE_SAMPLES=8640,
    // 与带屏入口使用相同快速旋钮配置；斜坡平滑留在音频采样域。
    parameter integer ADC_I2C_HZ=350000, ADC_CONV_WAIT=75000, ADC_READY_SAMPLES=2,
    parameter integer ADC_FILTER_SHIFT=0,ADC_SLEW_STEP=127,
    parameter [2:0] ADC_DR=3'b111,
    parameter integer ENABLE_BRIGHTNESS=1,
    parameter integer BRIGHTNESS_REPEAT_CYCLES=25000000,
    parameter integer USE_MODAL=1
)(
    input wire sys_clk,sys_rst_n,
    input wire [1:0] Key_in,
    input wire [12:0] piano_key_n,
    input wire uart_rx,
    output wire uart_tx,HP_BCK,HP_WS,HP_DIN,PA_EN,
    inout wire knob_sda,
    output wire knob_scl
);
    wire [13:0] knob_value_flat;
    wire knob_valid,param_ready,param_fault,core_ready;
    // 无屏入口不消费显示观察副本；显式连接后由综合裁剪，避免接口漏接告警。
    wire unused_monitor_valid;
    wire signed [15:0] unused_monitor_sample;
    wire [12:0] unused_monitor_keys;
    ads1115_knob_if #(.I2C_HZ(ADC_I2C_HZ),.CONV_WAIT(ADC_CONV_WAIT),.DR(ADC_DR),
        .READY_SAMPLES(ADC_READY_SAMPLES),.FILTER_SHIFT(ADC_FILTER_SHIFT),.SLEW_STEP(ADC_SLEW_STEP)) u_adc(
        .clk(sys_clk),.rst_n(core_ready),.sda(knob_sda),.scl(knob_scl),
        .knob_value_flat(knob_value_flat),.knob_sample_valid(knob_valid),
        .param_ready(param_ready),.param_fault(param_fault));
    instrument_uart_top #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .WATCHDOG_CYCLES(WATCHDOG_CYCLES),.ROM_FILE(ROM_FILE),.FIXED_PIANO(1),
        .ATTACK_SAMPLES(ATTACK_SAMPLES),.DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(17'd0),.RELEASE_SAMPLES(RELEASE_SAMPLES),
        .REQUEST_LEAD_HALF_EDGES(USE_MODAL?60:2),.EXTERNAL_PIANO_KEYS(1),.VOICES(16),
        .ENABLE_CONTROLS(1),.ENABLE_GUITAR(1),.USE_MODAL(USE_MODAL),
        .ENABLE_BRIGHTNESS(ENABLE_BRIGHTNESS),.BRIGHTNESS_REPEAT_CYCLES(BRIGHTNESS_REPEAT_CYCLES)) u_core(
        .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.Key_in(Key_in),.piano_key_n(piano_key_n),
        .uart_rx(uart_rx),.uart_tx(uart_tx),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN),
        .knob_value_flat(knob_value_flat),.knob_valid(knob_valid),.param_ready(param_ready),.param_fault(param_fault),
        .control_sustain(1'b0),.control_octave(2'd1),.control_ready(core_ready),
        .monitor_audio_valid(unused_monitor_valid),.monitor_audio_sample(unused_monitor_sample),
        .monitor_key_down(unused_monitor_keys),.monitor_instrument_guitar(),.monitor_piano_keys(),.monitor_guitar_keys());
endmodule
