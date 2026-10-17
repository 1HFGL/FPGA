// 7位旋钮到显示用±2半音归一化码，63/64为中心，0对应-32768。
// 对原floor(distance*32767/63)精确化简：32767=63*520+7，
// 因而结果为(distance<<9)+(distance<<3)+floor(distance/9)。
module display_bend_map(input wire [6:0] knob,output wire signed [15:0] bend);
    wire [5:0] distance=knob[6] ? knob[5:0] : (6'd63-knob[5:0]);
    wire [2:0] ninths=(distance>=63)?3'd7:(distance>=54)?3'd6:
        (distance>=45)?3'd5:(distance>=36)?3'd4:(distance>=27)?3'd3:
        (distance>=18)?3'd2:(distance>=9)?3'd1:3'd0;
    wire [14:0] magnitude={distance,9'd0}+{6'd0,distance,3'd0}+{12'd0,ninths};
    assign bend=(knob==0)?-16'sd32768:
        (knob[6]?$signed({1'b0,magnitude}):-$signed({1'b0,magnitude}));
endmodule
