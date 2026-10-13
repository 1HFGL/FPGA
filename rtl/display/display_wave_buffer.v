// 像素域波形快照：两个256点、8位的缓冲区，共512字节，不需要整屏帧缓存。
// 写满一页后等待 frame_commit 再交换；帧内读页不被写，避免波形撕裂。
// 等待交换时只丢显示样本，audio_valid 没有反压。每页保留连续收到的256个样本。
// 不清空RAM：复位清除有效标志，在首个完整页发布前读出强制为0。
module display_wave_buffer (
    input wire pixel_clk, rst_n,
    input wire sample_valid,
    input wire [7:0] sample_data,
    input wire frame_commit,
    input wire [7:0] read_addr,
    output wire [7:0] read_data,
    output reg wave_ready
);
    reg [7:0] memory [0:511];
    reg write_bank, read_bank, pending;
    reg [7:0] write_addr, read_q;
    reg read_valid;
    wire write_en=rst_n && sample_valid && !pending;
    // 单时钟简单双口RAM模板；是否映射BSRAM以实际综合为准。
    always @(posedge pixel_clk) begin
        if (write_en) memory[{write_bank,write_addr}]<=sample_data;
        read_q<=memory[{read_bank,read_addr}];
    end
    assign read_data=read_valid ? read_q : 8'd0;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            write_bank<=1'b1; read_bank<=1'b0;
            write_addr<=0; pending<=1'b0;
            wave_ready<=1'b0; read_valid<=1'b0;
        end else begin
            read_valid<=wave_ready;
            if (write_en) begin
                if (write_addr==8'd255) pending<=1'b1;
                else write_addr<=write_addr+1'b1;
            end
            if (frame_commit && pending) begin
                read_bank<=write_bank;
                write_bank<=~write_bank;
                write_addr<=0;
                pending<=1'b0;
                wave_ready<=1'b1;
            end
        end
    end
endmodule
