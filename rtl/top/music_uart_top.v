// Board entry: existing ten pinned signals, no screen pins.
module music_uart_top #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer UART_CLKS_PER_BIT=434,
    parameter integer WATCHDOG_CYCLES=150000000,
    parameter integer VOICES=16,
    parameter [31:0] P_RELEASE=4096,
    parameter integer REQUEST_LEAD_HALF_EDGES=60
)(
    input wire sys_clk,sys_rst_n,input wire [1:0] Key_in,
    input wire uart_rx,output wire uart_tx,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN
);
    music_performance_core #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),.WATCHDOG_CYCLES(WATCHDOG_CYCLES),
        .VOICES(VOICES),.P_RELEASE(P_RELEASE),.REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES)) u_core(
        .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.Key_in(Key_in),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN),
        .external_control_valid(1'b0),.external_volume(7'd127),.external_bend(11'd512),.external_control_ready(),
        .monitor_volume(),.monitor_bend(),
        .monitor_keys(),.monitor_guitar(),.monitor_valid(),.monitor_sample());
endmodule
