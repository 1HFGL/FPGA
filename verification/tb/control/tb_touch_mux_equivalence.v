`timescale 1ns/1ps
// 固定Git原版逐周期对照；不同槽数、重排/滑奏、背压、断连/坏包和异步复位。
module touch_mux_case #(parameter integer N=6)(output reg done=0);
    reg clk=0,rst_n=0,connected=1,error=0,fv=0,mode=0;
    reg [1:0] octave=1;
    reg [N-1:0] active=0;
    reg [N*8-1:0] ids=0;
    reg [N*12-1:0] xs=0,ys=0;
    reg er=0,cr=0,ar=0;
    wire fr,ev,eon,eg,cv,ca,fault;
    wire ofr,oev,oeon,oeg,ocv,oca,ofault;
    wire [7:0] src,mask,value,osrc,omask,ovalue;
    wire [6:0] note,velocity,onote,ovelocity;
    wire [1:0] kind,control,okind,ocontrol;
    always #10 clk=~clk;
    touch_contact_tracker #(.CONTACTS(N)) dut(.clk(clk),.rst_n(rst_n),.connected(connected),.stream_error(error),
        .frame_valid(fv),.frame_ready(fr),.contact_active(active),.contact_id(ids),.contact_x(xs),.contact_y(ys),
        .instrument_guitar(mode),.octave(octave),.event_valid(ev),.event_ready(er),.event_on(eon),
        .event_source(src),.event_note(note),.event_velocity(velocity),.event_guitar(eg),
        .control_valid(cv),.control_ready(cr),.control_kind(kind),.control_value(control),
        .cancel_valid(ca),.cancel_ready(ar),.cancel_mask(mask),.cancel_value(value),.fault(fault));
    touch_contact_tracker_reference #(.CONTACTS(N)) reference(.clk(clk),.rst_n(rst_n),.connected(connected),.stream_error(error),
        .frame_valid(fv),.frame_ready(ofr),.contact_active(active),.contact_id(ids),.contact_x(xs),.contact_y(ys),
        .instrument_guitar(mode),.octave(octave),.event_valid(oev),.event_ready(er),.event_on(oeon),
        .event_source(osrc),.event_note(onote),.event_velocity(ovelocity),.event_guitar(oeg),
        .control_valid(ocv),.control_ready(cr),.control_kind(okind),.control_value(ocontrol),
        .cancel_valid(oca),.cancel_ready(ar),.cancel_mask(omask),.cancel_value(ovalue),.fault(ofault));
    integer cycle=0,events=0,controls=0,cancels=0,frames=0,phase=0,k,round,slot;
    reg accepted=0;
    reg [31:0] random_state=32'hb6e87a91;
    always @(posedge clk)begin
        if(rst_n)begin
            if(ev && er)events=events+1;
            if(cv && cr)controls=controls+1;
            if(ca && ar)cancels=cancels+1;
            if(fv && fr)begin frames=frames+1;accepted=1;end
        end
        #1;
        if(rst_n && ({fr,ev,cv,ca,fault}!=={ofr,oev,ocv,oca,ofault} ||
           (ev && {eon,src,note,velocity,eg}!=={oeon,osrc,onote,ovelocity,oeg}) ||
           (cv && {kind,control}!=={okind,ocontrol}) ||
           (ca && {mask,value}!=={omask,ovalue})))begin
            $display("FAIL touch mux N=%0d cycle=%0d state=%0d old=%0d slot=%0d",
                     N,cycle,dut.state,reference.state,dut.index);$stop;
        end
    end
    task make_frame;
        input integer number;
        integer t,logical;
        begin
            mode=(number/11)%2;octave=(number/7)%4;
            for(t=0;t<N;t=t+1)begin
                logical=(t+number)%N;
                active[t]=((number%9)==0)?1'b0:((number%3)==0 || ((logical+number)%4)!=0);
                ids[t*8+:8]=logical+1;
                xs[t*12+:12]=32+((logical*137+number*29)%960);
                ys[t*12+:12]=mode?550:520;
                if(number%17==0)begin xs[t*12+:12]=900;ys[t*12+:12]=40;end
                if(number%19==0)begin xs[t*12+:12]=940;ys[t*12+:12]=110;end
                if(number%23==0)begin xs[t*12+:12]=4095;ys[t*12+:12]=4095;end
            end
            // 完整重复ID快照必须取消；N=1没有成对ID，不强行构造。
            if(N>1 && number%29==0)
                for(t=0;t<N;t=t+1)if(t<2)begin ids[t*8+:8]=8'd1;active[t]=1;end
        end
    endtask
    initial begin
        #1;rst_n=1;#1;rst_n=0;
        repeat(4)@(negedge clk);rst_n=1;
        for(cycle=0;cycle<60000;cycle=cycle+1)begin
            @(negedge clk);
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            er=random_state[0] || random_state[6];cr=random_state[2];ar=random_state[4];
            connected=(cycle%4000>=31);error=(cycle%1709==1650);
            if(fv && phase && accepted)begin fv=0;phase=0;accepted=0;end
            else if(!fv && fr && random_state[8])begin
                make_frame(round);round=round+1;fv=1;phase=1;accepted=0;
            end
            if(cycle==30000)begin
                #3;rst_n=0;#1;
                if(ev || cv || ca || fault)begin $display("FAIL touch mux async reset N=%0d",N);$stop;end
                #3;rst_n=1;fv=0;phase=0;accepted=0;
            end
        end
        connected=1;error=0;fv=0;er=1;cr=1;ar=1;
        repeat(200)@(negedge clk);
        if(events<100 || frames<100 || cancels<10 || controls<1)begin
            $display("FAIL touch mux coverage N=%0d events=%0d frames=%0d cancels=%0d controls=%0d",
                     N,events,frames,cancels,controls);$stop;
        end
        $display("PASS touch mux case N=%0d cycles=%0d frames=%0d events=%0d controls=%0d cancels=%0d",N,cycle,frames,events,controls,cancels);
        done=1;
    end
    initial begin round=1;end
endmodule
module tb_touch_mux_equivalence;
    wire d1,d5,d6,d15;
    touch_mux_case #(.N(1)) n1(d1);
    touch_mux_case #(.N(5)) n5(d5);
    touch_mux_case #(.N(6)) n6(d6);
    touch_mux_case #(.N(15)) n15(d15);
    initial begin
        wait(d1 && d5 && d6 && d15);
        $display("PASS tb_touch_mux_equivalence: four parameter sets, 240000 cycles, exact event/control/cancel timing and reset");$finish;
    end
    initial begin #2000000;$display("FAIL touch mux timeout");$stop;end
endmodule
