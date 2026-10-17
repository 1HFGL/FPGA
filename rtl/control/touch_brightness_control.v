// Normalized primary-contact input, synchronous to clk (50MHz).
// USB enumeration/HID parsing/coordinate calibration belong to the future host.
// No pin or USB packet assumptions here. See docs/touch-brightness.md.
module touch_brightness_control #(
    parameter integer TIMEOUT_CYCLES=10000000 // 200ms at 50MHz
)(
    input wire clk,rst_n,
    input wire connected,report_valid,contact_down,
    input wire [11:0] contact_x,contact_y,
    output reg [6:0] target,
    output reg available,
    output reg dragging
);
    localparam integer COUNT_WIDTH=(TIMEOUT_CYCLES>1)?$clog2(TIMEOUT_CYCLES):1;
    reg [COUNT_WIDTH-1:0] age;
    reg down_seen;
    wire coordinate_valid=contact_x<1024 && contact_y<600;
    wire slider_y=contact_y>=40 && contact_y<74;
    wire slider_hit=contact_x>=336 && contact_x<876 && slider_y;
    wire reset_hit=contact_x>=880 && contact_x<984 && contact_y>=12 && contact_y<70;
    wire [11:0] offset_x=contact_x-12'd352;
    wire [6:0] mapped=(contact_x<=352)?7'd0:(contact_x>=860)?7'd127:offset_x[8:2];
    always @(posedge clk)begin
        if(!rst_n)begin target<=127;available<=0;dragging<=0;down_seen<=0;age<=0;end
        else if(!connected)begin
            available<=0;dragging<=0;down_seen<=0;age<=0;
            // Retain the last tone on cable loss. Reset restores 127.
        end else if(report_valid)begin
            if(!contact_down)begin
                available<=1;age<=0;down_seen<=0;dragging<=0;
            end else if(coordinate_valid)begin
                available<=1;age<=0;down_seen<=1;
                if(!down_seen)begin
                    dragging<=slider_hit;
                    if(slider_hit)target<=mapped;
                    else if(reset_hit)target<=127;
                end else if(dragging && slider_y)target<=mapped;
            end else begin
                // Malformed down report cancels capture; require an up before retry.
                available<=0;dragging<=0;down_seen<=1;age<=0;
            end
        end else if(age>=TIMEOUT_CYCLES-1)begin
            available<=0;dragging<=0;down_seen<=1;
            // Missing release / stalled stream: wait for up, never reinterpret a drag.
        end else age<=age+1'b1;
    end
endmodule
