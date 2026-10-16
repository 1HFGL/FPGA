// 钢琴感固定预设：只更换单周期波表和编译期ADSR，复用现有四声部/UART/B输出。
// 不存储钢琴录音、不引入软件播放器；相位/包络/混音仍由FPGA实时计算。
// 48kHz下：96点=2ms；57600点=1200ms；8640点=180ms；保持电平为0。
// 本版为线性衰减、固定谐波比例的合成近似；没有真实钢琴的分音独立衰减。
module instrument_uart_piano_top #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer UART_CLKS_PER_BIT=434,
    parameter integer WATCHDOG_CYCLES=150000000,
    parameter ROM_FILE="../../rtl/rom/piano_1024.mem",
    parameter integer REQUEST_LEAD_HALF_EDGES=2
)(
    input wire sys_clk,sys_rst_n,
    input wire [1:0] Key_in,
    input wire uart_rx,
    output wire uart_tx,HP_BCK,HP_WS,HP_DIN,PA_EN
);
    instrument_uart_top #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .WATCHDOG_CYCLES(WATCHDOG_CYCLES),.ROM_FILE(ROM_FILE),.FIXED_PIANO(1),
        .REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES),
        .ATTACK_SAMPLES(32'd96),.DECAY_SAMPLES(32'd57600),
        .SUSTAIN_LEVEL(17'd0),.RELEASE_SAMPLES(32'd8640)
    ) u_core(
        .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.Key_in(Key_in),.piano_key_n(13'h1fff),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN)
    );
endmodule
