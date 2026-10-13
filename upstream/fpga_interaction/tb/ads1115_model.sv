`timescale 1ns/1ps
// ADS1115 行为模型（I2C 从机），供各测试台复用。
module ads1115_model #(
    parameter [6:0] ADDR = 7'h48,
    parameter [15:0] CONV0 = 16'h4000,
    parameter [15:0] CONV1 = 16'h2000,
    parameter integer CH0_MUX = 4,
    parameter integer CH1_MUX = 5
) (
    input  wire scl,
    inout  wire sda
);
    reg sda_drv = 1'b1;                 // 1=释放, 0=拉低
    // Fault controls are set by the testbench, without changing existing ports.
    reg connected = 1'b1;
    integer nack_byte = -1;
    reg nack_read_address = 1'b0;
    reg nack_conversion_pointer = 1'b0;
    reg [15:0] conversion0 = CONV0;
    reg [15:0] conversion1 = CONV1;
    integer byte_index = 0;
    reg accepted = 1'b0;
    assign sda = (connected && !sda_drv) ? 1'b0 : 1'bz;

    reg [7:0]  ptr = 8'h00;
    reg [15:0] cfg = 16'h0000;
    wire [15:0] conv_sel = (ptr == 8'h00) ? ((cfg[14:12] == CH0_MUX) ? conversion0 : conversion1) : 16'd0;

    reg active    = 1'b0;
    reg rw        = 1'b0;
    reg [1:0] wphase = 2'd0;            // 0 地址,1 指针,2 cfgMSB,3 cfgLSB
    reg [3:0] bitcnt = 4'd0;
    reg [7:0] shr    = 8'd0;
    reg send_mode = 1'b0;
    reg [15:0] out_shr = 16'd0;
    reg [4:0] send_cnt = 5'd0;

    always @(negedge sda) if (scl) begin
        active <= 1'b1; rw <= 1'b0; wphase <= 2'd0; bitcnt <= 4'd0;
        shr <= 8'd0; send_mode <= 1'b0; sda_drv <= 1'b1; send_cnt <= 5'd0;
        byte_index <= 0;
    end
    always @(posedge sda) if (scl) begin
        active <= 1'b0; sda_drv <= 1'b1; send_mode <= 1'b0;
    end

    always @(posedge scl) if (active && !send_mode) begin
        if (bitcnt < 8) shr <= {shr[6:0], sda};
        bitcnt <= bitcnt + 1'b1;
    end

    always @(negedge scl) begin
        if (!active) begin
            sda_drv <= 1'b1;
        end else if (send_mode) begin
            if (send_cnt < 5'd8) begin
                sda_drv <= out_shr[15]; out_shr <= {out_shr[14:0], 1'b0}; send_cnt <= send_cnt + 1'b1;
            end else if (send_cnt == 5'd8) begin
                sda_drv <= 1'b1; send_cnt <= 5'd9;
            end else if (send_cnt < 5'd17) begin
                sda_drv <= out_shr[15]; out_shr <= {out_shr[14:0], 1'b0}; send_cnt <= send_cnt + 1'b1;
            end else begin
                sda_drv <= 1'b1;
            end
        end else begin
            if (bitcnt == 4'd8) begin
                accepted = connected && (byte_index != nack_byte) &&
                           ((wphase != 0) || (shr[7:1] == ADDR)) &&
                           !(nack_read_address && (wphase == 0) && shr[0]) &&
                           !(nack_conversion_pointer && (wphase == 1) && (shr == 0));
                sda_drv <= !accepted;
            end else if (bitcnt == 4'd9) begin
                sda_drv <= 1'b1; bitcnt <= 4'd0;
                byte_index <= byte_index + 1;
                if (!accepted) begin
                    active <= 1'b0;
                end else case (wphase)
                    2'd0: begin
                        if (shr[0]) begin   // 读：立即送出第一位
                            out_shr <= {conv_sel[14:0], 1'b0};
                            sda_drv <= conv_sel[15];
                            send_mode <= 1'b1; send_cnt <= 5'd1; rw <= 1'b1;
                        end else begin
                            rw <= 1'b0; wphase <= 2'd1;
                        end
                    end
                    2'd1: begin ptr <= shr; wphase <= 2'd2; end
                    2'd2: begin cfg[15:8] <= shr; wphase <= 2'd3; end
                    2'd3: begin cfg[7:0] <= shr; wphase <= 2'd0; end
                endcase
            end else begin
                sda_drv <= 1'b1;
            end
        end
    end
endmodule
