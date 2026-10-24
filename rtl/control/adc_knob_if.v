`timescale 1ns/1ps

// ADC 旋钮接口：
//  - 每路 12bit ADC 经过一阶 IIR 低通滤波，映射为 7bit 控制值；
//  - 输出按 SLEW_STEP 逐采样平滑，避免旋钮快速旋转时的"拉链噪声"；
//  - READY_SAMPLES 个有效采样后置 ready，连续超时无有效采样则置 fault。
module adc_knob_if #(
    parameter integer ADC_WIDTH      = 12,
    parameter integer KNOB_COUNT     = 2,
    parameter integer READY_SAMPLES  = 16,
    parameter integer FAULT_TIMEOUT  = 5000000,
    parameter integer VALUE_WIDTH    = 7,
    parameter integer SLEW_STEP      = 1,
    parameter integer FILTER_SHIFT   = 3,
    // Raw-code hysteresis: held reference rejects noise without waiting for more samples.
    // Zero preserves the original interface behavior for independent/legacy projects.
    parameter integer HYSTERESIS_COUNTS = 0,
    parameter integer CENTER_CHANNEL = -1
) (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_valid,
    input  wire [KNOB_COUNT*ADC_WIDTH-1:0] raw_flat,
    output wire [KNOB_COUNT*VALUE_WIDTH-1:0] value_flat,
    output reg  param_valid,
    output reg  ready,
    output reg  fault
);

    localparam integer SHIFT = ADC_WIDTH - VALUE_WIDTH;
    localparam [ADC_WIDTH:0] ROUND_MASK =
        ({{ADC_WIDTH{1'b0}}, 1'b1} << FILTER_SHIFT) - {{ADC_WIDTH{1'b0}}, 1'b1};
    localparam [VALUE_WIDTH:0] SLEW = SLEW_STEP[VALUE_WIDTH:0];

    reg [ADC_WIDTH-1:0]  filtered  [0:KNOB_COUNT-1];
    reg [ADC_WIDTH-1:0] accepted [0:KNOB_COUNT-1];
    reg history_valid;
    reg [VALUE_WIDTH-1:0] value_mem [0:KNOB_COUNT-1];
    reg [31:0] ready_count;
    reg [31:0] timeout_count;

    integer i;

    function [ADC_WIDTH-1:0] stable_raw;
        input [ADC_WIDTH-1:0] previous,incoming;
        input initialized,center;
        reg [ADC_WIDTH:0] distance;
        reg [ADC_WIDTH:0] midpoint,quantum;
        begin
            midpoint=({{ADC_WIDTH{1'b0}},1'b1} << (ADC_WIDTH-1));
            quantum=({{ADC_WIDTH{1'b0}},1'b1} << SHIFT);
            distance=(incoming>=previous)?{1'b0,incoming}-{1'b0,previous}:
                                           {1'b0,previous}-{1'b0,incoming};
            if(HYSTERESIS_COUNTS==0)stable_raw=incoming;
            // The existing bend-neutral bins are 63/64. Always reach neutral on return.
            else if(center && {1'b0,incoming}>=midpoint-quantum &&
                             {1'b0,incoming}<midpoint+quantum)
                stable_raw=midpoint[ADC_WIDTH-1:0];
            else if(!initialized || incoming==0 || (&incoming) || distance>HYSTERESIS_COUNTS)
                stable_raw=incoming;
            else stable_raw=previous;
        end
    endfunction

    // Round the correction away from zero so constant inputs reach both endpoints.
    function [ADC_WIDTH-1:0] filter_next;
        input [ADC_WIDTH-1:0] previous;
        input [ADC_WIDTH-1:0] incoming;
        reg [ADC_WIDTH:0] correction;
        reg [ADC_WIDTH:0] result;
        begin
            if (incoming >= previous) begin
                correction = ({1'b0, incoming} - {1'b0, previous}
                            + ROUND_MASK) >> FILTER_SHIFT;
                result = {1'b0, previous} + correction;
            end else begin
                correction = ({1'b0, previous} - {1'b0, incoming}
                            + ROUND_MASK) >> FILTER_SHIFT;
                result = {1'b0, previous} - correction;
            end
            filter_next = result[ADC_WIDTH-1:0];
        end
    endfunction

    function [VALUE_WIDTH-1:0] slew_next;
        input [VALUE_WIDTH-1:0] previous;
        input [VALUE_WIDTH-1:0] target;
        reg [VALUE_WIDTH:0] difference;
        reg [VALUE_WIDTH:0] result;
        begin
            if (target > previous) begin
                difference = {1'b0, target} - {1'b0, previous};
                result = (difference > SLEW) ? {1'b0, previous} + SLEW : {1'b0, target};
            end else begin
                difference = {1'b0, previous} - {1'b0, target};
                result = (difference > SLEW) ? {1'b0, previous} - SLEW : {1'b0, target};
            end
            slew_next = result[VALUE_WIDTH-1:0];
        end
    endfunction

    genvar g;
    generate
        for (g = 0; g < KNOB_COUNT; g = g + 1) begin : g_knob_out
            assign value_flat[g*VALUE_WIDTH +: VALUE_WIDTH] = value_mem[g];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_count  <= 32'd0;
            timeout_count <= 32'd0;
            param_valid  <= 1'b0;
            ready        <= 1'b0;
            fault        <= 1'b0;
            history_valid <= 1'b0;
            for (i = 0; i < KNOB_COUNT; i = i + 1) begin
                accepted[i] <= {ADC_WIDTH{1'b0}};
                filtered[i]  <= {ADC_WIDTH{1'b0}};
                value_mem[i] <= {VALUE_WIDTH{1'b0}};
            end
        end else begin
            param_valid <= 1'b0;

            if (sample_valid) begin
                timeout_count <= 32'd0;
                param_valid   <= 1'b1;
                fault         <= 1'b0;
                history_valid <= 1'b1;

                if (ready_count < READY_SAMPLES) begin
                    ready_count <= ready_count + 1'b1;
                end
                if ((READY_SAMPLES <= 1) || (ready_count >= READY_SAMPLES - 1)) begin
                    ready <= 1'b1;
                end

                for (i = 0; i < KNOB_COUNT; i = i + 1) begin
                    accepted[i] <= stable_raw(accepted[i],raw_flat[i*ADC_WIDTH +: ADC_WIDTH],history_valid,i==CENTER_CHANNEL);
                    filtered[i] <= filter_next(filtered[i],stable_raw(accepted[i],raw_flat[i*ADC_WIDTH +: ADC_WIDTH],history_valid,i==CENTER_CHANNEL));
                    value_mem[i] <= slew_next(value_mem[i],
                        filter_next(filtered[i],stable_raw(accepted[i],raw_flat[i*ADC_WIDTH +: ADC_WIDTH],history_valid,i==CENTER_CHANNEL)) >> SHIFT);
                end
            end else begin
                // Watch from reset too: an ADC that never sends a sample is faulty.
                if (timeout_count >= FAULT_TIMEOUT - 1) begin
                    fault <= 1'b1;
                    ready <= 1'b0;
                    ready_count <= 32'd0;
                    history_valid <= 1'b0;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end
        end
    end

endmodule
