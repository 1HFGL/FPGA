`timescale 1ns/1ps
module tb_display_cdc;
    reg sc=0,dc=0,rst_n=0,run_dst=1,valid=0;
    reg [31:0] data=0;
    wire ready,dvalid;
    wire [31:0] received;
    always #5 sc=~sc;
    always #17 if(run_dst) dc=~dc;
    display_cdc_latest #(.WIDTH(32)) dut(.src_clk(sc),.src_rst_n(rst_n),.src_valid(valid),
        .src_data(data),.src_ready(ready),.dst_clk(dc),.dst_rst_n(rst_n),.dst_valid(dvalid),.dst_data(received));
    reg [31:0] queue[0:1023];
    integer sent=0,got=0,rejected=0,i;
    always @(posedge sc) if(rst_n && valid) begin
        if(ready) begin queue[sent]=data; sent=sent+1;end
        else rejected=rejected+1;
    end
    always @(posedge dc) begin
        #1;
        if(rst_n && dvalid) begin
            if(got>=sent || received!==queue[got]) begin
                $display("FAIL CDC atomic/order got=%h expected=%h",received,queue[got]);$finish;
            end
            got=got+1;
        end
    end
    initial begin
        #41; rst_n=1;
        for(i=0;i<500;i=i+1) begin
            @(negedge sc); valid=1; data={i[15:0],~i[15:0]};
        end
        @(negedge sc);valid=0;
        #500;
        if(sent!=got || got<10 || rejected==0) begin $display("FAIL CDC totals");$finish;end
        // 目的时钟停止后只允许一个未完成信箱，不让源端忙等或覆盖数据。
        @(negedge dc);run_dst=0;
        @(negedge sc);valid=1;data=32'ha5a55a5a;
        repeat(10) @(negedge sc);
        valid=0;
        if(ready!==0) begin $display("FAIL stopped destination backpressure");$finish;end
        // 有未确认数据时共同复位，旧数据应被丢弃，不得在恢复后产生幽灵事务。
        rst_n=0;#40;sent=0;got=0;run_dst=1;
        #80;rst_n=1;
        #150;
        if(dvalid!==0 || got!=0) begin $display("FAIL CDC stale reset transaction");$finish;end
        @(negedge sc);valid=1;data=32'h13572468;
        @(negedge sc);valid=0;
        #500;
        if(sent!=1 || got!=1) begin $display("FAIL CDC restart");$finish;end
        $display("PASS tb_display_cdc: atomicity, order, busy drop, clock stop, reset");$finish;
    end
    initial begin #200000; $display("FAIL CDC timeout");$finish;end
endmodule
