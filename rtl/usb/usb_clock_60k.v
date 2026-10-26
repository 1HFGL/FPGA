// The two 48MHz outputs use the same VCO/divider ratio and zero phase.
// CLKOUT0 serves the USB core; CLKOUT1 serves only the three pin registers.
// Both remain related clocks in STA; no crossing is exempted.
// GW5AT-60B: 50MHz /1 *24 =1200MHz VCO, /25 =48MHz USB full-speed oversampling.
module usb_clock_60k(input wire sys_clk,rst_n,output wire usb_clk,locked,usb_pin_clk);
 PLLA #(.FCLKIN("50"),.IDIV_SEL(1),.FBDIV_SEL(1),.MDIV_SEL(24),
  .MDIV_FRAC_SEL(0),.ODIV0_SEL(25),.ODIV1_SEL(25),.CLKOUT0_EN("TRUE"),.CLKOUT1_EN("TRUE"),.CLKFB_SEL("INTERNAL")) u_pll(
  .CLKIN(sys_clk),.RESET(!rst_n),.LOCK(locked),.CLKOUT0(usb_clk),.CLKOUT1(usb_pin_clk),
  .CLKOUT2(),.CLKOUT3(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKFBOUT(),.MDRDO(),
  .CLKFB(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
  .PSSEL(3'd0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),.SSCON(1'b0),
  .SSCMDSEL(7'd0),.SSCMDSEL_FRAC(3'd0),.MDCLK(1'b0),.MDOPC(2'd0),.MDAINC(1'b0),.MDWDI(8'd0));
endmodule
