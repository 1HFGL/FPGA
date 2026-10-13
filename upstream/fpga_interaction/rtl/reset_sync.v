`timescale 1ns/1ps

module reset_sync (
    input  wire clk,
    input  wire raw_rst_n,
    output wire rst_n_sync
);

    reg [1:0] sync_cnt;

    always @(posedge clk or negedge raw_rst_n) begin
        if (!raw_rst_n) begin
            sync_cnt <= 2'b00;
        end else begin
            sync_cnt <= {sync_cnt[0], 1'b1};
        end
    end

    assign rst_n_sync = sync_cnt[1];

endmodule