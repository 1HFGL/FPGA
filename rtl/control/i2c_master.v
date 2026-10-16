`timescale 1ns/1ps
// 简单 I2C 主机（单主机、开漏 SDA，SCL 推挽）。
// 一次处理一个字节级操作：
//   op = 0 START, 1 STOP, 2 WRITE, 3 READ(主机回 ACK), 4 READ(主机回 NACK)
module i2c_master #(
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire req,          // 1 周期脉冲或电平，锁存后开始
    input  wire [2:0] op,
    input  wire [7:0] wr_data,
    output reg  done,         // 操作完成，1 周期脉冲
    output reg  ack,          // WRITE 后：0=收到 ACK，1=NACK
    output reg  [7:0] rd_data,
    inout  wire sda,
    output reg  scl
);

    localparam [2:0] OP_START = 3'd0, OP_STOP = 3'd1, OP_WRITE = 3'd2,
                     OP_READA = 3'd3, OP_READN = 3'd4;

    localparam integer QDIV = (CLK_HZ / (I2C_HZ * 4)) > 0 ? (CLK_HZ / (I2C_HZ * 4)) : 1;

    reg sda_oe;                 // 1 = 把 SDA 拉低（开漏）
    wire sda_in;
    assign sda    = sda_oe ? 1'b0 : 1'bz;
    reg sda_meta,sda_sync;
    // 外设返回SDA异步于50MHz，先同步后在I2C高电平中部采样。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin sda_meta<=1'b1;sda_sync<=1'b1;end
        else begin sda_meta<=sda;sda_sync<=sda_meta;end
    end
    assign sda_in = sda_sync;

    reg busy;
    reg [2:0] op_r;
    reg [7:0] shreg;
    reg [3:0] bit_idx;          // 0..8（8=ACK/NACK 位）
    reg [1:0] phase;            // 0..3
    reg [31:0] qcnt;
    reg tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            qcnt <= 32'd0;
            tick <= 1'b0;
        end else begin
            if (busy) begin
                if (qcnt >= QDIV - 1) begin
                    qcnt <= 32'd0;
                    tick <= 1'b1;
                end else begin
                    qcnt <= qcnt + 1'b1;
                    tick <= 1'b0;
                end
            end else begin
                qcnt <= 32'd0;
                tick <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy    <= 1'b0;
            done    <= 1'b0;
            ack     <= 1'b1;
            rd_data <= 8'd0;
            scl     <= 1'b1;
            sda_oe  <= 1'b0;
            op_r    <= OP_START;
            shreg   <= 8'd0;
            bit_idx <= 4'd0;
            phase   <= 2'd0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (req) begin
                    busy    <= 1'b1;
                    op_r    <= op;
                    shreg   <= wr_data;
                    bit_idx <= 4'd0;
                    phase   <= 2'd0;
                    // 起始状态准备
                    case (op)
                        OP_START: begin scl <= 1'b1; sda_oe <= 1'b0; end
                        OP_STOP:  begin scl <= 1'b0; sda_oe <= 1'b1; end
                        default:  begin scl <= 1'b0; sda_oe <= 1'b0; end
                    endcase
                end
            end else if (tick) begin
                case (op_r)
                    OP_START: begin
                        case (phase)
                            2'd0: begin scl <= 1'b1; sda_oe <= 1'b0; phase <= 2'd1; end
                            2'd1: begin scl <= 1'b1; sda_oe <= 1'b1; phase <= 2'd2; end
                            2'd2: begin scl <= 1'b0; sda_oe <= 1'b1; phase <= 2'd3; end
                            default: begin busy <= 1'b0; done <= 1'b1; sda_oe <= 1'b1; end
                        endcase
                    end

                    OP_STOP: begin
                        case (phase)
                            2'd0: begin scl <= 1'b0; sda_oe <= 1'b1; phase <= 2'd1; end
                            2'd1: begin scl <= 1'b1; sda_oe <= 1'b1; phase <= 2'd2; end
                            2'd2: begin scl <= 1'b1; sda_oe <= 1'b0; phase <= 2'd3; end
                            default: begin busy <= 1'b0; done <= 1'b1; sda_oe <= 1'b0; end
                        endcase
                    end

                    OP_WRITE: begin
                        case (phase)
                            2'd0: begin
                                scl <= 1'b0;
                                // 数据位：bit=0 拉低，bit=1 释放；ACK 位释放
                                if (bit_idx == 8)
                                    sda_oe <= 1'b0;
                                else
                                    sda_oe <= ~shreg[7];
                                phase <= 2'd1;
                            end
                            2'd1: begin scl <= 1'b1; phase <= 2'd2; end
                            2'd2: begin
                                scl <= 1'b1;
                                if (bit_idx == 8) ack <= sda_in;    // 0=ACK, 1=NACK
                                phase <= 2'd3;
                            end
                            default: begin
                                scl <= 1'b0;
                                if (bit_idx == 8) begin
                                    busy <= 1'b0; done <= 1'b1;
                                end else begin
                                    shreg <= {shreg[6:0], 1'b0};
                                end
                                bit_idx <= bit_idx + 1'b1;
                                phase <= 2'd0;
                            end
                        endcase
                    end

                    OP_READA, OP_READN: begin
                        case (phase)
                            2'd0: begin
                                scl <= 1'b0;
                                if (bit_idx == 8)
                                    sda_oe <= (op_r == OP_READA) ? 1'b1 : 1'b0;
                                else
                                    sda_oe <= 1'b0;
                                phase <= 2'd1;
                            end
                            2'd1: begin scl <= 1'b1; phase <= 2'd2; end
                            2'd2: begin
                                scl <= 1'b1;
                                if (bit_idx != 8)
                                    rd_data <= {rd_data[6:0], sda_in};
                                phase <= 2'd3;
                            end
                            default: begin
                                scl <= 1'b0;
                                if (bit_idx == 8) begin
                                    busy <= 1'b0; done <= 1'b1;
                                end
                                bit_idx <= bit_idx + 1'b1;
                                phase <= 2'd0;
                            end
                        endcase
                    end

                    default: begin
                        busy <= 1'b0; done <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
