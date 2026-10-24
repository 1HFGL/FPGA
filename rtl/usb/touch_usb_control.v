// Bounded USB control reads and zero-data control writes. EP0 DATA1 starts each
// setup; only CRC-accepted, correctly toggled packets enter the result buffer.
module touch_usb_control #(
    parameter integer TIMEOUT_FRAMES=500,
    parameter integer ERROR_LIMIT=8
)(
    input wire clk,rst_n,frame_tick,
    input wire start,output wire ready,
    input wire [63:0] setup_data,
    input wire [6:0] device_address,ep0_max_packet,
    output reg done,success,stalled,
    output reg [9:0] result_length,
    output reg [1023:0] result_data,
    output wire command_valid,input wire command_ready,
    output wire [7:0] command_pid,
    output wire [6:0] command_address,
    output wire [3:0] command_endpoint,
    output wire command_toggle,
    output wire [6:0] command_length,
    output wire [63:0] command_payload,
    input wire transaction_done,transaction_error,
    input wire [7:0] response,
    input wire [15:0] received_length,
    input wire [511:0] received_payload
);
    localparam IDLE=0,SETUP=1,SETUP_WAIT=2,DATA=3,DATA_WAIT=4,
        COPY=5,STATUS=6,STATUS_WAIT=7,RETRY=8,FINISH=9;
    reg [3:0] state,retry_state;
    reg [63:0] setup;
    reg [6:0] address,mps;
    reg [9:0] wanted;
    reg direction_in,expected_toggle;
    reg [9:0] frames;
    reg [3:0] errors;
    reg [6:0] copy_index,packet_length;
    reg [511:0] packet;
    assign ready=state==IDLE;
    assign command_valid=state==SETUP || state==DATA || state==STATUS;
    assign command_pid=state==SETUP ? 8'h2d : state==DATA ? 8'h69 : direction_in ? 8'he1 : 8'h69;
    assign command_address=address;
    assign command_endpoint=0;
    assign command_toggle=state==SETUP ? 1'b0 : state==DATA ? expected_toggle : 1'b1;
    assign command_length=state==SETUP ? 7'd8 : 7'd0;
    assign command_payload=setup;
    task retry;
        input [3:0] target;
        begin
            if(response==8'h1e && !transaction_error)begin stalled<=1;success<=0;state<=FINISH;end
            else if(response==8'h5a && !transaction_error)begin retry_state<=target;state<=RETRY;end
            else if(errors>=ERROR_LIMIT-1)begin success<=0;state<=FINISH;end
            else begin errors<=errors+1'b1;retry_state<=target;state<=RETRY;end
        end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;retry_state<=IDLE;setup<=0;address<=0;mps<=8;wanted<=0;
            direction_in<=0;expected_toggle<=1;frames<=0;errors<=0;
            copy_index<=0;packet_length<=0;packet<=0;done<=0;success<=0;stalled<=0;
            result_length<=0;result_data<=0;
        end else begin
            done<=0;
            if(frame_tick && state!=IDLE && frames<TIMEOUT_FRAMES)frames<=frames+1'b1;
            if(state!=IDLE && frames>=TIMEOUT_FRAMES)begin success<=0;state<=FINISH;frames<=0;end
            else case(state)
                IDLE:if(start)begin
                    setup<=setup_data;address<=device_address;mps<=ep0_max_packet;
                    wanted<=setup_data[57:48];direction_in<=setup_data[7];
                    result_length<=0;frames<=0;errors<=0;success<=0;stalled<=0;expected_toggle<=1;
                    if(setup_data[63:48]>512 || (!setup_data[7] && setup_data[63:48]!=0))state<=FINISH;
                    else state<=SETUP;
                end
                SETUP:if(command_ready)state<=SETUP_WAIT;
                SETUP_WAIT:if(transaction_done)begin
                    if(!transaction_error && response==8'hd2)begin
                        errors<=0;state<=direction_in && wanted!=0?DATA:STATUS;
                    end else retry(SETUP);
                end
                DATA:if(command_ready)state<=DATA_WAIT;
                DATA_WAIT:if(transaction_done)begin
                    if(!transaction_error && (response==8'hc3 || response==8'h4b))begin
                        if(response!=(expected_toggle?8'h4b:8'hc3))retry(DATA);
                        else if(received_length>mps || received_length>64 || result_length+received_length>wanted)begin
                            success<=0;state<=FINISH;
                        end else begin
                            expected_toggle<=!expected_toggle;errors<=0;
                            packet<=received_payload;packet_length<=received_length[6:0];copy_index<=0;
                            state<=received_length==0?STATUS:COPY;
                        end
                    end else retry(DATA);
                end
                COPY:begin
                    if(result_length+copy_index<128)
                        result_data[(result_length+copy_index)*8+:8]<=packet[copy_index*8+:8];
                    if(copy_index==packet_length-1)begin
                        result_length<=result_length+packet_length;
                        state<=packet_length<mps || result_length+packet_length>=wanted?STATUS:DATA;
                    end else copy_index<=copy_index+1'b1;
                end
                STATUS:if(command_ready)state<=STATUS_WAIT;
                STATUS_WAIT:if(transaction_done)begin
                    if(!transaction_error && (direction_in ? response==8'hd2 : response==8'h4b && received_length==0))begin
                        success<=1;state<=FINISH;
                    end else retry(STATUS);
                end
                RETRY:if(frame_tick)state<=retry_state;
                FINISH:begin done<=1;state<=IDLE;end
                default:begin success<=0;state<=FINISH;end
            endcase
        end
    end
endmodule
