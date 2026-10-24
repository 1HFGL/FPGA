`timescale 1ns/1ps
// 名义50MHz、真实转换等待；采集起点锁存模拟输入，包含错过一次转换的情况。
// 只验证数字参数链，不能替代滑条电气接线及DAC模拟总延迟测量。
module tb_slider_controls;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    tri1 sda;
    wire scl,valid,ready,fault,bvalid,bready,request;
    wire [13:0] knobs;
    wire [6:0] brightness;
    wire [16:0] gain;
    wire [17:0] bend;
    reg [6:0] current=127;
    ads1115_knob_if #(.ENABLE_BRIGHTNESS(1)) dut(
        .clk(clk),.rst_n(rst_n),.sda(sda),.scl(scl),.knob_value_flat(knobs),
        .knob_sample_valid(valid),.param_ready(ready),.param_fault(fault),
        .brightness_value(brightness),.brightness_valid(bvalid),.brightness_ready(bready));
    slider_adc_model adc(.scl(scl),.sda(sda));
    sample_tick #(.AUDIO_CLK_HZ(50000000),.REQUEST_LEAD_HALF_EDGES(60)) tick(.clk_audio(clk),.rst_n(rst_n),
        .bclk_half_ce(),.frame_start(),.sample_prepare(request));
    piano_controls control(.clk(clk),.rst_n(rst_n),.sample_request(request),
        .knob_value_flat(knobs),.knob_valid(valid),.param_ready(ready),.param_fault(fault),
        .master_gain(gain),.bend_ratio(bend));
    always @(posedge clk)begin
        if(!rst_n)current<=127;
        else if(request)begin
            if(current<brightness)current<=current+1'b1;
            else if(current>brightness)current<=current-1'b1;
        end
    end
    time maximum=0,begun,elapsed;
    integer cases=0,n,starts;
    reg previous_valid=0,previous_bvalid=0;
    always @(negedge clk)begin
        if(rst_n && ((valid && previous_valid) || (bvalid && previous_bvalid)))begin
            $display("FAIL slider valid pulse width");$stop;end
        previous_valid=valid;previous_bvalid=bvalid;
    end
    task settle;
        input [16:0] eg;
        input [17:0] eb;
        input [6:0] el;
        input integer limit;
        begin
            begun=$time;
            while(!ready || !bready || fault || gain!==eg || bend!==eb || current!==el)begin
                @(negedge clk);
                if($time-begun>limit)begin
                    $display("FAIL slider settle gain=%d bend=%d bright=%d ready=%b/%b fault=%b",gain,bend,current,ready,bready,fault);$stop;end
            end
            elapsed=$time-begun;
            if(limit==10000000)begin
                cases=cases+1;
                if(elapsed>maximum)maximum=elapsed;
                $display("SLIDER case=%0d latency_ns=%0d",cases,elapsed);
            end
        end
    endtask
    initial begin
        repeat(10)@(negedge clk);rst_n=1;
        if(brightness!==127 || bready)begin $display("FAIL slider neutral startup");$stop;end
        settle(65536,65536,127,30000000);
        // 三路各自独立变化：音量/弯音固定时滑条不应改它们。
        for(n=0;n<6;n=n+1)begin
            starts=adc.starts2;wait(adc.starts2!=starts);#1;
            adc.input2=(n[0])?26400:0;
            settle(65536,65536,n[0]?127:0,10000000);
        end
        // 不同相位同时改变三个通道，检查两旋钮在三路轮询下仍及时发布。
        for(n=0;n<6;n=n+1)begin
            starts=adc.starts0;wait(adc.starts0!=starts);#(n*300000+1);
            adc.input0=n[0]?26400:0;adc.input1=n[0]?26400:0;adc.input2=n[0]?0:26400;
            settle(n[0]?65536:0,n[0]?73562:58386,n[0]?0:127,10000000);
        end
        // 断连不发布半个坏字；明亮度回中性，两旋钮保持最后有效值。
        adc.connected=0;wait(fault);repeat(200000)@(negedge clk);
        if(brightness!==127 || gain!==65536 || bend!==73562 || ready)begin $display("FAIL slider fault policy");$stop;end
        adc.input0=26400;adc.input1=13200;adc.input2=13200;adc.connected=1;
        settle(65536,65536,64,30000000);
        // 仅复位FPGA而ADC转换继续，不允许下一次转换过早启动。
        wait(adc.busy);#100;rst_n=0;repeat(10)@(negedge clk);
        if(brightness!==127 || bready || ready)begin $display("FAIL slider reset");$stop;end
        rst_n=1;settle(65536,65536,64,30000000);
        if(cases!=12 || adc.starts2<15)begin $display("FAIL slider coverage");$stop;end
        $display("PASS tb_slider_controls: 12 real-time phase cases max_settled_ns=%0d; 3 channels independent/fault/recovery/reset",maximum);$finish;
    end
    initial begin #250000000;$display("FAIL slider timeout");$stop;end
endmodule

// 独立三路ADS1115验证从机：只支持本工程使用的单次860SPS配置。
// 非产品RTL；旧双路模型和队友TB保持不变。
module slider_adc_model(input wire scl,inout wire sda);
    reg connected=1;
    reg [15:0] input0=26400,input1=13200,input2=26400;
    reg drive_low=0,active=0,sending=0,accepted=0,busy=0;
    assign sda=(connected && drive_low)?1'b0:1'bz;
    reg [1:0] phase=0;
    integer bit_count=0,send_count=0,starts0=0,starts1=0,starts2=0;
    reg [7:0] shift=0,pointer=0;
    reg [15:0] config_word=0,out_shift=0,captured=0,result=0;
    event conversion_start;
    always @(conversion_start)begin busy=1;#1350000;result=captured;busy=0;end
    always @(negedge sda)if(scl)begin
        active<=1;sending<=0;phase<=0;bit_count<=0;shift<=0;drive_low<=0;send_count<=0;
    end
    always @(posedge sda)if(scl)begin active<=0;sending<=0;drive_low<=0;end
    always @(posedge scl)if(active && !sending)begin
        if(bit_count<8)shift<={shift[6:0],sda};
        bit_count<=bit_count+1;
    end
    always @(negedge scl)begin
        if(!active)drive_low<=0;
        else if(sending)begin
            if(send_count<8 || (send_count>=9 && send_count<17))begin
                drive_low<=!out_shift[15];out_shift<={out_shift[14:0],1'b0};send_count<=send_count+1;
            end else if(send_count==8)begin drive_low<=0;send_count<=9;end
            else drive_low<=0;
        end else if(bit_count==8)begin
            accepted=connected && (phase!=0 || shift[7:1]==7'h48);drive_low<=accepted;
        end else if(bit_count==9)begin
            drive_low<=0;bit_count<=0;
            if(!accepted)active<=0;
            else case(phase)
                0:if(shift[0])begin
                    if(pointer!=0 || busy)begin $display("FAIL slider read before ADC ready");$stop;end
                    out_shift<={result[14:0],1'b0};drive_low<=!result[15];sending<=1;send_count<=1;
                end else phase<=1;
                1:begin pointer<=shift;phase<=2;end
                2:begin config_word[15:8]<=shift;phase<=3;end
                3:begin
                    config_word[7:0]=shift;phase<=0;
                    if(pointer!=1 || config_word[11:9]!=1 || !config_word[8] || !config_word[15] ||
                        config_word[7:5]!=7 || config_word[14:12]<4 || config_word[14:12]>6 || busy)begin
                        $display("FAIL slider ADC config %h busy=%b",config_word,busy);$stop;end
                    case(config_word[14:12])
                        4:begin captured=input0;starts0=starts0+1;end
                        5:begin captured=input1;starts1=starts1+1;end
                        6:begin captured=input2;starts2=starts2+1;end
                        default:begin $display("FAIL slider mux");$stop;end
                    endcase
                    ->conversion_start;
                end
                default:phase<=0;
            endcase
        end else drive_low<=0;
    end
endmodule
