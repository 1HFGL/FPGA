`timescale 1ns/1ps
// 独立整数模型：不实例化另一份 instrument_env 作为参考，避免双方同错。
// 覆盖接受拍改变预设、连续采样、短段/非二次幂/长计数、释放与复位。
module tb_final_env_alignment;
    reg clk=0;
    always #10 clk=~clk;
    wire [4:0] done;
    wire [31:0] c0,c1,c2,c3,c4;
    env_alignment_case #(.ID(0),.GA(16),.GD(1),.GS(65536),.GR(2048),
        .SA(64),.SD(1),.SS(65536),.SR(4096)) a(clk,done[0],c0);
    env_alignment_case #(.ID(1),.GA(5),.GD(7),.GS(12000),.GR(3),
        .SA(9),.SD(11),.SS(43001),.SR(13)) b(clk,done[1],c1);
    env_alignment_case #(.ID(2),.GA(0),.GD(1),.GS(0),.GR(0),
        .SA(1),.SD(0),.SS(65536),.SR(1)) c(clk,done[2],c2);
    env_alignment_case #(.ID(3),.GA(2),.GD(2),.GS(65535),.GR(2),
        .SA(3),.SD(3),.SS(1),.SR(3)) d(clk,done[3],c3);
    env_alignment_case #(.ID(4),.GA(65537),.GD(3),.GS(65536),.GR(65539),
        .SA(7),.SD(5),.SS(70000),.SR(11)) e(clk,done[4],c4);
    initial begin
        wait(&done);
        $display("PASS tb_final_env_alignment: %0d independent integer checks; current preset, consecutive ticks, odd/zero/long durations, reset",c0+c1+c2+c3+c4);
        $finish;
    end
    initial begin #20000000;$display("FAIL env alignment timeout");$finish;end
endmodule

module env_alignment_case #(
    parameter integer ID=0, GA=16, GD=1, GS=65536, GR=2048,
    parameter integer SA=64, SD=1, SS=65536, SR=4096
)(input wire clk, output reg done=0, output reg [31:0] checks=0);
    reg rst=1,tick=0,gate=0,note_on=0,preset=0;
    wire [16:0] level;
    wire active;
    wire [2:0] state;
    instrument_env #(.G_ATTACK(GA),.G_DECAY(GD),.G_SUSTAIN(GS),.G_RELEASE(GR),
        .S_ATTACK(SA),.S_DECAY(SD),.S_SUSTAIN(SS),.S_RELEASE(SR)) dut(
        .clk(clk),.rst(rst),.sample_tick(tick),.gate(gate),.note_on(note_on),
        .instrument(preset),.env_level(level),.active(active),.state(state));
    integer m_level=0,m_state=0,m_left=0,m_step=0,m_rem=0,m_error=0;
    integer an,dn,rn,sc,nstate,distance,duration,total;
    integer i,p;
    reg start;
    task step;
        input r,t,g,on,inst;
        begin
            @(negedge clk);rst=r;tick=t;gate=g;note_on=on;preset=inst;
            if(r)begin
                m_level=0;m_state=0;m_left=0;m_step=0;m_rem=0;m_error=0;
            end else if(t)begin
                an=inst?SA:GA;if(an==0)an=1;
                dn=inst?SD:GD;if(dn==0)dn=1;
                rn=inst?SR:GR;if(rn==0)rn=1;
                sc=inst?SS:GS;if(sc>65536)sc=65536;
                nstate=m_state;start=0;
                if(!g)begin
                    if(m_level==0)nstate=0;
                    else if(m_state!=4)begin nstate=4;start=1;end
                end else if(on)begin nstate=1;start=1;end
                else if(m_state==2 && m_left==0)start=1;
                if(start)begin
                    case(nstate)
                        1:begin distance=65536-m_level;duration=an;end
                        2:begin distance=65536-sc;duration=dn;end
                        4:begin distance=m_level;duration=rn;end
                        default:begin distance=0;duration=1;end
                    endcase
                    m_step=distance/duration;m_rem=distance%duration;
                    m_error=m_rem;m_left=duration-1;
                    if(nstate==1)m_level=m_level+m_step;
                    else if(nstate==2)m_level=65536-m_step;
                    else if(nstate==4)m_level=m_level-m_step;
                    if(duration==1)begin
                        m_error=0;
                        case(nstate)
                            1:begin m_level=65536;nstate=2;end
                            2:begin m_level=sc;nstate=3;end
                            4:begin m_level=0;nstate=0;end
                            default:begin end
                        endcase
                    end
                end else if(nstate==1 || nstate==2 || nstate==4)begin
                    if(m_left<=1)begin
                        m_left=0;m_error=0;
                        case(nstate)
                            1:begin m_level=65536;nstate=2;end
                            2:begin m_level=sc;nstate=3;end
                            4:begin m_level=0;nstate=0;end
                            default:begin end
                        endcase
                    end else begin
                        duration=(m_state==1)?an:((m_state==2)?dn:rn);
                        // 与原合同一致：每拍最多补一格；不假定测试输入永远锁定预设。
                        total=m_error+m_rem;m_error=(total>=duration)?total-duration:total;m_left=m_left-1;
                        if(nstate==1)m_level=m_level+m_step+(total>=duration);
                        else m_level=m_level-m_step-(total>=duration);
                    end
                end else begin
                    m_level=(nstate==3)?sc:0;m_left=0;m_error=0;m_step=0;m_rem=0;
                end
                m_state=nstate;
            end
            @(posedge clk);#1;
            if(level!==m_level || state!==m_state || active!==(m_state!=0))begin
                $display("FAIL env current preset case=%0d check=%0d rst/tick/gate/on/preset=%b%b%b%b%b expected=%0d/%0d actual=%0d/%0d",ID,checks,r,t,g,on,inst,m_level,m_state,level,state);
                $finish;
            end
            checks=checks+1;
        end
    endtask
    initial begin
        step(1,0,0,0,0);step(0,0,0,0,0);step(0,0,0,0,0);
        // 相邻采样拍重触发时切预设：任何“上一拍计算结果”都会在这里暴露。
        step(0,1,1,1,0);
        step(0,1,1,1,1);
        step(0,1,1,1,0);
        step(0,1,0,0,0);
        step(0,1,1,1,1);
        step(1,0,1,1,1);
        for(p=0;p<2;p=p+1)begin
            step(1,0,0,0,p[0]);step(0,0,0,0,p[0]);
            step(0,1,1,1,p[0]);
            for(i=0;i<(p?SA:GA)+(p?SD:GD)+5;i=i+1)step(0,1,1,0,p[0]);
            for(i=0;i<(p?SR:GR)+5;i=i+1)step(0,1,0,0,p[0]);
        end
        for(i=0;i<300;i=i+1)begin
            step((i==161),(i%7!=0),(i%23<18),(i%11==0),(i/13)%2);
        end
        done=1;
    end
endmodule
