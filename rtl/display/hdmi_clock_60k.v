// GW5AT-60B：50MHz -> VCO 1225MHz -> 串行245MHz/像素49MHz，同源相位关系。
// 参数依据UG306 PLLA：50/2*49=1225；输出分别除5/25，处于60K VCO范围700..1400MHz。
// 1024x600普通CVT候选：1312*624总像素，实际59.851Hz；不是精确60.000Hz。
module hdmi_clock_60k(
    input wire sys_clk,rst_n,
    output wire pixel_clk,serial_clk,locked
);
    PLLA #(.FCLKIN("50"),.IDIV_SEL(2),.FBDIV_SEL(1),.MDIV_SEL(49),
        .MDIV_FRAC_SEL(0),.ODIV0_SEL(5),.ODIV1_SEL(25),
        .CLKOUT0_EN("TRUE"),.CLKOUT1_EN("TRUE"),.CLKFB_SEL("INTERNAL")) u_pll(
        .CLKIN(sys_clk),.RESET(!rst_n),.LOCK(locked),.CLKOUT0(serial_clk),.CLKOUT1(pixel_clk),
        .CLKOUT2(),.CLKOUT3(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKFBOUT(),.MDRDO(),
        .CLKFB(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .PSSEL(3'd0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),.SSCON(1'b0),
        .SSCMDSEL(7'd0),.SSCMDSEL_FRAC(3'd0),.MDCLK(1'b0),.MDOPC(2'd0),.MDAINC(1'b0),.MDWDI(8'd0));
endmodule
