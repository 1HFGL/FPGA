// Main board entry for thirteen independent active-low piano buttons.
// Bit 0..12 = C4,C#4,D4,D#4,E4,F4,F#4,G4,G#4,A4,A#4,B4,C5.
// Reuse the team's existing piano engine, UART and PT8211-S output timing.
module piano_13key_top #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer UART_CLKS_PER_BIT=434,
    parameter integer WATCHDOG_CYCLES=150000000,
    parameter ROM_FILE="../../rtl/rom/piano_1024.mem",
    parameter [31:0] ATTACK_SAMPLES=96,DECAY_SAMPLES=57600,RELEASE_SAMPLES=8640,
    parameter integer REQUEST_LEAD_HALF_EDGES=2
)(
    input wire sys_clk,sys_rst_n,
    input wire [1:0] Key_in,
    input wire [12:0] piano_key_n,
    input wire uart_rx,
    output wire uart_tx,HP_BCK,HP_WS,HP_DIN,PA_EN
);
    instrument_uart_top #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .WATCHDOG_CYCLES(WATCHDOG_CYCLES),.ROM_FILE(ROM_FILE),.FIXED_PIANO(1),
        .ATTACK_SAMPLES(ATTACK_SAMPLES),.DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(17'd0),.RELEASE_SAMPLES(RELEASE_SAMPLES),
        .REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES),.EXTERNAL_PIANO_KEYS(1)
    ) u_core(
        .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.Key_in(Key_in),.piano_key_n(piano_key_n),
        .uart_rx(uart_rx),.uart_tx(uart_tx),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN)
    );
endmodule
