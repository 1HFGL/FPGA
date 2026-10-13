// 通用逐行扫描；默认只是 800x480 仿真模板，不是任何已选屏幕的时序承诺。
// 一行顺序：有效像素 -> 前肩 -> 同步 -> 后肩；一帧同理。pixel_clk 必须来自外部时钟/PLL。
// 12 位计数器支持总长 1..4096，H/V_ACTIVE、SYNC 必须 >=1，肩宽允许为0。
module lcd_rgb_timing #(
    parameter integer H_ACTIVE=800, H_FRONT=40, H_SYNC=128, H_BACK=88,
    parameter integer V_ACTIVE=480, V_FRONT=13, V_SYNC=2, V_BACK=30,
    parameter integer HS_ACTIVE=0, VS_ACTIVE=0
) (
    input wire pixel_clk, rst_n,
    output reg [11:0] x, y,
    output wire de, hsync, vsync,
    output wire frame_start, frame_commit
);
    localparam integer H_TOTAL=H_ACTIVE+H_FRONT+H_SYNC+H_BACK;
    localparam integer V_TOTAL=V_ACTIVE+V_FRONT+V_SYNC+V_BACK;
    wire hs_window=(x>=H_ACTIVE+H_FRONT && x<H_ACTIVE+H_FRONT+H_SYNC);
    wire vs_window=(y>=V_ACTIVE+V_FRONT && y<V_ACTIVE+V_FRONT+V_SYNC);
    assign de=rst_n && x<H_ACTIVE && y<V_ACTIVE;
    assign hsync=(rst_n && hs_window) ? (HS_ACTIVE!=0) : (HS_ACTIVE==0);
    assign vsync=(rst_n && vs_window) ? (VS_ACTIVE!=0) : (VS_ACTIVE==0);
    assign frame_start=rst_n && x==0 && y==0;
    // 在最后一个消隐像素的采样沿换状态，下一帧从第一个像素起使用新快照。
    assign frame_commit=rst_n && x==H_TOTAL-1 && y==V_TOTAL-1;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin x<=0; y<=0; end
        else if (x==H_TOTAL-1) begin
            x<=0;
            if (y==V_TOTAL-1) y<=0;
            else y<=y+1'b1;
        end else x<=x+1'b1;
    end
endmodule
