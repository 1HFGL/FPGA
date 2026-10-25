`timescale 1ns/1ps
// 系统边界回归：保留真实48/50MHz信箱、解析器和触点所有权逻辑。
// 仅替代PLL输出及已校验USB报告入口；D+/D-由tb_touch_usb_wire另行验证。
module tb_usb_system_recovery;
    reg clk=0,usb_clk=0,rst=0,lock=0,connected=0,report=0;
    reg event_ready=1,cancel_ready=1;
    reg [415:0] packet=0;
    wire available,valid,on,guitar,cancel;
    wire [7:0] source;
    wire [6:0] note,velocity;
    tri dp,dm;
    integer events=0,cancels=0,epoch,n,saved_events,saved_cancels;
    reg [15:0] stalled_event;
    GSR GSR(.GSRI(1'b1));
    always #10 clk=~clk;
    always #10.416 usb_clk=~usb_clk;
    touch_usb_system dut(.sys_clk(clk),.sys_rst_n(rst),.core_ready(rst),
        .usb_dp(dp),.usb_dm(dm),.instrument_guitar(1'b0),.octave(2'd1),
        .available(available),.event_valid(valid),.event_ready(event_ready),
        .event_on(on),.event_guitar(guitar),.event_source(source),
        .event_note(note),.event_velocity(velocity),.cancel_valid(cancel),.cancel_ready(cancel_ready));
    always @(posedge clk)if(rst)begin
        if(valid && event_ready)begin
            if(!on || note!=60 || source!=8'h40 || guitar || velocity!=96)begin
                $display("FAIL USB recovery unexpected event");$finish;
            end
            events=events+1;
        end
        if(cancel && cancel_ready)cancels=cancels+1;
    end
    task settle;
        input integer clocks;
        begin repeat(clocks)@(negedge clk);end
    endtask
    task send;
        begin
            @(negedge usb_clk);while(!dut.ready_usb)@(negedge usb_clk);
            report=1;@(negedge usb_clk);report=0;
        end
    endtask
    initial begin
        force dut.usb_clk=usb_clk;
        force dut.locked=lock;
        force dut.connected_usb=connected;
        force dut.report_usb=report;
        force dut.data_usb=packet;
        // 原始坐标(256,3600)映射到(64,527)，稳定落在C4白键。
        packet[7:0]=1;packet[15:8]=1;packet[23:16]=17;
        packet[39:24]=256;packet[55:40]=3600;packet[415:408]=1;
        settle(5);rst=1;lock=1;
        for(epoch=0;epoch<4;epoch=epoch+1)begin
            connected=1;lock=1;settle(20);
            event_ready=0;cancel_ready=0;saved_events=events;saved_cancels=cancels;
            send;
            wait(valid);@(negedge clk);stalled_event={on,source,note};
            if(!available)begin $display("FAIL no valid-report availability");$finish;end
            // 分别模拟真实断线及PLL失锁；同步连接信号比源信箱晚两拍清零。
            if(epoch%2==0)connected=0;else lock=0;
            for(n=0;n<30;n=n+1)begin
                settle(1);
                if(!valid || {on,source,note}!==stalled_event || events!=saved_events)begin
                    $display("FAIL unstable stalled event across USB loss");$finish;
                end
            end
            if(available)begin $display("FAIL availability survived USB loss");$finish;end
            event_ready=1;wait(cancel);settle(20);
            if(!cancel || events!=saved_events+1 || cancels!=saved_cancels)begin
                $display("FAIL cancel ordering/backpressure");$finish;
            end
            cancel_ready=1;settle(20);
            if(cancels!=saved_cancels+1 || valid || cancel)begin
                $display("FAIL cancel not completed exactly once");$finish;
            end
            connected=0;settle(20);lock=1;connected=1;settle(40);
            if(valid || available)begin $display("FAIL stale report on reconnect");$finish;end
            send;wait(events==saved_events+2);settle(20);
            // 完整系统复位应丢弃旧所有权，下一轮重新从slot0起音。
            rst=0;connected=0;lock=0;settle(6);rst=1;settle(10);
            if(valid || cancel || available)begin $display("FAIL dirty system reset");$finish;end
        end
        $display("PASS tb_usb_system_recovery: 4 disconnect/PLL-loss epochs, real asymmetric mailbox resets, held events then cancellation, no stale reconnect notes");$finish;
    end
    initial begin #2000000;$display("FAIL USB system recovery timeout");$finish;end
endmodule
