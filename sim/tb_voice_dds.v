`timescale 1ns/1fs

module tb_voice_dds;
    // Simulation-only clock: nominal 12 MHz / 250 = 48 kHz.
    // Femtosecond precision makes clock-period rounding negligible.
    localparam integer SAMPLE_DIV = 250;
    localparam integer FS_HZ = 48000;
    localparam integer TONE_SAMPLES = 2400; // 50 ms per tone.
    localparam [31:0] INC_440 = 32'd39370534;
    localparam [31:0] INC_880 = 32'd78741067;

    reg clk;
    reg rst;
    reg sample_tick;
    reg [31:0] phase_inc;
    wire signed [15:0] sample;
    wire sample_valid;

    reg [31:0] ref_phase;
    reg signed [15:0] expected_sample;
    reg expected_valid;
    integer ref_addr;
    integer rounded;
    real ref_value;
    integer clocks_checked;
    integer requests;
    integer outputs;
    integer trace_fd;
    reg [2047:0] trace_path;

    voice_dds dut (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .phase_inc(phase_inc), .sample(sample), .sample_valid(sample_valid)
    );

    initial clk = 1'b0;
    always #41.666666667 clk = ~clk;

    // Independent model: mathematical sine, quantized address, 32-bit wrap.
    // Check every clock, including idle clocks, not only valid samples.
    always @(posedge clk) begin
        if (rst) begin
            ref_phase = 32'd0;
            expected_sample = 16'sd0;
            expected_valid = 1'b0;
        end
        else begin
            expected_valid = sample_tick;
            if (sample_tick) begin
                ref_addr = ref_phase >> 22;
                ref_value = 32767.0 * $sin(6.283185307179586 * ref_addr / 1024.0);
                if (ref_value >= 0.0)
                    rounded = $rtoi(ref_value + 0.5);
                else
                    rounded = $rtoi(ref_value - 0.5);
                expected_sample = rounded[15:0];
                ref_phase = ref_phase + phase_inc;
                requests = requests + 1;
            end
        end
        #1;
        if ((sample !== expected_sample) || (sample_valid !== expected_valid)) begin
            $display("FAIL: time=%0t sample=%0d expected=%0d valid=%b expected_valid=%b",
                     $time, sample, expected_sample, sample_valid, expected_valid);
            $fatal(1, "DDS sample or valid mismatch");
        end
        if (sample_valid)
            outputs = outputs + 1;
        if ((trace_fd != 0) && (rst || sample_tick))
            $fwrite(trace_fd, "%0d %0d %0d\n", rst, phase_inc, $signed(sample));
        clocks_checked = clocks_checked + 1;
    end

    task step;
        input test_rst;
        input test_tick;
        input [31:0] test_inc;
        begin
            @(negedge clk);
            rst = test_rst;
            sample_tick = test_tick;
            phase_inc = test_inc;
            @(posedge clk);
            #2;
        end
    endtask

    task run_tone;
        input [31:0] increment;
        input integer target_hz;
        integer n;
        integer previous_sample;
        integer crossings;
        integer first_crossing;
        integer last_crossing;
        real measured_hz;
        begin
            step(1, 0, increment);
            step(0, 0, increment);
            previous_sample = 0;
            crossings = 0;
            first_crossing = 0;
            last_crossing = 0;
            // Start with a low tick on a falling edge.
            @(negedge clk);
            for (n = 0; n < TONE_SAMPLES; n = n + 1) begin
                repeat (SAMPLE_DIV - 1) @(negedge clk);
                sample_tick = 1'b1;
                @(posedge clk);
                #2;
                if ((previous_sample < 0) && ($signed(sample) >= 0)) begin
                    if (crossings == 0)
                        first_crossing = n;
                    last_crossing = n;
                    crossings = crossings + 1;
                end
                previous_sample = $signed(sample);
                @(negedge clk);
                sample_tick = 1'b0;
            end
            if (crossings < 2)
                $fatal(1, "Not enough positive zero crossings");
            measured_hz = 1.0 * FS_HZ * (crossings - 1) / (last_crossing - first_crossing);
            // Crossing locations are quantized to sample indices.
            if ((measured_hz < target_hz * 0.99) ||
                (measured_hz > target_hz * 1.01))
                $fatal(1, "Frequency outside 1 percent tolerance");
            $display("Tone %0d Hz: %0d samples, estimated frequency %.3f Hz, PASS",
                     target_hz, TONE_SAMPLES, measured_hz);
        end
    endtask

    initial begin
        rst = 1;
        sample_tick = 0;
        phase_inc = 0;
        clocks_checked = 0;
        requests = 0;
        outputs = 0;
        trace_fd = 0;
        if ($value$plusargs("DDS_TRACE=%s", trace_path)) begin
            trace_fd = $fopen(trace_path, "w");
            if (trace_fd == 0) $fatal(1, "Cannot open DDS trace file");
        end

        step(1, 0, 32'h40000000);
        // Old-phase sequence: 0, +32767, 0, -32767, 0.
        repeat (5) step(0, 1, 32'h40000000);
        step(0, 0, INC_880); // Changing pitch while paused must not move phase.
        step(0, 0, INC_440);
        step(0, 1, INC_440); // Resume from the held phase.
        step(0, 1, INC_880); // Pitch changes preserve phase continuity.
        step(1, 1, INC_880); // Reset wins even when a request is present.
        step(0, 1, 32'd0);
        step(0, 1, 32'd0);
        step(0, 0, 32'd0);
        $display("Reset, old-phase order, wrap, idle and pitch-change checks passed.");

        run_tone(INC_440, 440);
        run_tone(INC_880, 880);
        step(0, 0, INC_880);
        step(1, 1, INC_440);
        step(0, 1, INC_440);
        step(0, 0, INC_440);
        if (requests != outputs)
            $fatal(1, "Sample count mismatch");
        $display("PASS: voice_dds; %0d valid samples matched; %0d clock checks passed.",
                 outputs, clocks_checked);
        if (trace_fd != 0) $fclose(trace_fd);
        $stop;
    end

    initial begin
        #120000000;
        $fatal(1, "DDS simulation timed out");
    end
endmodule
