// Generic integration only: external pixel clock, no guessed PLL or LCD pinout.
// Status/audio copies never backpressure the performance core. Touch is not implemented.
module music_display_top #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer UART_CLKS_PER_BIT=434,
    parameter integer WATCHDOG_CYCLES=150000000,
    parameter integer VOICES=16,
    parameter [31:0] P_RELEASE=4096,
    parameter integer REQUEST_LEAD_HALF_EDGES=60
)(
    input wire sys_clk,sys_rst_n,input wire [1:0] Key_in,
    input wire uart_rx,output wire uart_tx,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,
    input wire pixel_clk,display_rst_n,
    output wire [23:0] lcd_rgb,
    output wire lcd_de,lcd_hsync,lcd_vsync,frame_start,display_sample_drop
);
    wire [6:0] volume_copy;wire signed [15:0] bend_copy;
    wire [12:0] key_copy;
    wire guitar_copy,audio_valid;
    wire signed [15:0] audio_sample;
    music_performance_core #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),.WATCHDOG_CYCLES(WATCHDOG_CYCLES),
        .VOICES(VOICES),.P_RELEASE(P_RELEASE),.REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES)) u_core(
        .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.Key_in(Key_in),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN),
        .external_control_valid(1'b0),.external_volume(7'd127),.external_bend(11'd512),.external_control_ready(),
        .monitor_volume(volume_copy),.monitor_bend(bend_copy),
        .monitor_keys(key_copy),.monitor_guitar(guitar_copy),.monitor_valid(audio_valid),.monitor_sample(audio_sample));
    instrument_display u_display(.sys_clk(sys_clk),.pixel_clk(pixel_clk),.rst_n(display_rst_n),
        .key_down(key_copy),.volume(volume_copy),.pitch_bend(bend_copy),.octave(2'd1),
        .sustain(1'b0),.instrument_guitar(guitar_copy),.audio_valid(audio_valid),.audio_sample(audio_sample),
        .lcd_rgb(lcd_rgb),.lcd_de(lcd_de),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),
        .frame_start(frame_start),.display_sample_drop(display_sample_drop));
endmodule
