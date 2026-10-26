`timescale 1ns/1ps
// Compare the four complete serializer lanes against a frozen pre-change source.
// Exact phase/reset checks complement the independent PLL/recovery scoreboard.
module tb_serializer_reset_equivalence;
    reg serial_clk=0,pixel_clk=0,clock_running=1,rst_n=0;
    reg [23:0] rgb=0;
    reg de=0,hsync=0,vsync=0;
    integer half_count=0,checks=0,epochs=0,n,phase;
    reg [31:0] sequence=32'h65b1c027;
    GSR GSR(.GSRI(1'b1));
    always #2.041 if(clock_running)serial_clk=~serial_clk;
    always @(serial_clk)begin
        if(half_count==4)begin half_count=0;pixel_clk=~pixel_clk;end
        else half_count=half_count+1;
    end
    always @(negedge pixel_clk)begin
        sequence={sequence[30:0],sequence[31]^sequence[21]^sequence[1]^sequence[0]};
        rgb=sequence[23:0];de=sequence[24];hsync=sequence[25];vsync=sequence[26];
    end
    wire [2:0] dp,dn,rp,rn;
    wire cp,cn,rcp,rcn;
    dvi_tx_gowin dut(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst_n(rst_n),
        .rgb(rgb),.de(de),.hsync(hsync),.vsync(vsync),
        .tmds_data_p(dp),.tmds_data_n(dn),.tmds_clk_p(cp),.tmds_clk_n(cn));
    dvi_tx_gowin_reference reference(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst_n(rst_n),
        .rgb(rgb),.de(de),.hsync(hsync),.vsync(vsync),
        .tmds_data_p(rp),.tmds_data_n(rn),.tmds_clk_p(rcp),.tmds_clk_n(rcn));
    wire [3:0] resets={dut.g_lane[3].u_serializer.RESET,dut.g_lane[2].u_serializer.RESET,
        dut.g_lane[1].u_serializer.RESET,dut.g_lane[0].u_serializer.RESET};
    wire [3:0] reference_resets={reference.g_lane[3].u_serializer.RESET,reference.g_lane[2].u_serializer.RESET,
        reference.g_lane[1].u_serializer.RESET,reference.g_lane[0].u_serializer.RESET};
    reg [1:0] release_model=0;
    always @(negedge pixel_clk or negedge rst_n)
        if(!rst_n)release_model<=0;
        else release_model<={release_model[0],1'b1};
    // A fixed-time checker also observes stopped clocks and short async pulses.
    initial begin
        #1;
        forever begin
            #0.5;
            if(resets!==reference_resets || resets!=={4{!release_model[1]}})begin
                $display("FAIL serializer reset equivalence epoch=%0d resets=%b reference=%b model=%b",epochs,resets,reference_resets,release_model);
                $finish;
            end
            if({cp,cn,dp,dn}!=={rcp,rcn,rp,rn})begin
                $display("FAIL serializer serial equivalence epoch=%0d",epochs);$finish;
            end
            if(dut.symbols!==reference.symbols)begin
                $display("FAIL serializer symbol equivalence epoch=%0d",epochs);$finish;
            end
            checks=checks+1;
        end
    end
    initial begin
        // Force a definite assertion event, independent of simulator time-zero ordering.
        #0.1;rst_n=1;#0.1;rst_n=0;#7.1;rst_n=1;
        repeat(20)@(negedge pixel_clk);
        for(n=0;n<300;n=n+1)begin
            phase=n%10;
            @(posedge pixel_clk);repeat(phase)@(serial_clk);#0.17;
            rst_n=0;epochs=epochs+1;
            if(n%7==0)clock_running=0;
            #(3.3+(n%13));
            if(resets!==4'hf)begin $display("FAIL serializer asynchronous reset");$finish;end
            rst_n=1;
            if(n%7==0)begin
                #23.7;
                if(resets!==4'hf)begin $display("FAIL serializer stopped clock release");$finish;end
                clock_running=1;
            end
            if(n%11==0)begin #2.1;rst_n=0;#4.9;rst_n=1;end
            repeat(18)@(negedge pixel_clk);
            if(resets!==4'h0)begin $display("FAIL serializer release timeout");$finish;end
        end
        if(epochs!=300 || checks<200000)begin $display("FAIL serializer coverage");$finish;end
        $display("PASS tb_serializer_reset_equivalence: %0d epochs, %0d exact reset/symbol/serial checks, ten phases, bounce and stopped clocks",epochs,checks);
        $finish;
    end
    initial begin #300000;$display("FAIL serializer test timeout");$finish;end
endmodule
