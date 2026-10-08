`timescale 1ns/1ps
module tb_uart_flow;
    reg clk=0,rst=0,iv=0,orr=0,flush=0;
    reg [7:0] id=0;
    wire ir,ov; wire [7:0] od; wire [2:0] level;
    reg phy=0,pc=0,ar=0,cancel=0,sample=0,idle=1;
    wire pr,cr,av,at,ac,ack; wire [7:0] src; wire [6:0] note,vel;
    integer i,accepted=0;
    always #10 clk=~clk;
    uart_fifo #(.WIDTH(8),.ADDR_BITS(2)) fifo(.clk(clk),.rst_n(rst),.flush(flush),
        .in_valid(iv),.in_ready(ir),.in_data(id),.out_valid(ov),.out_ready(orr),.out_data(od),.level(level));
    uart_event_arbiter arb(.clk(clk),.rst_n(rst),.sample_request(sample),
        .physical_valid(phy),.physical_ready(pr),.physical_type(1'b1),.physical_source(8'd1),
        .physical_note(7'd64),.physical_velocity(7'd100),.pc_valid(pc),.pc_ready(cr),
        .pc_type(1'b1),.pc_note(7'd60),.pc_velocity(7'd99),.cancel_valid(cancel),.cancel_ready(ack),
        .allocator_cancel(ac),.allocator_cancel_ready(idle),.event_valid(av),.event_ready(ar),
        .event_type(at),.event_source(src),.event_note(note),.event_velocity(vel));
    initial begin
        repeat(4) @(negedge clk); rst=1;
        for(i=0;i<4;i=i+1) begin id=i; iv=1; @(negedge clk); end
        iv=0; if(level!=4 || ir || !ov || od!=0) $fatal(1,"full FIFO");
        repeat(5) @(negedge clk); if(od!=0) $fatal(1,"stalled FIFO changed");
        iv=1; id=4; orr=1; @(negedge clk); iv=0;
        if(level!=4 || od!=1) $fatal(1,"simultaneous full pop/push");
        for(i=1;i<5;i=i+1) begin if(od!=i) $fatal(1,"FIFO ordering"); @(negedge clk); end
        orr=0; if(ov || level!=0) $fatal(1,"empty FIFO");
        id=9; iv=1; @(negedge clk); iv=0; flush=1;
        #1; if(ov || ir) $fatal(1,"flush acceptance");
        @(negedge clk); flush=0; if(ov || level!=0) $fatal(1,"flush stale item");
        phy=1; ar=0; @(negedge clk);
        if(!av || src!=1 || pr || cr) $fatal(1,"phy stall");
        pc=1; repeat(3) @(negedge clk);
        if(src!=1 || note!=64) $fatal(1,"selected payload changed in stall");
        ar=1; #1; if(!pr || cr) $fatal(1,"ready went to wrong producer");
        @(negedge clk); #1; if(!cr || pr || src!=188) $fatal(1,"round robin PC");
        @(negedge clk); #1; if(!pr || cr) $fatal(1,"round robin phy");
        cancel=1; idle=0; sample=1; #1;
        if(av || pr || cr || ack || ac) $fatal(1,"cancel while allocator busy");
        @(negedge clk); idle=1; sample=0; #1; if(ack || ac) $fatal(1,"cancel outside sample boundary");
        @(negedge clk); sample=1; #1; if(!ack || !ac || av) $fatal(1,"cancel handshake");
        @(negedge clk); cancel=0; sample=0; phy=0;
        #1; if(!av || !cr || src!=188) $fatal(1,"post-cancel recovery");
        $display("PASS tb_uart_flow: FIFO full/empty/stall/flush and arbiter fairness/cancel"); $finish;
    end
    initial begin #30000; $fatal(1,"flow timeout"); end
endmodule
