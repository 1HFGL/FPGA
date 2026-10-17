// UG306要求LOCK连续稳定至少2ms；失锁立即复位显示，不能复位正在演奏的音频。
// display_rst_n同时送显示信箱两端；每个显示时钟域再同步释放。
module hdmi_reset_guard #(parameter integer LOCK_CYCLES=100000)(
    input wire sys_clk,rst_n,pll_locked,
    output wire display_rst_n
);
    reg [1:0] lock_sync;
    reg [31:0] stable_count;
    reg stable;
    wire reset_ok=rst_n && pll_locked;
    always @(posedge sys_clk or negedge reset_ok) begin
        if(!reset_ok) begin lock_sync<=0;stable_count<=0;stable<=0;end
        else begin
            lock_sync<={lock_sync[0],1'b1};
            if(!lock_sync[1]) begin stable_count<=0;stable<=0;end
            else if(!stable) begin
                if(stable_count==LOCK_CYCLES-1) stable<=1;
                else stable_count<=stable_count+1'b1;
            end
        end
    end
    assign display_rst_n=reset_ok && stable;
endmodule
