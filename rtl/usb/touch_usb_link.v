// 48MHz full-speed transaction boundary. Commands/payload stay registered through
// the SIE transaction; received bytes are provisional until done && !error.
module touch_usb_link #(
    parameter integer FRAME_CYCLES=48000,
    parameter integer FRAME_GUARD=6000
)(
    input wire clk,rst_n,enabled,
    input wire command_valid,output wire command_ready,
    input wire [7:0] command_pid,
    input wire [6:0] command_address,
    input wire [3:0] command_endpoint,
    input wire command_toggle,
    input wire [6:0] command_length,
    input wire [63:0] command_payload,
    output reg done,error,
    output reg [7:0] response,
    output reg [15:0] received_length,
    output reg [511:0] received_payload,
    output reg frame_tick,
    input wire [7:0] utmi_rx_data,
    input wire utmi_rxvalid,utmi_rxactive,utmi_rxerror,utmi_txready,
    input wire [1:0] utmi_linestate,
    output wire [7:0] utmi_tx_data,
    output wire utmi_txvalid
);
    localparam IDLE=0,START=1,WAIT=2,COOL=3;
    reg [1:0] state;
    reg [15:0] frame_clock;
    reg [10:0] frame_number;
    reg sof_pending,is_sof;
    reg [7:0] pid;
    reg [6:0] address,length;
    reg [3:0] endpoint;
    reg toggle;
    reg [63:0] payload;
    reg [6:0] rx_index;
    reg [3:0] tx_index;
    reg overflow;
    reg [5:0] cooldown;
    reg [15:0] watchdog;
    wire sie_idle,sie_ack,sie_pop,sie_push,sie_crc,sie_timeout;
    wire [7:0] sie_response,sie_data;
    wire [15:0] sie_count;
    wire reset=!rst_n || !enabled;
    assign command_ready=enabled && state==IDLE && !sof_pending &&
        frame_clock<FRAME_CYCLES-FRAME_GUARD;
    // The reused SIE expects bit-reversed address/endpoint fields.
    wire [6:0] reversed_address={address[0],address[1],address[2],address[3],address[4],address[5],address[6]};
    wire [3:0] reversed_endpoint={endpoint[0],endpoint[1],endpoint[2],endpoint[3]};
    usbh_sie #(.USB_CLK_FREQ(48000000)) u_sie(
        .clk_i(clk),.rst_i(reset || watchdog==16'hffff),.start_i(state==START),
        .in_transfer_i(pid==8'h69),.sof_transfer_i(is_sof),.resp_expected_i(!is_sof),
        .token_pid_i(pid),.token_dev_i(reversed_address),.token_ep_i(reversed_endpoint),
        .data_len_i({9'd0,length}),.data_idx_i(toggle),.tx_data_i(payload[tx_index*8+:8]),
        .utmi_txready_i(utmi_txready),.utmi_data_i(utmi_rx_data),
        .utmi_rxvalid_i(utmi_rxvalid),.utmi_rxactive_i(utmi_rxactive),.utmi_rxerror_i(utmi_rxerror),
        .utmi_linestate_i(utmi_linestate),.ack_o(sie_ack),.tx_pop_o(sie_pop),
        .rx_data_o(sie_data),.rx_push_o(sie_push),.tx_done_o(),.rx_done_o(),
        .crc_err_o(sie_crc),.timeout_o(sie_timeout),.response_o(sie_response),
        .rx_count_o(sie_count),.idle_o(sie_idle),.utmi_data_o(utmi_tx_data),.utmi_txvalid_o(utmi_txvalid));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;frame_clock<=0;frame_number<=0;sof_pending<=0;frame_tick<=0;
            is_sof<=0;pid<=0;address<=0;endpoint<=0;toggle<=0;length<=0;payload<=0;
            rx_index<=0;tx_index<=0;overflow<=0;cooldown<=0;watchdog<=0;
            done<=0;error<=0;response<=0;received_length<=0;received_payload<=0;
        end else begin
            done<=0;frame_tick<=0;
            if(!enabled)begin state<=IDLE;frame_clock<=0;frame_number<=0;sof_pending<=0;watchdog<=0;end
            else begin
                if(frame_clock==FRAME_CYCLES-1)begin
                    frame_clock<=0;frame_tick<=1;sof_pending<=1;frame_number<=frame_number+1'b1;
                end else frame_clock<=frame_clock+1'b1;
                if(sie_pop)tx_index<=tx_index+1'b1;
                if(sie_push)begin
                    if(rx_index<64)received_payload[rx_index*8+:8]<=sie_data;
                    else overflow<=1;
                    if(rx_index!=127)rx_index<=rx_index+1'b1;
                end
                case(state)
                    IDLE:begin
                        watchdog<=0;
                        if(sof_pending)begin
                            pid<=8'ha5;address<=frame_number[6:0];endpoint<=frame_number[10:7];
                            length<=0;is_sof<=1;sof_pending<=0;state<=START;
                        end else if(command_valid && command_ready)begin
                            pid<=command_pid;address<=command_address;endpoint<=command_endpoint;
                            toggle<=command_toggle;length<=command_length;payload<=command_payload;
                            is_sof<=0;rx_index<=0;tx_index<=0;overflow<=0;state<=START;
                        end
                    end
                    START:if(sie_ack)state<=WAIT;
                    WAIT:begin
                        watchdog<=watchdog+1'b1;
                        if(sie_idle || watchdog==16'hfffe)begin
                            if(!is_sof)begin
                                done<=1;error<=sie_crc || sie_timeout || overflow || watchdog==16'hfffe;
                                response<=sie_response;received_length<=sie_count;
                            end
                            cooldown<=48;state<=COOL;
                        end
                    end
                    COOL:if(cooldown==0)begin state<=IDLE;watchdog<=0;end else cooldown<=cooldown-1'b1;
                    default:state<=IDLE;
                endcase
            end
        end
    end
endmodule
