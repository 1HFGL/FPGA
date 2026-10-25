`timescale 1ns/1ps
// 对全部可达偏移及1024个基向量检查9拍采集，不改上游协议TB。
module tb_usb_descriptor_serial;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [1023:0] buffer=0;
    reg [9:0] offset=0;
    integer bit_index,address,byte_index,cycle,checks=0;
    touch_usb_host dut(.clk(clk),.rst_n(rst_n),.line_state(2'b01),.host_transmitting(1'b0),
        .report_ready(1'b0),.command_ready(1'b0),.link_frame_tick(1'b0),
        .transaction_done(1'b0),.transaction_error(1'b0),.response(8'd0),
        .received_length(16'd0),.received_payload(512'd0));
    function [7:0] reference;
        input [1023:0] data;input integer position;
        begin reference=position<128?data[position*8+:8]:8'd0;end
    endfunction
    initial begin
        #1;#10;rst_n=1;
        force dut.control_data=buffer;force dut.parse_offset=offset;
        force dut.configuration_length=10'd128;force dut.state=4'd6;
        for(bit_index=-1;bit_index<1024;bit_index=bit_index+1)begin
            buffer=0;if(bit_index>=0)buffer[bit_index]=1;
            for(address=0;address<128;address=address+1)begin
                @(negedge clk);offset=address;
                dut.descriptor_index=0;dut.descriptor_ready=0;
                for(cycle=0;cycle<9;cycle=cycle+1)begin
                    @(posedge clk);#1;
                    if(dut.descriptor_ready !== (cycle==8))begin
                        $display("FAIL descriptor early/late ready cycle=%0d",cycle);$finish;
                    end
                end
                for(byte_index=0;byte_index<9;byte_index=byte_index+1)begin
                    if(dut.descriptor_fields[byte_index*8+:8]!==reference(buffer,address+byte_index))begin
                        $display("FAIL descriptor serial bit=%0d address=%0d byte=%0d",bit_index,address,byte_index);$finish;
                    end
                    checks=checks+1;
                end
            end
        end
        @(negedge clk);rst_n=0;#1;
        if(dut.descriptor_ready!==0 || dut.descriptor_index!==0 || dut.descriptor_fields!==0)begin
            $display("FAIL descriptor reset");$finish;
        end
        $display("PASS tb_usb_descriptor_serial: %0d byte comparisons, all basis vectors/128 offsets, exact nine-cycle readiness and reset",checks);$finish;
    end
endmodule
