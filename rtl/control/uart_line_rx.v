// 流式ASCII行解析，不保存整条512字节行。只在LF输出一拍cmd_valid。
// 命令最多8字符，至多三个32位十进制参数；APPLY后续载荷不解释。
// bad_byte（帧错/丢字节）后丢弃到LF，绝不能执行残缺命令。
module uart_line_rx #(parameter integer TIMEOUT_CYCLES=12500000)(
    input wire clk,rst_n,input wire byte_valid,input wire [7:0] byte_data,
    input wire bad_byte,
    output reg cmd_valid,output reg [3:0] cmd,
    output reg [3:0] fields,
    output reg [31:0] arg0,arg1,arg2,
    output reg bad_line,bad_number,sequence_valid
);
    localparam HELLO=1,ON=2,OFF=3,PANIC=4,STATUS=5,APPLY=6;
    reg [63:0] name;
    reg [3:0] name_len,tokens,digits;
    reg in_token,dropping,number_bad,seq_bad,cr_seen;
    reg [9:0] length;
    reg [31:0] numbers[0:2];
    reg [31:0] timeout_count;
    wire digit=byte_data>=8'd48 && byte_data<=8'd57;
    // ASCII '0'..'9' 的低四位恰为0..9；仅digit=1时参与合法累加。
    wire [3:0] digit_value=byte_data[3:0];
    wire apply_name=(name=="APPLY");
    reg [3:0] decoded;
    reg [31:0] current_number;
    reg overflow;
    always @* begin
        decoded=0;
        case(name)
            "HELLO": decoded=HELLO;
            "NOTE_ON": decoded=ON;
            "NOTE_OFF": decoded=OFF;
            "PANIC": decoded=PANIC;
            "STATUS?": decoded=STATUS;
            "APPLY": decoded=APPLY;
            "XBEGIN":decoded=7;"XDATA":decoded=8;"XCOMMIT":decoded=9;
            "XABORT":decoded=10;"CTRL":decoded=11;"GETCFG":decoded=12;
            default: decoded=0;
        endcase
        if(name_len>8) decoded=0;
        current_number=0;
        if(tokens>=2 && tokens<=4) current_number=numbers[tokens-2];
        overflow=current_number>32'd429496729 ||
                 (current_number==32'd429496729 && digit_value>5);
    end
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            name<=0; name_len<=0; tokens<=0; digits<=0; in_token<=0;
            dropping<=0; number_bad<=0; seq_bad<=0; cr_seen<=0;
            length<=0; timeout_count<=0;
            cmd_valid<=0; cmd<=0; fields<=0; arg0<=0; arg1<=0; arg2<=0;
            bad_line<=0; bad_number<=0; sequence_valid<=0;
            for(i=0;i<3;i=i+1) numbers[i]<=0;
        end else begin
            cmd_valid<=0;
            if(bad_byte) begin dropping<=1; timeout_count<=0; end
            else if(byte_valid) begin
                timeout_count<=0;
                if(byte_data==10) begin
                    if(length!=0 || dropping) begin
                        cmd_valid<=1; cmd<=decoded; fields<=tokens;
                        arg0<=numbers[0]; arg1<=numbers[1]; arg2<=numbers[2];
                        bad_line<=dropping; bad_number<=number_bad;
                        sequence_valid<=tokens>=2 && !seq_bad;
                    end
                    name<=0; name_len<=0; tokens<=0; digits<=0; in_token<=0;
                    dropping<=0; number_bad<=0; seq_bad<=0; cr_seen<=0; length<=0;
                    for(i=0;i<3;i=i+1) numbers[i]<=0;
                end else begin
                    if(length<513) length<=length+1'b1;
                    if(length>=512 || byte_data<32 && byte_data!=13 || byte_data>126 || cr_seen)
                        dropping<=1;
                    if(byte_data==13) cr_seen<=1;
                    else if(!dropping) begin
                        if(byte_data==32) begin in_token<=0; digits<=0; end
                        else if(!in_token) begin
                            in_token<=1;
                            if(tokens<15) tokens<=tokens+1'b1;
                            if(tokens==0) begin name<={56'd0,byte_data}; name_len<=1; end
                            else if(tokens<=3) begin
                                digits<=1;
                                numbers[tokens-1]<=digit ? {28'd0,digit_value} : 32'd0;
                                if(!digit) begin
                                    number_bad<=1;
                                    if(tokens==1) seq_bad<=1;
                                end
                            end else if(!apply_name) number_bad<=1;
                        end else if(tokens==1) begin
                            if(name_len<8) begin name<={name[55:0],byte_data}; name_len<=name_len+1'b1; end
                            // 长命令名记为未知；不能截成已支持命令，也不把合法ASCII作坏行。
                            else name_len<=9;
                        end else if(tokens>=2 && tokens<=4) begin
                            // APPLY仅解析序号，后续CRC/配置文本不是本版数字参数。
                            if(!apply_name || tokens==2) begin
                                if(!digit || digits>=10 || overflow) begin
                                    number_bad<=1;
                                    if(tokens==2) seq_bad<=1;
                                end else numbers[tokens-2]<=(current_number<<3)+(current_number<<1)+digit_value;
                                if(digits<11) digits<=digits+1'b1;
                            end
                        end
                    end
                end
            end else if(length!=0 || dropping) begin
                if(timeout_count==TIMEOUT_CYCLES-1) begin
                    name<=0; name_len<=0; tokens<=0; digits<=0; in_token<=0;
                    dropping<=0; number_bad<=0; seq_bad<=0; cr_seen<=0; length<=0; timeout_count<=0;
                    for(i=0;i<3;i=i+1) numbers[i]<=0;
                end else timeout_count<=timeout_count+1'b1;
            end
        end
    end
endmodule
