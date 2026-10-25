`timescale 1ns/1ps
// 三路同步输出延后一拍；在四种USB位相位和停钟状态检查异步复位放开总线。
module tb_usb_port_outputs;
    reg clk=0,clock_on=1,rst_n=0;
    always #5 if(clock_on)clk=~clk;
    tri dp,dm;
    reg reset_bus=0,disable_tx=1,d=0,n=0;
    reg expected_drive,expected_dp,expected_dm;
    integer k,phase,checks=0;
    touch_usb_port dut(.clk(clk),.rst_n(rst_n),.usb_dp(dp),.usb_dm(dm),.report_ready(1'b0));
    initial begin
        force dut.bus_reset=reset_bus;force dut.oe=disable_tx;
        force dut.dp_out=d;force dut.dm_out=n;
        #1;#10;rst_n=1;
        for(k=0;k<256;k=k+1)begin
            @(negedge clk);reset_bus=k%7==0;disable_tx=k%5==0;d=k%2;n=(k/2)%2;
            expected_drive=reset_bus || !disable_tx;
            expected_dp=reset_bus?1'b0:d;expected_dm=reset_bus?1'b0:n;
            @(posedge clk);#1;
            if(dp!==(expected_drive?expected_dp:1'bz) || dm!==(expected_drive?expected_dm:1'bz))begin
                $display("FAIL USB data/enable pipeline k=%0d",k);$finish;
            end
            checks=checks+1;
        end
        for(phase=0;phase<4;phase=phase+1)begin
            @(negedge clk);reset_bus=0;disable_tx=0;d=1;n=0;
            @(posedge clk);#1;
            #(phase+1);rst_n=0;#1;
            if(dp!==1'bz || dm!==1'bz)begin $display("FAIL USB asynchronous high impedance");$finish;end
            @(negedge clk);clock_on=0;rst_n=1;#31;
            if(dp!==1'bz || dm!==1'bz)begin $display("FAIL USB output while clock stopped");$finish;end
            disable_tx=1;clock_on=1;repeat(2)@(posedge clk);#1;
            if(dp!==1'bz || dm!==1'bz)begin $display("FAIL USB release without transmit");$finish;end
        end
        $display("PASS tb_usb_port_outputs: %0d data/enable combinations, four reset phases, clock-stop high impedance",checks);$finish;
    end
endmodule
