`timescale 1ns/1ps

module pressure_if #(
    parameter integer ADC_WIDTH = 12
) (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_valid,
    input  wire [ADC_WIDTH-1:0] pressure_raw,
    output reg  [ADC_WIDTH-1:0] pressure_filtered,
    output reg  [6:0] velocity,
    output reg  pressure_active
);

    wire [ADC_WIDTH+1:0] y_ext;
    wire [ADC_WIDTH+1:0] x_ext;
    wire [ADC_WIDTH+1:0] filter_next;
    wire [ADC_WIDTH-1:0] next_filtered;
    wire [ADC_WIDTH-1:0] velocity_scaled;

    assign y_ext = {2'b00, pressure_filtered};
    assign x_ext = {2'b00, pressure_raw};
    assign filter_next = y_ext - (y_ext >> 3) + (x_ext >> 3);
    assign next_filtered = filter_next[ADC_WIDTH-1:0];

    assign velocity_scaled = (next_filtered > 12'd128)
                           ? (next_filtered - 12'd128)
                           : 12'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pressure_filtered <= {ADC_WIDTH{1'b0}};
            velocity          <= 7'd0;
            pressure_active   <= 1'b0;
        end else if (sample_valid) begin
            pressure_filtered <= next_filtered;
            velocity          <= velocity_scaled[ADC_WIDTH-1:5];
            pressure_active   <= (next_filtered >= 12'd128);
        end
    end

endmodule