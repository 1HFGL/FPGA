// One confirmed full-speed host port. External board pulldowns supply bus bias.
// USB reset affects only this stack. Data outputs are disabled during FPGA reset.
module touch_usb_port #(parameter integer SEPARATE_PIN_CLOCK=0)(
 input wire clk,rst_n,
 inout wire usb_dp,usb_dm,
 output wire connected,report_valid,input wire report_ready,
 output wire [415:0] report_data,
 output wire [7:0] debug_state,
 output wire [1:0] debug_line,
 output wire [31:0] debug_detail,
 input wire pin_clk
);
 wire bus_reset,link_enable;
 wire cv,cr,ct,done,error,tick,txvalid,txready,rv,ra,re,oe,dp_out,dm_out;
 wire [7:0] cp,response,td,rd;wire [6:0] ca,cl;wire [3:0] ce;
 wire [63:0] cb;wire [15:0] count;wire [511:0] payload;
 wire [1:0] phy_line;
 wire phy_rst_n=rst_n && !bus_reset;
 // 数据与使能统一寄存到引脚边界，切断高扇出复位经组合逻辑直达IO的长路径。
 // 三个信号一起延后一个48MHz周期，保持USB位宽/数据与使能的相对时刻。
 // 异步复位仍立即释放总线，即使时钟停止也不会持续驱动D+/D-。
 reg pin_drive,pin_dp,pin_dm;
 // This is a static parameter choice, not a runtime clock mux.
 // The selected pin clock is a related, equal-phase 48MHz PLL output.
 wire output_clk = SEPARATE_PIN_CLOCK ? pin_clk : clk;
 always @(posedge output_clk or negedge rst_n)begin
  if(!rst_n)begin pin_drive<=0;pin_dp<=0;pin_dm<=0;end
  else begin pin_drive<=bus_reset || !oe;pin_dp<=bus_reset?1'b0:dp_out;pin_dm<=bus_reset?1'b0:dm_out;end
 end
 assign usb_dp=pin_drive?pin_dp:1'bz;
 assign usb_dm=pin_drive?pin_dm:1'bz;
 // Observe the bus even while the PHY is held in reset; the controller suppresses
 // detach classification during its own reset interval.
 reg [1:0] line_meta,line_sync;
 reg [3:0] tx_history;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin line_meta<=0;line_sync<=0;tx_history<=0;end
  else begin
   line_meta<={usb_dm,usb_dp};line_sync<=line_meta;
   tx_history<={tx_history[2:0],!oe};
  end
 end
 assign debug_line=line_sync;
 assign debug_detail={response,count[7:0],4'd0,error,bus_reset,link_enable,connected,debug_state};
 touch_usb_host u_host(.clk(clk),.rst_n(rst_n),.line_state(line_sync),
  .host_transmitting(!oe || |tx_history),
  .bus_reset(bus_reset),.link_enable(link_enable),.connected(connected),
  .report_valid(report_valid),.report_ready(report_ready),.report_data(report_data),.debug_state(debug_state),
  .command_valid(cv),.command_ready(cr),.command_pid(cp),.command_address(ca),.command_endpoint(ce),
  .command_toggle(ct),.command_length(cl),.command_payload(cb),.link_frame_tick(tick),
  .transaction_done(done),.transaction_error(error),.response(response),.received_length(count),.received_payload(payload));
 touch_usb_link u_link(.clk(clk),.rst_n(rst_n),.enabled(link_enable),
  .command_valid(cv),.command_ready(cr),.command_pid(cp),.command_address(ca),.command_endpoint(ce),
  .command_toggle(ct),.command_length(cl),.command_payload(cb),.done(done),.error(error),.response(response),
  .received_length(count),.received_payload(payload),.frame_tick(tick),
  .utmi_rx_data(rd),.utmi_rxvalid(rv),.utmi_rxactive(ra),.utmi_rxerror(re),.utmi_txready(txready),
  .utmi_linestate(phy_line),.utmi_tx_data(td),.utmi_txvalid(txvalid));
 usb_fs_phy u_phy(.clk_i(clk),.rstn_i(phy_rst_n),.utmi_data_out_i(td),.utmi_txvalid_i(txvalid && link_enable),
  .utmi_op_mode_i(2'd0),.utmi_xcvrselect_i(2'd1),.utmi_termselect_i(1'b0),
  .utmi_dppulldown_i(1'b1),.utmi_dmpulldown_i(1'b1),
  .usb_rx_rcv_i(usb_dp && !usb_dm),.usb_rx_dp_i(usb_dp),.usb_rx_dn_i(usb_dm),.usb_reset_assert_i(1'b0),
  .utmi_data_in_o(rd),.utmi_txready_o(txready),.utmi_rxvalid_o(rv),.utmi_rxactive_o(ra),
  .utmi_rxerror_o(re),.utmi_linestate_o(phy_line),.usb_tx_dp_o(dp_out),.usb_tx_dn_o(dm_out),.usb_tx_oen_o(oe),
  .usb_reset_detect_o(),.usb_en_o());
endmodule
