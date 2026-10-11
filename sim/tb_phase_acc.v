`timescale 1ns/1ps

module tb_phase_acc;

    reg         clk;
    reg         rst;
    reg         sample_tick;
    reg  [31:0] phase_inc;
    wire [31:0] phase;
    wire [9:0]  wave_addr;
    integer     checks;

    // 实例化待测电路；点号后是电路端口，括号里是本测试平台的信号。
    phase_acc dut (
        .clk(clk),
        .rst(rst),
        .sample_tick(sample_tick),
        .phase_inc(phase_inc),
        .phase(phase),
        .wave_addr(wave_addr)
    );

    // 10 ns 周期的仿真时钟，即 100 MHz；不代表板卡实际时钟。
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // 每调用一次：下降沿设置输入，上升沿更新后检查输出。
    task step;
        input        test_rst;
        input        test_tick;
        input [31:0] test_inc;
        input [31:0] expected_phase;
        begin
            @(negedge clk);
            rst         = test_rst;
            sample_tick = test_tick;
            phase_inc   = test_inc;
            @(posedge clk);
            #1; // 等待非阻塞赋值和地址组合逻辑更新完成。
            if ((phase !== expected_phase) ||
                (wave_addr !== expected_phase[31:22])) begin
                $display("FAIL at %0t: phase=%h expected=%h addr=%d",
                         $time, phase, expected_phase, wave_addr);
                begin $display("FAIL: Phase accumulator check failed."); $finish; end
            end
            checks = checks + 1;
            $display("CHECK %0d: phase=%h addr=%0d",
                     checks, phase, wave_addr);
        end
    endtask

    initial begin
        rst = 1'b1;
        sample_tick = 1'b0;
        phase_inc = 32'd0;
        checks = 0;
        // Waveforms are controlled by the simulator runner.


        // 复位、加 5、暂停、继续。
        step(1, 0, 32'd5, 32'd0);
        step(0, 1, 32'd5, 32'd5);
        step(0, 1, 32'd5, 32'd10);
        step(0, 1, 32'd5, 32'd15);
        step(0, 0, 32'd5, 32'd15);
        step(0, 0, 32'd99, 32'd15);
        step(0, 1, 32'd5, 32'd20);

        // 运行中复位；复位优先于采样使能。
        step(1, 1, 32'h40000000, 32'd0);

        // 每次走四分之一圈：地址 256、512、768、0。
        step(0, 1, 32'h40000000, 32'h40000000);
        step(0, 1, 32'h40000000, 32'h80000000);
        step(0, 1, 32'h40000000, 32'hC0000000);
        step(0, 1, 32'h40000000, 32'h00000000);

        // 最大增量回绕，以及零增量保持。
        step(0, 1, 32'hFFFFFFFF, 32'hFFFFFFFF);
        step(0, 1, 32'd1, 32'd0);
        step(0, 1, 32'd0, 32'd0);

        $display("PASS: all %0d checks passed.", checks);
        $stop; // ModelSim 暂停，保留波形供观察。
    end

    // 测试异常时避免无限运行。
    initial begin
        #1000;
        begin $display("FAIL: Simulation timed out."); $finish; end
    end

endmodule
