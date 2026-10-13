`timescale 1ns/1ps
module tb_display_timing;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    wire [11:0] x,y,x1,y1;
    wire de,hs,vs,fs,fc,de1,hs1,vs1;
    lcd_rgb_timing #(.H_ACTIVE(8),.H_FRONT(2),.H_SYNC(3),.H_BACK(1),
        .V_ACTIVE(4),.V_FRONT(1),.V_SYNC(2),.V_BACK(1)) dut (
        .pixel_clk(clk),.rst_n(rst_n),.x(x),.y(y),.de(de),.hsync(hs),.vsync(vs),
        .frame_start(fs),.frame_commit(fc));
    lcd_rgb_timing #(.H_ACTIVE(8),.H_FRONT(2),.H_SYNC(3),.H_BACK(1),
        .V_ACTIVE(4),.V_FRONT(1),.V_SYNC(2),.V_BACK(1),.HS_ACTIVE(1),.VS_ACTIVE(1)) positive (
        .pixel_clk(clk),.rst_n(rst_n),.x(x1),.y(y1),.de(de1),.hsync(hs1),.vsync(vs1),
        .frame_start(),.frame_commit());
    integer ex,ey,i,count;
    task check;
        begin
            if(x!==ex || y!==ey || de!==(ex<8 && ey<4) ||
               hs!==!(ex>=10 && ex<13) || vs!==!(ey>=5 && ey<7) ||
               fs!==(ex==0 && ey==0) || fc!==(ex==13 && ey==7) ||
               x1!==x || y1!==y || de1!==de || hs1!==~hs || vs1!==~vs) begin
                $display("FAIL timing expected %0d,%0d got %0d,%0d",ex,ey,x,y); $finish;
            end
            if(de) count=count+1;
        end
    endtask
    initial begin
        #2;
        if(de!==0 || hs!==1 || vs!==1) begin $display("FAIL reset blank"); $finish; end
        @(negedge clk); rst_n=1; ex=0;ey=0;count=0;
        for(i=0;i<336;i=i+1) begin
            #1; check;
            @(posedge clk);
            if(ex==13) begin ex=0; if(ey==7) ey=0;else ey=ey+1;end else ex=ex+1;
            @(negedge clk);
        end
        if(count!=96) begin $display("FAIL active area %0d",count);$finish;end
        repeat(19) @(negedge clk);
        rst_n=0; #1;
        if(x!==0 || y!==0 || de!==0) begin $display("FAIL mid-frame reset");$finish;end
        $display("PASS tb_display_timing: three frames, both polarities, porches, reset");$finish;
    end
    initial begin #100000; $display("FAIL timing timeout");$finish;end
endmodule
