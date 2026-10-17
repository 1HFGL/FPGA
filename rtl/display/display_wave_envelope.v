// 像素域实时波形：512个原始16位样本按两点取min/max，双页共2KiB。
// 发布时整页交换并锁定峰值/倍率，帧内不会读到正在写的页。
// 不清RAM，只清有效标志；等待换页时允许丢显示副本，绝不反压音频。
module display_wave_envelope(
    input wire pixel_clk,rst_n,sample_valid,frame_commit,
    input wire signed [15:0] sample_data,
    input wire [7:0] read_addr,
    output wire signed [15:0] read_min,read_max,
    output reg [15:0] peak_level,
    output reg [3:0] gain_shift,
    output reg wave_ready
);
    reg [31:0] memory[0:511];
    reg write_bank,read_bank,pending,half_full,read_valid;
    reg [7:0] write_addr;
    reg signed [15:0] first_sample;
    reg [15:0] page_peak,pending_peak;
    reg [31:0] read_q;
    reg [2:0] quiet_pages;
    wire write_sample=sample_valid && !pending && rst_n;
    wire [15:0] magnitude=sample_data[15]?(~sample_data+16'd1):sample_data;
    wire [15:0] next_peak=(magnitude>page_peak)?magnitude:page_peak;
    wire signed [15:0] pair_min=(sample_data<first_sample)?sample_data:first_sample;
    wire signed [15:0] pair_max=(sample_data>first_sample)?sample_data:first_sample;
    function [3:0] fit_shift;
        input [15:0] peak;
        integer i;
        reg [31:0] wide_peak;
        begin
            fit_shift=0;wide_peak={16'd0,peak};
            // 目标为满幅的75%；只用移位/比较，最大256倍，不引入除法/DSP。
            for(i=0;i<=8;i=i+1)
                if(peak!=0 && (wide_peak<<i)<=32'd24576)fit_shift=i[3:0];
        end
    endfunction
    wire [3:0] wanted_shift=fit_shift(pending_peak);
    always @(posedge pixel_clk)begin
        if(write_sample && half_full)memory[{write_bank,write_addr}]<={pair_min,pair_max};
        read_q<=memory[{read_bank,read_addr}];
    end
    assign read_min=read_valid?$signed(read_q[31:16]):16'sd0;
    assign read_max=read_valid?$signed(read_q[15:0]):16'sd0;
    always @(posedge pixel_clk or negedge rst_n)begin
        if(!rst_n)begin
            write_bank<=1;read_bank<=0;pending<=0;half_full<=0;read_valid<=0;
            write_addr<=0;first_sample<=0;page_peak<=0;pending_peak<=0;
            peak_level<=0;gain_shift<=0;quiet_pages<=0;wave_ready<=0;
        end else begin
            read_valid<=wave_ready;
            if(write_sample)begin
                page_peak<=next_peak;
                half_full<=~half_full;
                if(!half_full)first_sample<=sample_data;
                else if(write_addr==255)begin pending<=1;pending_peak<=next_peak;end
                else write_addr<=write_addr+1'b1;
            end
            if(frame_commit && pending)begin
                read_bank<=write_bank;write_bank<=~write_bank;
                write_addr<=0;half_full<=0;page_peak<=0;pending<=0;
                peak_level<=pending_peak;wave_ready<=1;
                if(wave_ready && pending_peak==0)begin
                    // 静音无可归一化的峰值，保持倍率并显示零线。
                    quiet_pages<=0;
                end else if(!wave_ready || wanted_shift<gain_shift)begin
                    gain_shift<=wanted_shift;quiet_pages<=0;
                end else if(pending_peak!=0 && wanted_shift>gain_shift)begin
                    if(quiet_pages==7)begin gain_shift<=gain_shift+1'b1;quiet_pages<=0;end
                    else quiet_pages<=quiet_pages+1'b1;
                end else quiet_pages<=0;
            end
        end
    end
endmodule
