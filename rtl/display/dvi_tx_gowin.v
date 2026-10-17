// Tang Mega 60K的DVI模式视频发送：HDMI物理插口、RGB888、无音频/HDCP/数据岛。
// serial_clk必须与pixel_clk同源且严格5倍；禁止用独立振荡器或逻辑计数器代替。
// OSER10以双沿发送10位，TLVDS_OBUF/板载匹配网络参考Sipeed cam_dvi例程。
module dvi_tx_gowin(
    input wire pixel_clk,serial_clk,rst_n,
    input wire [23:0] rgb,
    input wire de,hsync,vsync,
    output wire [2:0] tmds_data_p,tmds_data_n,
    output wire tmds_clk_p,tmds_clk_n
);
    wire [39:0] symbols;
    assign symbols[39:30]=10'b1111100000;
    tmds_encoder u_blue(.pixel_clk(pixel_clk),.rst_n(rst_n),.data(rgb[7:0]),
        .de(de),.control({vsync,hsync}),.symbol(symbols[9:0]));
    tmds_encoder u_green(.pixel_clk(pixel_clk),.rst_n(rst_n),.data(rgb[15:8]),
        .de(de),.control(2'b00),.symbol(symbols[19:10]));
    tmds_encoder u_red(.pixel_clk(pixel_clk),.rst_n(rst_n),.data(rgb[23:16]),
        .de(de),.control(2'b00),.symbol(symbols[29:20]));
    wire [3:0] serial_data,positive,negative;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin:g_lane
        // 像素域下降沿两拍释放，不为复位引入245MHz普通逻辑负载。
        // 两级都就绪才撤销复位，异步断言时两级同时清零；每通道局部保留。
        // 双状态合并保留真实门级；hdmi_reset_placement.cst将FF/LUT限定在各自I/O旁。
        // 不能只追求最短线：必须同时检查恢复(最大延迟)与移除(最小延迟)。
        // 增加的20.408ns仅影响显示启动，不改变音频R7；仿真不替代布局布线STA。
        reg [1:0] serializer_release /* synthesis syn_preserve=1 */;
        always @(negedge pixel_clk or negedge rst_n)
            if(!rst_n) serializer_release<=2'b00;
            else serializer_release<={serializer_release[0],1'b1};
        wire serializer_reset /* synthesis syn_keep=1 */;
        LUT2 #(.INIT(4'b0111)) u_reset_combine(.I0(serializer_release[0]),
            .I1(serializer_release[1]),.F(serializer_reset));
        OSER10 u_serializer(.D0(symbols[lane*10]),.D1(symbols[lane*10+1]),
            .D2(symbols[lane*10+2]),.D3(symbols[lane*10+3]),.D4(symbols[lane*10+4]),
            .D5(symbols[lane*10+5]),.D6(symbols[lane*10+6]),.D7(symbols[lane*10+7]),
            .D8(symbols[lane*10+8]),.D9(symbols[lane*10+9]),
            .PCLK(pixel_clk),.FCLK(serial_clk),.RESET(serializer_reset),.Q(serial_data[lane]));
        TLVDS_OBUF u_diff(.I(serial_data[lane]),.O(positive[lane]),.OB(negative[lane]));
    end endgenerate
    assign tmds_data_p=positive[2:0];assign tmds_data_n=negative[2:0];
    assign tmds_clk_p=positive[3];assign tmds_clk_n=negative[3];
endmodule
