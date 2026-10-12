`timescale 1ns/1ps
// ADS1115 前端：通过 I2C 主机驱动 ADS1115，轮流采集两个旋钮通道，
// 输出 2 x 16bit 原始数据 + sample_valid（两通道都更新后给一个脉冲）。
module ads1115_if #(
    parameter integer CLK_HZ      = 50000000,
    parameter integer I2C_HZ      = 100000,
    parameter [6:0]  I2C_ADDR     = 7'h48,   // ADDR 引脚接 GND 时
    parameter [2:0]  PGA          = 3'b001,  // 001 = +/-4.096V
    parameter [2:0]  DR           = 3'b100,  // 100 = 128 SPS
    parameter integer CH0_MUX     = 4,       // 100 = AIN0-GND
    parameter integer CH1_MUX     = 5,       // 101 = AIN1-GND
    parameter integer CONV_WAIT   = 500000,  // 等待转换完成周期数
    parameter integer STARTUP_WAIT= 1000,
    parameter integer RETRY_WAIT  = CLK_HZ / 100
) (
    input  wire clk,
    input  wire rst_n,
    output reg  [31:0] raw_flat,     // {chn1[15:0], chn0[15:0]}
    output reg  sample_valid,
    output reg  fault,
    inout  wire sda,
    output wire scl
);

    localparam [2:0] OP_START = 3'd0, OP_STOP = 3'd1, OP_WRITE = 3'd2,
                     OP_READA = 3'd3, OP_READN = 3'd4;

    reg chn;
    wire [7:0] addr_w = {I2C_ADDR, 1'b0};
    wire [7:0] addr_r = {I2C_ADDR, 1'b1};
    wire [2:0] mux    = (chn == 0) ? CH0_MUX[2:0] : CH1_MUX[2:0];
    wire [15:0] cfg   = {1'b1, mux, PGA, 1'b1, DR, 3'b000, 2'b11};

    reg [15:0] ch0_data;
    reg [15:0] ch1_data;
    reg [7:0]  rd_msb;
    reg [7:0]  rd_lsb;
    reg [31:0] wait_cnt;
    reg [4:0]  step;

    reg i2c_req;
    reg [2:0] i2c_op;
    reg [7:0] i2c_wr;
    wire i2c_done;
    wire i2c_ack;
    wire [7:0] i2c_rd;
    wire write_step = (step == 2) || (step == 3) || (step == 4) ||
                      (step == 5) || (step == 9) || (step == 10) || (step == 13);

    i2c_master #(
        .CLK_HZ (CLK_HZ),
        .I2C_HZ (I2C_HZ)
    ) u_i2c (
        .clk     (clk),
        .rst_n   (rst_n),
        .req     (i2c_req),
        .op      (i2c_op),
        .wr_data (i2c_wr),
        .done    (i2c_done),
        .ack     (i2c_ack),
        .rd_data (i2c_rd),
        .sda     (sda),
        .scl     (scl)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step         <= 5'd0;
            chn          <= 1'b0;
            ch0_data     <= 16'd0;
            ch1_data     <= 16'd0;
            rd_msb       <= 8'd0;
            rd_lsb       <= 8'd0;
            raw_flat     <= 32'd0;
            sample_valid <= 1'b0;
            fault        <= 1'b0;
            wait_cnt     <= STARTUP_WAIT;
            i2c_req      <= 1'b0;
            i2c_op       <= OP_START;
            i2c_wr       <= 8'd0;
        end else begin
            i2c_req      <= 1'b0;
            sample_valid <= 1'b0;

            // Every transmitted byte must be ACKed. Abort the whole pair on NACK.
            if (i2c_done && write_step && (i2c_ack !== 1'b0)) begin
                fault <= 1'b1;
                chn <= 1'b0;
                step <= 5'd17;
                i2c_req <= 1'b1;
                i2c_op <= OP_STOP;
            end else case (step)
                // ---- 上电等待 ----
                5'd0: begin
                    if (wait_cnt == 0) begin
                        step <= 5'd1;
                        i2c_req <= 1'b1;
                        i2c_op  <= OP_START;
                    end else begin
                        wait_cnt <= wait_cnt - 1'b1;
                    end
                end

                // ---- 写 Config，启动单次转换 ----
                5'd1: begin // START
                    if (i2c_done) begin step <= 5'd2; i2c_req <= 1'b1; i2c_op <= OP_WRITE; i2c_wr <= addr_w; end
                end
                5'd2: begin // 写从机地址(W)，检查 ACK
                    if (i2c_done) begin
                        step <= 5'd3; i2c_req <= 1'b1; i2c_op <= OP_WRITE; i2c_wr <= 8'h01;
                    end
                end
                5'd3: begin // 指针 = Config(0x01)
                    if (i2c_done) begin step <= 5'd4; i2c_req <= 1'b1; i2c_op <= OP_WRITE; i2c_wr <= cfg[15:8]; end
                end
                5'd4: begin // Config[15:8]
                    if (i2c_done) begin step <= 5'd5; i2c_req <= 1'b1; i2c_op <= OP_WRITE; i2c_wr <= cfg[7:0]; end
                end
                5'd5: begin // Config[7:0]
                    if (i2c_done) begin step <= 5'd6; i2c_req <= 1'b1; i2c_op <= OP_STOP; end
                end
                5'd6: begin // STOP，随后等待转换完成
                    if (i2c_done) begin step <= 5'd7; wait_cnt <= CONV_WAIT; end
                end
                5'd7: begin // 等待转换完成
                    if (wait_cnt == 0) begin step <= 5'd8; i2c_req <= 1'b1; i2c_op <= OP_START; end
                    else wait_cnt <= wait_cnt - 1'b1;
                end

                // ---- 读转换结果 ----
                5'd8: begin // START
                    if (i2c_done) begin step <= 5'd9; i2c_req <= 1'b1; i2c_op <= OP_WRITE; i2c_wr <= addr_w; end
                end
                5'd9: begin // 写从机地址(W)
                    if (i2c_done) begin step <= 5'd10; i2c_req <= 1'b1; i2c_op <= OP_WRITE; i2c_wr <= 8'h00; end
                end
                5'd10: begin // 指针 = Conversion(0x00)
                    if (i2c_done) begin step <= 5'd11; i2c_req <= 1'b1; i2c_op <= OP_STOP; end
                end
                5'd11: begin // STOP，准备读
                    if (i2c_done) begin step <= 5'd12; i2c_req <= 1'b1; i2c_op <= OP_START; end
                end
                5'd12: begin // START
                    if (i2c_done) begin step <= 5'd13; i2c_req <= 1'b1; i2c_op <= OP_WRITE; i2c_wr <= addr_r; end
                end
                5'd13: begin // 写从机地址(R)
                    if (i2c_done) begin step <= 5'd14; i2c_req <= 1'b1; i2c_op <= OP_READA; end
                end
                5'd14: begin // 读 MSB
                    if (i2c_done) begin rd_msb <= i2c_rd; step <= 5'd15; i2c_req <= 1'b1; i2c_op <= OP_READN; end
                end
                5'd15: begin // 读 LSB
                    if (i2c_done) begin rd_lsb <= i2c_rd; step <= 5'd16; i2c_req <= 1'b1; i2c_op <= OP_STOP; end
                end
                5'd16: begin // STOP，存结果
                    if (i2c_done) begin
                        if (chn == 0) begin
                            ch0_data <= {rd_msb, rd_lsb};
                            chn <= 1'b1;
                        end else begin
                            ch1_data <= {rd_msb, rd_lsb};
                            chn <= 1'b0;
                            sample_valid <= 1'b1;
                            raw_flat <= {rd_msb, rd_lsb, ch0_data};
                            fault <= 1'b0;
                        end
                        step <= 5'd1;
                        i2c_req <= 1'b1; i2c_op <= OP_START;
                    end
                end

                5'd17: begin // Abort STOP completed; delay before retrying channel 0.
                    if (i2c_done) begin
                        wait_cnt <= RETRY_WAIT;
                        step <= 5'd0;
                    end
                end

                default: begin
                    step <= 5'd1;
                end
            endcase
        end
    end

endmodule
