`timescale 1ns/1ps
// 默认板级参数的数字延迟测量：起点是最后稳定键沿，终点是PT8211完整字。
// ref_dut 接收相同背景与PANIC，但不接收本次新增按键；背景非零不算新音响应。
// 本测试不包含机械接触、模拟DAC/功放、耳机可闻阈值或亚稳态的物理统计。
module tb_piano_latency;
    parameter integer REQUEST_LEAD_HALF_EDGES = 0;
    reg clk=0, rst=0, rx=1;
    reg [1:0] keys=3, ref_keys=3;
    wire bck,ws,din,pa,ref_bck,ref_ws,ref_din,ref_pa;
    instrument_uart_piano_top #(.REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES),
        .ROM_FILE("rtl/rom/piano_1024.mem")) dut(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(keys),.uart_rx(rx),.uart_tx(),
        .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa));
    instrument_uart_piano_top #(.REQUEST_LEAD_HALF_EDGES(REQUEST_LEAD_HALF_EDGES),
        .ROM_FILE("rtl/rom/piano_1024.mem")) ref_dut(
        .sys_clk(clk),.sys_rst_n(rst),.Key_in(ref_keys),.uart_rx(rx),.uart_tx(),
        .HP_BCK(ref_bck),.HP_WS(ref_ws),.HP_DIN(ref_din),.PA_EN(ref_pa));
    always #10 clk=~clk;

    integer cycle=0, frames=0, words=0, bits=0, request_at=0, total_words=0;
    integer case_id=0, case_count=0, csv, p, cancel_overlap=0, measured_frame=-1;
    integer request_count=0, case_request_count=0, samples_until_difference=0;
    integer golden_phase=0,golden_edge=0,golden_sum=0;
    reg golden_ce;
    reg [15:0] pending=0, ref_pending=0, received=0, ref_received=0;
    reg [15:0] expected[0:4095], ref_expected[0:4095];
    reg pending_valid=0, ref_pending_valid=0, armed=0;
    reg [255:0] case_name;
    reg [2047:0] csv_path;
    time t_raw=0,t_sync=0,t_stable=0,t_press=0,t_event=0,t_trigger=0;
    time t_request=0,t_pcm=0,t_cache=0,t_right=0,t_left=0;
    time bounce_ns=0, max_left=0, min_left=64'h7fffffffffffffff;

    task fail;
        input [1023:0] message;
        begin
            $display("FAIL tb_piano_latency lead=%0d case=%0d %s at %0t: %s",
                REQUEST_LEAD_HALF_EDGES,case_id,case_name,$time,message);
            $finish;
        end
    endtask

    // 在真实 frame_start 消费旧缓存，再接受同拍sample_valid。
    // 不能用请求时刻充当帧边界；因此同一记分板适用于旧/新策略。
    always @(posedge clk) begin
        cycle=cycle+1;
        if(!dut.u_core.audio_ready) begin
            frames=0; pending=0; ref_pending=0;
            pending_valid=0; ref_pending_valid=0; request_at=0; request_count=0;
            golden_phase=0;golden_edge=0;
        end else begin
            // 独立整数递推验证真实时钟使能；解析相位上界不能只假定RTL符合模型。
            golden_sum=golden_phase+3072000;golden_ce=(golden_sum>=50000000);
            if(dut.u_core.u_b.bclk_half_ce!==golden_ce ||
                dut.u_core.u_b.frame_start!==(golden_ce && golden_edge==0) ||
                dut.u_core.sample_request!==(golden_ce && golden_edge==
                    ((REQUEST_LEAD_HALF_EDGES==0)?0:64-REQUEST_LEAD_HALF_EDGES)))
                fail("48k phase model/request deadline mismatch");
            if(golden_ce) begin golden_phase=golden_sum-50000000;golden_edge=(golden_edge+1)%64;end
            else golden_phase=golden_sum;
            if(dut.u_core.sample_request !== ref_dut.u_core.sample_request ||
               dut.u_core.u_b.frame_start !== ref_dut.u_core.u_b.frame_start)
                fail("reference clock/request drift");
            if(dut.u_core.sample_request) begin
                request_at=cycle; request_count=request_count+1;
                if(armed && t_trigger!=0 && t_request==0) begin
                    t_request=$time; case_request_count=request_count;
                end
            end
            if(dut.u_core.u_b.frame_start) begin
                if(frames>=4096) fail("scoreboard overflow");
                expected[frames]=pending_valid ? pending : 16'd0;
                ref_expected[frames]=ref_pending_valid ? ref_pending : 16'd0;
                if(frames>0 && (!pending_valid || !ref_pending_valid)) fail("normal frame underrun");
                frames=frames+1; pending_valid=0; ref_pending_valid=0;
            end
            if(dut.u_core.sample_valid) begin
                if(cycle-request_at!=4 || dut.u_core.sample_clipped!==0)
                    fail("request to cache must be R4 without clipping");
                if(^dut.u_core.sample_data===1'bx) fail("unknown PCM word");
                pending=dut.u_core.sample_data; pending_valid=1;
                if(armed && t_pcm!=0 && t_cache==0) t_cache=$time;
            end
            if(ref_dut.u_core.sample_valid) begin
                ref_pending=ref_dut.u_core.sample_data; ref_pending_valid=1;
            end
            if(armed && dut.u_core.pv && dut.u_core.pr && dut.u_core.pt &&
                dut.u_core.ps==0 && t_event==0) t_event=$time;
            if(armed && dut.u_core.cancel && dut.u_core.pv) cancel_overlap=cancel_overlap+1;
        end
        // 在NBA后记录实际可见的寄存输出，不将R3有效错误地记成R4接收。
        #1;
        if(rst && armed) begin
            if(!dut.u_core.u_keys.g_key[0].u_debounce.sync_q && t_sync==0) t_sync=$time-1;
            if(dut.u_core.u_keys.g_key[0].u_debounce.stable && t_stable==0) t_stable=$time-1;
            if(dut.u_core.key_press[0] && t_press==0) t_press=$time-1;
            for(p=0;p<4;p=p+1)
                if(dut.u_core.voice_trigger[p] && dut.u_core.voice_source_flat[p*8 +: 8]==0 &&
                    t_trigger==0) t_trigger=$time-1;
            if(dut.u_core.sample_valid &&
                dut.u_core.sample_data !== ref_dut.u_core.sample_data && t_pcm==0) begin
                if(t_request==0) fail("differential response before target request");
                t_pcm=$time-1;
                samples_until_difference=request_count-case_request_count+1;
            end
        end
    end

    always @(posedge bck or negedge rst) begin
        if(!rst) begin words=0;bits=0;received=0;ref_received=0; end
        else if(dut.u_core.audio_ready) begin
            if(bck!==ref_bck || ws!==ref_ws || ws!==(words%2)) fail("serial clocks/channel drift");
            if(dut.u_core.sample_underrun!==(words<2)) fail("unexpected underrun");
            received={received[14:0],din}; ref_received={ref_received[14:0],ref_din};
            bits=bits+1;
            if(bits==16) begin
                if(received!==expected[words/2] || ref_received!==ref_expected[words/2])
                    fail("serial word does not match frame-consumed sample");
                if(armed && received!==ref_received) begin
                    if(t_pcm==0) fail("serial difference without PCM difference");
                    if(words%2==0 && t_right==0) begin t_right=$time;measured_frame=words/2; end
                    if(words%2==1 && words/2==measured_frame && t_left==0) t_left=$time;
                end
                words=words+1;total_words=total_words+1;bits=0;
            end
        end
    end

    task wait_cycles;
        input integer count;
        begin repeat(count) @(negedge clk); end
    endtask
    task send_text;
        input [2047:0] text;
        integer len,j,k;
        reg [7:0] byte_value;
        begin
            len=0;
            for(j=0;j<256;j=j+1) if(text[j*8 +: 8]!=0) len=j+1;
            for(j=len-1;j>=0;j=j-1) begin
                byte_value=text[j*8 +: 8];
                @(negedge clk);rx=0;wait_cycles(434);
                for(k=0;k<8;k=k+1) begin rx=byte_value[k];wait_cycles(434);end
                rx=1;wait_cycles(434);
            end
            wait_cycles(20);
        end
    endtask
    task reset_case;
        begin
            @(negedge clk);armed=0;rst=0;keys=3;ref_keys=3;rx=1;
            wait_cycles(8);rst=1;wait_cycles(4000);
            if(dut.u_core.voice_count!=0 || ref_dut.u_core.voice_count!=0 || pa!==1)
                fail("reset did not clear prior voices");
        end
    endtask
    task phase_align;
        input integer offset;
        begin
            @(posedge clk);
            while(!dut.u_core.sample_request) @(posedge clk);
            @(negedge clk);wait_cycles(offset);
        end
    endtask
    task begin_measure;
        input [255:0] name;
        begin
            case_name=name; t_raw=$time;t_sync=0;t_stable=0;t_press=0;t_event=0;
            t_trigger=0;t_request=0;t_pcm=0;t_cache=0;t_right=0;t_left=0;
            measured_frame=-1;samples_until_difference=0;cancel_overlap=0;
            armed=1; keys[0]=0;
        end
    endtask
    task end_measure;
        integer watchdog;
        time elapsed;
        begin
            watchdog=0;
            while(t_left==0 && watchdog<260000) begin @(negedge clk);watchdog=watchdog+1;end
            if(t_left==0) fail("no correlated left word within local digital bound");
            if(t_sync-t_raw!=30 || t_stable-t_raw!=2000030 || t_press-t_stable!=20)
                fail("real 100000-cycle debounce stage changed");
            if(t_event<t_press || t_trigger-t_event!=100 || t_request<=t_trigger ||
                t_pcm<t_request+60 || t_cache-t_pcm!=20 || t_right<t_cache || t_left-t_right<10400)
                fail("stage order/pipeline contract violated");
            elapsed=t_left-t_raw;
            if(elapsed>max_left) max_left=elapsed;
            if(elapsed<min_left) min_left=elapsed;
            $fdisplay(csv,"%0d,%0d,%0s,%0t,%0t,%0t,%0t,%0t,%0t,%0t,%0t,%0t,%0t,%0t,%0d,%0d,%0t",
                REQUEST_LEAD_HALF_EDGES,case_id,case_name,t_raw,t_sync,t_stable,t_press,t_event,
                t_trigger,t_request,t_pcm,t_cache,t_right,t_left,samples_until_difference,cancel_overlap,bounce_ns);
            $display("LATENCY lead=%0d case=%0d name=%0s sync=%0d stable=%0d event=%0d trigger=%0d request=%0d pcm=%0d cache=%0d right=%0d left=%0d ns samples=%0d cancel_overlap=%0d",
                REQUEST_LEAD_HALF_EDGES,case_id,case_name,t_sync-t_raw,t_stable-t_raw,t_event-t_raw,
                t_trigger-t_raw,t_request-t_raw,t_pcm-t_raw,t_cache-t_raw,t_right-t_raw,t_left-t_raw,
                samples_until_difference,cancel_overlap);
            armed=0;case_count=case_count+1;case_id=case_id+1;bounce_ns=0;
        end
    endtask
    task add_background;
        input integer count;
        begin
            send_text("HELLO\n"); wait_cycles(1000);
            send_text("NOTE_ON 67 100 0\n");
            if(count>1) begin
                send_text("NOTE_ON 69 100 0\n");send_text("NOTE_ON 72 100 0\n");send_text("NOTE_ON 76 100 0\n");
            end
            wait_cycles(4000);
            if(dut.u_core.voice_count!=count || ref_dut.u_core.voice_count!=count)
                fail("background setup failed");
        end
    endtask

    initial begin
        $timeformat(-9,0,"",0); // CSV时间单位固定ns，不随默认%t精度变成ps。
        if(dut.DEBOUNCE_CYCLES!=100000 || dut.UART_CLKS_PER_BIT!=434 ||
            dut.u_core.ATTACK_SAMPLES!=96 || dut.u_core.DECAY_SAMPLES!=57600 ||
            dut.u_core.SUSTAIN_LEVEL!=0 || dut.u_core.RELEASE_SAMPLES!=8640)
            fail("test must use default board debounce, baud and original piano ADSR");
        if(!$value$plusargs("CSV=%s",csv_path)) csv_path="build/piano_latency.csv";
        csv=$fopen(csv_path,"w");if(csv==0) fail("cannot open CSV");
        $fdisplay(csv,"lead,case_id,name,raw_ns,sync_ns,stable_ns,press_ns,event_ns,trigger_ns,request_ns,pcm_ns,cache_ns,right_ns,left_ns,samples_to_difference,cancel_overlap_cycles,bounce_ns");
        // 3125系统周期=3个音频帧。零相位和各截止点邻域，完整枚举在包装脚本中。
        reset_case;phase_align(0);begin_measure("first_phase_0");end_measure;
        reset_case;phase_align(1030);begin_measure("first_before_cutoff");end_measure;
        reset_case;phase_align(1031);begin_measure("first_at_cutoff");end_measure;
        reset_case;phase_align(1032);begin_measure("first_after_cutoff");end_measure;
        reset_case;phase_align(2073);begin_measure("first_second_frame");end_measure;
        reset_case;phase_align(3114);begin_measure("first_third_frame");end_measure;
        reset_case;add_background(1);phase_align(1031);begin_measure("background_new_note");end_measure;
        reset_case;add_background(4);phase_align(1031);begin_measure("full_four_voice_steal");end_measure;
        if(dut.u_core.voice_count!=4 || dut.u_core.steal_count!=1) fail("full occupancy did not steal one slot");
        reset_case;keys=2;ref_keys=2;wait_cycles(150000);keys=3;ref_keys=3;wait_cycles(150000);
        if(dut.u_core.voice_gate!=0 || dut.u_core.voice_count==0) fail("retrigger setup must retain release tail");
        phase_align(1031);begin_measure("retrigger_during_tail");end_measure;
        reset_case;add_background(4);phase_align(1031);begin_measure("panic_key_competition");
        // PANIC真实434拍/位；在实体事件生成附近到达，检查取消实际阻塞了实体队头。
        wait_cycles(74080);send_text("PANIC\n");end_measure;
        if(cancel_overlap==0) fail("PANIC competition stimulus missed physical queue overlap");
        for(p=0;p<4;p=p+1)
            if(dut.u_core.voice_source_flat[p*8+7] && dut.u_core.voice_gate[p])
                fail("PANIC left a PC gate held");
        reset_case;add_background(1);phase_align(0);begin_measure("panic_near_full_frame_wait");
        // 让PANIC刚好错过上一请求，再由实体队头等待下一请求，不能只测5拍轻负载。
        wait_cycles(74166);send_text("PANIC\n");end_measure;
        if(cancel_overlap<900) fail("worst-wait PANIC did not hold the physical queue for near one frame");
        reset_case;
        keys=2;wait_cycles(500);keys=3;wait_cycles(300);keys=2;wait_cycles(900);keys=3;wait_cycles(400);
        if(dut.u_core.voice_count!=0 || dut.u_core.key_press!=0) fail("bounce caused premature note");
        bounce_ns=42000;begin_measure("bounce_last_stable_edge");end_measure;
        reset_case;phase_align(1031);begin_measure("two_physical_keys");keys=0;end_measure;
        wait_cycles(20);if(dut.u_core.voice_count!=2) fail("second simultaneous physical key missing");
        // 中途复位必须冲掉测量前的旧样本，随后重新验证一次完整新音。
        @(negedge clk);rst=0;#1;if(pa!==1) fail("reset must immediately disable PA");
        reset_case;phase_align(1032);begin_measure("post_reset_first_note");end_measure;
        $fclose(csv);
        $display("PASS tb_piano_latency lead=%0d cases=%0d words=%0d min_left_ns=%0d max_left_ns=%0d; digital-only threshold=1LSB default_debounce=100000 ADSR=96/57600/0/8640",
            REQUEST_LEAD_HALF_EDGES,case_count,total_words,min_left,max_left);
        $finish;
    end
    initial begin #200000000;fail("global timeout");end
endmodule
