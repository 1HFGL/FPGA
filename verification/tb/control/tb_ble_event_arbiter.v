`timescale 1ns/1ps
// 固定种子LFSR背压、三路全负载、稳定队头、两种取消源及复位。
module tb_ble_event_arbiter;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    reg pv=1,cv=1,bv=1,pc_cancel=0,ble_cancel=0;
    reg [6:0] pn=0,cn=0,bn=0;
    reg [15:0] random_state=16'hb10c;
    reg ready=0,sample_request=0;
    wire pr,cr,br,pcr,bcr,ac,valid,kind;
    wire [8:0] source,mask,value;
    wire [6:0] note,velocity;
    uart_event_arbiter #(.ENABLE_BLE(1)) dut(.clk(clk),.rst_n(rst_n),.sample_request(sample_request),
        .physical_valid(pv),.physical_ready(pr),.physical_type(1'b1),.physical_source(8'd2),
        .physical_note(pn),.physical_velocity(7'd100),.pc_valid(cv),.pc_ready(cr),
        .pc_type(1'b1),.pc_note(cn),.pc_velocity(7'd100),.cancel_valid(pc_cancel),.cancel_ready(pcr),
        .allocator_cancel(ac),.allocator_cancel_ready(1'b1),.event_valid(valid),.event_ready(ready),
        .event_type(kind),.event_source(source),.event_note(note),.event_velocity(velocity),
        .ble_valid(bv),.ble_ready(br),.ble_type(1'b1),.ble_note(bn),.ble_velocity(7'd100),
        .ble_cancel_valid(ble_cancel),.ble_cancel_ready(bcr),.allocator_cancel_mask(mask),.allocator_cancel_value(value));
    integer i,pa=0,ca=0,ba=0,pc_cleared=0,ble_cleared=0;
    reg stalled=0,took_p=0,took_c=0,took_b=0;
    reg [24:0] payload;
    always @(posedge clk)if(rst_n)begin
        took_p=pr;took_c=cr;took_b=br;
        if(stalled && !pc_cancel && !ble_cancel && (!valid || {kind,source,note,velocity}!==payload))begin
            $display("FAIL BLE arbiter stalled payload changed");$stop;end
        stalled=valid && !ready && !pc_cancel && !ble_cancel;
        payload={kind,source,note,velocity};
        if(valid && ready)begin
            if((pr+cr+br)!=1)begin $display("FAIL BLE arbiter multiple ready");$stop;end
            if(pr)begin if(source!==9'd2 || note!==pa[6:0])begin $display("FAIL BLE physical tag/order");$stop;end pa=pa+1;end
            if(cr)begin if(source!=={2'b10,cn} || note!==ca[6:0])begin $display("FAIL BLE PC tag/order");$stop;end ca=ca+1;end
            if(br)begin if(source!=={2'b11,bn} || note!==ba[6:0])begin $display("FAIL BLE tag/order");$stop;end ba=ba+1;end
        end
        if(ac)begin
            if(!sample_request || mask!==9'h180 || valid)begin $display("FAIL BLE cancel boundary/mask");$stop;end
            if(pcr)begin pc_cleared=pc_cleared+1;if(value!==9'h100)begin $display("FAIL BLE PC cancel tag");$stop;end end
            if(bcr)begin ble_cleared=ble_cleared+1;if(value!==9'h180)begin $display("FAIL BLE cancel tag");$stop;end end
        end
    end
    initial begin
        repeat(10)@(negedge clk);rst_n=1;
        for(i=0;i<3000;i=i+1)begin
            @(negedge clk);
            // 仅被接受的生产者推进队头，不人为违反ready/valid。
            if(took_p)pn=pn+1'b1;if(took_c)cn=cn+1'b1;if(took_b)bn=bn+1'b1;
            random_state={random_state[14:0],random_state[15]^random_state[13]^random_state[12]^random_state[10]};
            ready=random_state[0];sample_request=(i%7)==0;
        end
        @(negedge clk);pc_cancel=1;ble_cancel=1;ready=0;sample_request=0;
        repeat(5)@(negedge clk);
        if(pc_cleared || ble_cleared)begin $display("FAIL BLE premature cancel");$stop;end
        sample_request=1;
        while(pc_cleared==0 || ble_cleared==0)begin
            @(negedge clk);
            if(pc_cleared)pc_cancel=0;if(ble_cleared)ble_cancel=0;
        end
        if(pa<400 || ca<400 || ba<400 || pa-ca>1 || ca-ba>1 || ba-pa>1)begin
            $display("FAIL BLE fairness %0d/%0d/%0d",pa,ca,ba);$stop;end
        rst_n=0;repeat(5)@(negedge clk);
        $display("PASS tb_ble_event_arbiter: 3000 cycles fixed seed b10c; stable stalls; fair 3-source traffic %0d/%0d/%0d; isolated boundary cancellation",pa,ca,ba);$finish;
    end
    initial begin #1000000;$display("FAIL BLE arbiter timeout");$stop;end
endmodule
