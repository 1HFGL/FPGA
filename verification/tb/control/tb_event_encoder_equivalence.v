`timescale 1ns/1ps
// Cycle-exact comparison with the frozen pre-optimization encoder, including
// its internal service decision (so output FIFO backpressure cannot hide it).
module tb_event_encoder_equivalence;
 reg clk=0,rst=0,ready=0;
 always #5 clk=~clk;
 reg [12:0] press=0,release_key=0;
 reg [90:0] velocity=0;
 reg [3:0] timbre=0;
 reg [1:0] octave=1;
 wire valid_a,valid_b,overflow_a,overflow_b;
 wire [23:0] event_a,event_b;
 integer cycle=0,events=0,full_events=0,i,epoch;
 reg [31:0] rng=32'hbd128465;
 event_encoder #(.KEY_COUNT(13),.CHROMATIC_KEYS(1),.ENABLE_PLAY_CONTROL(1)) dut(
  .clk(clk),.rst_n(rst),.key_press(press),.key_release(release_key),.key_velocity_flat(velocity),
  .input_timbre(timbre),.octave_select(octave),.input_overflow(overflow_a),
  .event_valid(valid_a),.event_type(event_a[23]),.event_source_id(event_a[22:18]),
  .event_note(event_a[17:11]),.event_velocity(event_a[10:4]),.event_timbre(event_a[3:0]),.event_ready(ready));
 event_encoder_reference #(.KEY_COUNT(13),.CHROMATIC_KEYS(1),.ENABLE_PLAY_CONTROL(1)) reference(
  .clk(clk),.rst_n(rst),.key_press(press),.key_release(release_key),.key_velocity_flat(velocity),
  .input_timbre(timbre),.octave_select(octave),.input_overflow(overflow_b),
  .event_valid(valid_b),.event_type(event_b[23]),.event_source_id(event_b[22:18]),
  .event_note(event_b[17:11]),.event_velocity(event_b[10:4]),.event_timbre(event_b[3:0]),.event_ready(ready));
 always @(posedge clk)begin
  cycle=cycle+1;
  if(rst)begin
   if({valid_a,overflow_a}!=={valid_b,overflow_b} || (valid_a && event_a!==event_b) ||
      dut.do_write!==reference.do_write || (dut.do_write && dut.selected!==reference.selected))begin
    $display("FAIL encoder equivalence cycle=%0d",cycle);$finish;
   end
   if(valid_a && ready)events=events+1;
   if(dut.fifo_count==64)full_events=full_events+1;
  end
 end
 task reset;
  begin rst=0;press=0;release_key=0;repeat(3)@(negedge clk);rst=1;end
 endtask
 initial begin
  for(i=0;i<13;i=i+1)velocity[i*7+:7]=60+i;
  reset;ready=1;
  // All keys arrive together, then release across a range/preset change.
  press=13'h1fff;@(negedge clk);press=0;repeat(40)@(negedge clk);
  octave=2;timbre=1;release_key=13'h1fff;@(negedge clk);release_key=0;repeat(40)@(negedge clk);
  // Fill the shared FIFO and all per-key queues, then reset the sticky overflow.
  ready=0;
  repeat(12)begin press=13'h1fff;@(negedge clk);press=0;repeat(16)@(negedge clk);end
  if(!overflow_a || full_events==0)begin $display("FAIL encoder overflow coverage");$finish;end
  for(epoch=0;epoch<20;epoch=epoch+1)begin
   reset;
   for(i=0;i<1500;i=i+1)begin
    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    ready=rng[4] || rng[7];press=0;release_key=0;
    if((i%7)==0)begin
     if(rng[9])press=13'b1<<(rng[15:12]%13);
     else release_key=13'b1<<(rng[15:12]%13);
    end
    octave=rng[19:18]%3;timbre={3'd0,rng[20]};
    @(negedge clk);
   end
  end
  if(events<1000)begin $display("FAIL encoder event coverage %0d",events);$finish;end
  $display("PASS tb_event_encoder_equivalence: %0d cycle-exact checks, %0d events, simultaneous keys, wraparound, backpressure, overflow/reset",cycle,events);$finish;
 end
 initial begin #400000;$display("FAIL encoder equivalence timeout");$finish;end
endmodule
