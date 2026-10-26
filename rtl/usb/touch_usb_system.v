// USB domain -> whole-report mailbox -> six-contact events in the audio domain.
// USB/PLL loss clears only the mailbox and requests touch-source cancellation;
// the tracker itself resets with the audio core so it cannot lose held ownership.
module touch_usb_system #(parameter integer ENABLE_CONTROLS=0)(
    input wire sys_clk, sys_rst_n, core_ready,
    inout wire usb_dp, usb_dm,
    input wire instrument_guitar, input wire [1:0] octave,
    output wire available,
    output wire event_valid, input wire event_ready,
    output wire event_on, event_guitar,
    output wire [7:0] event_source,
    output wire [6:0] event_note, event_velocity,
    output wire cancel_valid, input wire cancel_ready,
 output wire control_valid,input wire control_ready,
 output wire [3:0] control_kind,output wire [1:0] control_value
);
    // 48MHz USB域只负责线级收发；52字节报告经原子信箱跨到50MHz音频域。
    wire usb_clk, usb_pin_clk, locked;
    usb_clock_60k u_clock(
        .sys_clk(sys_clk),
        .rst_n(sys_rst_n),
        .usb_clk(usb_clk),
        .usb_pin_clk(usb_pin_clk),
        .locked(locked)
    );
    wire usb_reset_condition = sys_rst_n && core_ready && locked;
    reg [1:0] usb_release;
    always @(posedge usb_clk or negedge usb_reset_condition)
        if (!usb_reset_condition) usb_release <= 0;
        else usb_release <= {usb_release[0], 1'b1};
    wire connected_usb, report_usb, ready_usb;
    wire [415:0] data_usb, data_sys;
    touch_usb_port #(.SEPARATE_PIN_CLOCK(1)) u_port(
        .clk(usb_clk),
        .pin_clk(usb_pin_clk),
        .rst_n(usb_release[1]),
        .usb_dp(usb_dp),
        .usb_dm(usb_dm),
        .connected(connected_usb),
        .report_valid(report_usb),
        .report_ready(ready_usb),
        .report_data(data_usb),
        .debug_state(),
        .debug_line(),
        .debug_detail()
    );
    reg connected_meta, connected_sys;
    always @(posedge sys_clk or negedge core_ready) begin
        if (!core_ready) begin
            connected_meta <= 0;
            connected_sys <= 0;
        end
        else begin
            connected_meta <= connected_usb && locked;
            connected_sys <= connected_meta;
        end
    end
    // 信箱随USB连接清空；触点所有权仅随core_ready复位，靠cancel握手清理断连。
    wire mailbox_src_reset = usb_release[1] && connected_usb;
    wire mailbox_dst_reset = core_ready && connected_sys;
    wire report_sys, ready_sys, mail_ready;
    assign ready_usb = mailbox_src_reset && mail_ready;
    touch_report_cdc u_reports(
        .src_clk(usb_clk),
        .src_rst_n(mailbox_src_reset),
        .src_valid(report_usb),
        .src_data(data_usb),
        .src_ready(mail_ready),
        .dst_clk(sys_clk),
        .dst_rst_n(mailbox_dst_reset),
        .dst_ready(ready_sys),
        .dst_valid(report_sys),
        .dst_data(data_sys)
    );
    wire frame_valid, frame_ready, stream_error;
    wire [5:0] active;
    wire [47:0] ids;
    wire [71:0] xs, ys;
    touch_report_decode u_decode(
        .clk(sys_clk),
        .rst_n(core_ready),
        .connected(connected_sys),
        .report_valid(report_sys),
        .report_ready(ready_sys),
        .report_data(data_sys),
        .frame_valid(frame_valid),
        .frame_ready(frame_ready),
        .contact_active(active),
        .contact_id(ids),
        .contact_x(xs),
        .contact_y(ys),
        .stream_error(stream_error)
    );
    reg seen_frame;
    always @(posedge sys_clk or negedge core_ready) begin
        if (!core_ready) seen_frame <= 0;
        else if (!connected_sys || stream_error) seen_frame <= 0;
        else if (frame_valid && frame_ready) seen_frame <= 1;
    end
    assign available = connected_sys && seen_frame;
    // 当前只接音符和来源取消；control_*握手后丢弃，屏幕模式/音区/延音尚未接通。
    touch_contact_tracker #(
        .CONTACTS(6),.CONTROL_WIDTH(4),.EXTENDED_CONTROLS(ENABLE_CONTROLS)) u_contacts(
        .clk(sys_clk),
        .rst_n(core_ready),
        .connected(connected_sys),
        .stream_error(stream_error),
        .frame_valid(frame_valid),
        .frame_ready(frame_ready),
        .contact_active(active),
        .contact_id(ids),
        .contact_x(xs),
        .contact_y(ys),
        .instrument_guitar(instrument_guitar),
        .octave(octave),
        .event_valid(event_valid),
        .event_ready(event_ready),
        .event_on(event_on),
        .event_source(event_source),
        .event_note(event_note),
        .event_velocity(event_velocity),
        .event_guitar(event_guitar),
        .control_valid(control_valid),
        .control_ready(ENABLE_CONTROLS?control_ready:1'b1),
        .control_kind(control_kind),
        .control_value(control_value),
        .cancel_valid(cancel_valid),
        .cancel_ready(cancel_ready),
        .cancel_mask(),
        .cancel_value(),
        .fault()
    );
endmodule
