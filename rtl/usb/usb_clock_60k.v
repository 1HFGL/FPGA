// GW5AT-60B: 50MHz /1 *24 =1200MHz VCO, /25 =48MHz USB full-speed oversampling.
module usb_clock_60k(input wire sys_clk,rst_n,output wire usb_clk,locked);
 PLLA #(.FCLKIN("50"),.IDIV_SEL(1),.FBDIV_SEL(1),.MDIV_SEL(24),
  .MDIV_FRAC_SEL(0),.ODIV0_SEL(25),.CLKOUT0_EN("TRUE"),.CLKFB_SEL("INTERNAL")) u_pll(
  .CLKIN(sys_clk),.RESET(!rst_n),.LOCK(locked),.CLKOUT0(usb_clk),.CLKOUT1(),
  .CLKOUT2(),.CLKOUT3(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKFBOUT(),.MDRDO(),
  .CLKFB(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
  .PSSEL(3'd0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),.SSCON(1'b0),
  .SSCMDSEL(7'd0),.SSCMDSEL_FRAC(3'd0),.MDCLK(1'b0),.MDOPC(2'd0),.MDAINC(1'b0),.MDWDI(8'd0));
endmodule
