// 模态参数的一拍同步ROM：地址仍为{音色, MIDI音号, 模态项号}。
// 每音仅调度0..47项，按16项分为三个4096深度bank，避免为48..63项占BSRAM。
// bank内地址{音色,音号,项号低4位}，无乘法/非二次幂地址计算。
// bank选择与数据同拍寄存；输出保持上一次读取值，复位同步清零，不增加音频流水级。
// 派生表由model/pack_modal_rom.py生成；MODE_ROM_FILE仍指向原始规范参数表。
module modal_parameter_rom #(
    parameter MODE_ROM_FILE="rtl/rom/piano_v3_modes.mem"
)(
    input wire clk,rst_n,read_enable,
    input wire [13:0] address,
    output wire [75:0] data
);
    localparam BANK0_FILE={MODE_ROM_FILE,".bank0.mem"};
    localparam BANK1_FILE={MODE_ROM_FILE,".bank1.mem"};
    localparam BANK2_FILE={MODE_ROM_FILE,".bank2.mem"};
    reg [75:0] bank0[0:4095],bank1[0:4095],bank2[0:4095];
    reg [75:0] q0,q1,q2;
    reg [1:0] selected;
    wire [11:0] bank_address={address[13:6],address[3:0]};
    initial begin
        $readmemh(BANK0_FILE,bank0);
        $readmemh(BANK1_FILE,bank1);
        $readmemh(BANK2_FILE,bank2);
    end
    always @(posedge clk) begin
        if(!rst_n)begin q0<=0;q1<=0;q2<=0;selected<=0;end
        else if(read_enable)begin
            selected<=address[5:4];
            if(address[5:4]==0)q0<=bank0[bank_address];
            if(address[5:4]==1)q1<=bank1[bank_address];
            if(address[5:4]==2)q2<=bank2[bank_address];
        end
    end
    // 原表48..63项的静音元组：只有loss=1，即bit10置位。
    assign data=(selected==0)?q0:(selected==1)?q1:(selected==2)?q2:76'h400;
endmodule
