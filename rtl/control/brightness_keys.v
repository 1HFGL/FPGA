// Third expression axis, using board KEY1/KEY2 rather than the 13 piano keys.
// Active-low KEY1 darkens, KEY2 brightens; both held restore the original tone.
// SINGLE_KEY mode reserves KEY2 for instrument selection. KEY1 steps down with
// wrap at zero; holding KEY1 restores 127. Other mode retains +/- auto-repeat.
// Target changes by 16. Current moves one step/frame in either mode.
module brightness_keys #(
    parameter integer DEBOUNCE_CYCLES=100000,
    parameter integer REPEAT_CYCLES=5000000,
    parameter integer SINGLE_KEY=0
)(
    input wire clk,rst_n,sample_request,
    input wire [1:0] key_n,
    output reg [6:0] target,
    output reg [6:0] current
);
    wire [1:0] level,pressed;
    reg [31:0] repeat_count;
    touch_or_key_if #(.KEY_COUNT(2),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_keys(
        .clk(clk),.rst_n(rst_n),.raw_key(SINGLE_KEY?{1'b1,key_n[0]}:key_n),.key_level(level),
        .key_press(pressed),.key_release());
    always @(posedge clk) begin
        if(!rst_n) begin target<=127;current<=127;repeat_count<=0;end
        else begin
            if(level==2'b11) begin target<=127;repeat_count<=0;end
            else if(level==0) repeat_count<=0;
            else if((|pressed) || repeat_count>=REPEAT_CYCLES-1) begin
                repeat_count<=0;
                if(SINGLE_KEY && !(|pressed)) target<=127;
                else if(SINGLE_KEY && target==0) target<=127;
                else if(level[0]) target<=(target<16)?7'd0:target-7'd16;
                else target<=(target>111)?7'd127:target+7'd16;
            end else repeat_count<=repeat_count+1'b1;
            if(sample_request) begin
                if(current<target)current<=current+1'b1;
                else if(current>target)current<=current-1'b1;
            end
        end
    end
endmodule
