module top (
  // I/O ports
  input  logic hz2m, hz100, reset,
  input  logic [20:0] pb,
  /* verilator lint_off UNOPTFLAT */
  output logic [7:0] left, right,
         ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0,
  output logic red, green, blue,

  // UART ports
  output logic [7:0] txdata,
  input  logic [7:0] rxdata,
  output logic txclk, rxclk,
  input  logic txready, rxready
);

  logic [4:0] keycode;
  logic strobe;
  logic [1:0] mode;
  
  scankey sk (.clk(hz2m), .rst(reset), .in(pb[19:0]), .out(keycode), .strobe(strobe));
  controller clr(.clk(strobe), .rst(reset), .set_edit(keycode == 5'b10011), .set_play(keycode == 5'b10010), .set_raw(keycode == 5'b10000), .mode(mode));

  assign red = mode == 2'd2;
  assign green = mode == 2'd1;
  assign blue = mode == 2'd0;
  
  logic [7:0] edit_seq_out;
  logic [2:0] ctr_out;
  logic [3:0] edit_play_smpl [7:0];
  logic bpm_clk;
  logic [7:0] play_seq_out;
  logic [2:0] seq_sel;
  logic [7:0] seq_out;
  
  clkdiv #(20) divhz2 (.clk(hz2m), .rst(reset), .lim(20'd499999), .hzX(bpm_clk));
  sequencer edit (.clk(strobe), .rst(reset), .srst(mode != 2'd0), .go_right(pb[8]), .go_left(pb[11]), .seq_out(edit_seq_out));
  prienc8to3 enc (.in(edit_seq_out), .out(ctr_out));

  sequencer play (.clk(bpm_clk), .rst(reset), .srst(mode != 2'd1), .go_right(1'b1), .go_left(1'b0), .seq_out(play_seq_out));
  
  always_ff @(posedge hz2m, posedge reset) begin
    if (reset) begin
      seq_out <= 8'b0;
    end else begin
      seq_out <= mode == 2'd1 ? play_seq_out : edit_seq_out;
    end
  end
  
  prienc8to3 enc2 (.in(seq_out), .out(seq_sel));

  assign {ss7[5], ss7[1], ss7[4], ss7[2]} = {edit_play_smpl[7][3], edit_play_smpl[7][2], edit_play_smpl[7][1], edit_play_smpl[7][0]};
  assign {ss6[5], ss6[1], ss6[4], ss6[2]} = {edit_play_smpl[6][3], edit_play_smpl[6][2], edit_play_smpl[6][1], edit_play_smpl[6][0]};
  assign {ss5[5], ss5[1], ss5[4], ss5[2]} = {edit_play_smpl[5][3], edit_play_smpl[5][2], edit_play_smpl[5][1], edit_play_smpl[5][0]};
  assign {ss4[5], ss4[1], ss4[4], ss4[2]} = {edit_play_smpl[4][3], edit_play_smpl[4][2], edit_play_smpl[4][1], edit_play_smpl[4][0]};
  assign {ss3[5], ss3[1], ss3[4], ss3[2]} = {edit_play_smpl[3][3], edit_play_smpl[3][2], edit_play_smpl[3][1], edit_play_smpl[3][0]};
  assign {ss2[5], ss2[1], ss2[4], ss2[2]} = {edit_play_smpl[2][3], edit_play_smpl[2][2], edit_play_smpl[2][1], edit_play_smpl[2][0]};
  assign {ss1[5], ss1[1], ss1[4], ss1[2]} = {edit_play_smpl[1][3], edit_play_smpl[1][2], edit_play_smpl[1][1], edit_play_smpl[1][0]};
  assign {ss0[5], ss0[1], ss0[4], ss0[2]} = {edit_play_smpl[0][3], edit_play_smpl[0][2], edit_play_smpl[0][1], edit_play_smpl[0][0]};

  sequence_editor seq_edit (.clk(strobe), .rst(reset), .mode(mode), .set_time_idx(seq_sel), .tgl_play_smpl(pb[3:0]), .seq_smpl_1(edit_play_smpl[0]), .seq_smpl_2(edit_play_smpl[1]), 
                            .seq_smpl_3(edit_play_smpl[2]), .seq_smpl_4(edit_play_smpl[3]), .seq_smpl_5(edit_play_smpl[4]), .seq_smpl_6(edit_play_smpl[5]), .seq_smpl_7(edit_play_smpl[6]), .seq_smpl_8(edit_play_smpl[7]));
      
  
  assign {left[7], left[5], left[3], left[1], 
          right[7], right[5], right[3], right[1]} = seq_out;
  logic prev_bpm_clk;
  logic [31:0] enable_ctr;
  always_ff @(posedge hz2m, posedge reset)
  if (reset) begin
    prev_bpm_clk <= 0;
    enable_ctr <= 0;
  end
  // otherwise, if we're in PLAY mode
  else if (mode == 2'd2) begin
    // if we're on a rising edge of bpm_clk, indicating 
    // the beginning of the beat, reset the counter.
    if (~prev_bpm_clk && bpm_clk) begin
    enable_ctr <= 0;
    prev_bpm_clk <= 1;
    end
    // if we're on a falling edge of bpm_clk, indicating 
    // the middle of the beat, set the counter to half its value
    // to correct for drift.
    else if (prev_bpm_clk && ~bpm_clk) begin
      enable_ctr <= 499999;
      prev_bpm_clk <= 0;
    end
    // otherwise count to 1 million, and reset to 0 when that value is reached.
    else begin
      enable_ctr <= (enable_ctr == 999999) ? 0 : enable_ctr + 1;
    end
  end
  // reset the counter so we start on time again.
  else begin
    prev_bpm_clk <= 0;
    enable_ctr <= 0;
  end

  logic [3:0] raw_play_smpl;
  assign raw_play_smpl = pb[3:0];
  
  logic [3:0] play_smpl;
  always_ff @(posedge hz2m, posedge reset) begin
    if (reset)
      play_smpl <= 0;
    else begin
      case (mode)
        2'd0: play_smpl <= 4'b0;
        2'd1: play_smpl <= ((enable_ctr <= 900000) ? edit_play_smpl[seq_sel] : 4'b0) | raw_play_smpl;
        2'd2: play_smpl <= raw_play_smpl;
        default: play_smpl <= 4'b0;
      endcase
    end
  end
  
  logic mhz16;
  logic [7:0] sample_data [3:0];
  
  clkdiv #(20) sample_clk (.clk(hz2m), .rst(reset), .lim(20'd128), .hzX(mhz16));
  sample #(
    .SAMPLE_FILE("../audio/kick.mem"),
    .SAMPLE_LEN(4000)
  ) sample_kick (
    .clk(mhz16),
    .rst(reset),
    .enable(play_smpl[3]),
    .out(sample_data[0])
  );

  sample #(
    .SAMPLE_FILE("../audio/clap.mem"),
    .SAMPLE_LEN(4000)
  ) sample_clap (
    .clk(mhz16),
    .rst(reset),
    .enable(play_smpl[2]),
    .out(sample_data[1])
  );
  
  sample #(
    .SAMPLE_FILE("../audio/hihat.mem"),
    .SAMPLE_LEN(4000)
  ) sample_hihat (
    .clk(mhz16),
    .rst(reset),
    .enable(play_smpl[1]),
    .out(sample_data[2])
  );
 
  sample #(
    .SAMPLE_FILE("../audio/snare.mem"),
    .SAMPLE_LEN(4000)
  ) sample_snare (
    .clk(mhz16),
    .rst(reset),
    .enable(play_smpl[0]),
    .out(sample_data[3])
  );
  
  logic [7:0] sample_sum1, sample_sum2, final_sum;
  
  always_comb begin
      sample_sum1 = sample_data[0] + sample_data[1];
      sample_sum2 = sample_data[2] + sample_data[3];
  	
      if (sample_data[0][7] == 1 && sample_data[1][7] == 1 && sample_sum1[7] == 0)
          sample_sum1 = -128;
      else if (sample_data[0][7] == 0 && sample_data[1][7] == 0 && sample_sum1[7] == 1)
  	  sample_sum2 = 127;
  		
      if (sample_data[2][7] == 1 && sample_data[3][7] == 1 && sample_sum2[7] == 0)
          sample_sum1 = -128;
      else if (sample_data[2][7] == 0 && sample_data[3][7] == 0 && sample_sum2[7] == 1)
  	  sample_sum2 = 127;
  
      final_sum = sample_sum1 + sample_sum2;
      if (sample_sum1[7] == 1 && sample_sum2[7] == 1 && final_sum[7] == 0)
          sample_sum1 = -128;
      else if (sample_sum1[7] == 0 && sample_sum2[7] == 0 && final_sum[7] == 1)
  	  sample_sum2 = 127;
      final_sum = ((final_sum) ^ 8'd128) >> 2;
  end
  
  pwm #(64) pwm_inst (.clk(hz2m), .rst(reset), .enable(1'b1), .duty_cycle(final_sum[5:0]), .counter(), .pwm_out(right[0]));

endmodule

module scankey (
  input logic clk, rst, 
  input logic [19:0] in, 
  output logic [4:0] out, 
  output logic strobe
);

  assign out[0] = (in[1] | in[3] | in[5] | in[7] | in[9] | in[11] | in[13] | in[15] | in[17] | in[19]);
  assign out[1] = (in[2] | in[3] | in[6] | in[7] | in[10] | in[11] | in[14] | in[15] | in[18] | in[19]);
  assign out[2] = (in[4] | in[5] | in[6] | in[7] | in[12] | in[13] | in[14] | in[15]);
  assign out[3] = (in[8] | in[9] | in[10] | in[11] | in[12] | in[13] | in[14] | in[15]);
  assign out[4] = (in[16] | in[17] | in[18] | in[19]);
  
  logic [1:0] delay;
  always_ff @ (posedge clk, posedge rst) begin
    if (rst) begin
      delay <= 2'b0;
    end else begin
      delay <= (delay << 1) | {1'b0, |in};
    end
  end
  
  assign strobe = delay[1];
endmodule

module clkdiv #(
    parameter BITLEN = 8
) (
    input logic clk, rst, 
    input logic [BITLEN-1:0] lim,
    output logic hzX
);

  logic [BITLEN-1:0] ctr;
  logic hz;
  logic [BITLEN-1:0] next_ctr; // next-state values

  always_ff @ (posedge clk, posedge rst) begin
    if (rst) begin
      hz <= 0;
      ctr <= 0;
    end else begin
      hz <= ctr == lim;
      ctr <= next_ctr;
    end
  end
  
  always_ff @ (posedge hz, posedge rst) begin
    if (rst)
      hzX <= 0;
    else
      hzX <= ~hzX;
  end
  
  // Counter
  always_comb begin
    if (ctr ==  lim) begin
      next_ctr = 0;
    end
    else begin
      next_ctr = ctr + 1;
    end
  end
endmodule

module prienc8to3 (
  input logic [7:0] in, 
  output logic [2:0] out
);

  assign out = in[7] == 1 ? 3'b111 :
                 in[6] == 1 ? 3'b110 :
                 in[5] == 1 ? 3'b101 :
                 in[4] == 1 ? 3'b100 :
                 in[3] == 1 ? 3'b011 :
                 in[2] == 1 ? 3'b010 :
                 in[1] == 1 ? 3'b001 :
                 in[0] == 1 ? 3'b000 :
                             3'b000;
endmodule

module sequencer (
  input logic clk, rst, srst, go_left, go_right, 
  output logic [7:0] seq_out
);

  logic [7:0] next_seq_out;
  
  always_ff @ (posedge clk, posedge rst) begin
    if (rst)
      seq_out <= 8'h80;
    else
      seq_out <= next_seq_out;
  end
  
  always_comb begin
    if (srst)
      next_seq_out = 8'h80;
    else if (go_left)
      next_seq_out = {seq_out[6:0], seq_out[7]};
    else if (go_right)
      next_seq_out = {seq_out[0], seq_out[7:1]};
    else
      next_seq_out = seq_out;
  end
endmodule

module sequence_editor (
  input logic clk, rst, 
  input logic [1:0] mode, 
  input logic [2:0] set_time_idx, 
  input logic [3:0] tgl_play_smpl,
  output logic [3:0] seq_smpl_1, seq_smpl_2, seq_smpl_3, seq_smpl_4,
         seq_smpl_5, seq_smpl_6, seq_smpl_7, seq_smpl_8 
);
  
  logic [3:0] seq_smpl [7:0];
  
  assign {seq_smpl_8, seq_smpl_7, seq_smpl_6, seq_smpl_5, 
          seq_smpl_4, seq_smpl_3, seq_smpl_2, seq_smpl_1} 
          = {seq_smpl[7], seq_smpl[6], seq_smpl[5], seq_smpl[4], 
          seq_smpl[3], seq_smpl[2], seq_smpl[1], seq_smpl[0]};

  integer i;
  always_ff @ (posedge clk, posedge rst) begin
    if (rst) begin
      for (i = 0; i < 8; i++) begin
        seq_smpl[i] <= 4'b0;
      end
    end else begin
      if (mode == 2'd0)
        seq_smpl[set_time_idx] <= seq_smpl[set_time_idx] ^ tgl_play_smpl;
    end
  end
endmodule


module pwm #(
    parameter int CTRVAL = 256,
    parameter int CTRLEN = $clog2(CTRVAL)
)
(
    input logic clk, rst, enable,
    input logic [CTRLEN-1:0] duty_cycle,
    output logic [CTRLEN-1:0] counter,
    output logic pwm_out
);
        

  always_ff @(posedge clk, posedge rst) begin
    if (rst)
      counter <= 0;
    else begin
      if (enable)
        counter <= counter + 1;
    end
  end
  
  assign pwm_out = (duty_cycle == CTRLEN'(CTRVAL - 1)) ? 1 : 
                   (duty_cycle == 0) ? 1 : 
                   (counter <= duty_cycle);
endmodule

module sample #(
  parameter SAMPLE_FILE = "../audio/kick.mem",
  parameter SAMPLE_LEN = 4000
)
(
  input clk, rst, enable,
  output logic [7:0] out
);

  logic [7:0] audio_mem [4095:0];
  initial $readmemh(SAMPLE_FILE, audio_mem, 0, SAMPLE_LEN);

  logic [11:0] counter;
  logic prev_en;
  always_ff @(posedge clk, posedge rst) begin
    if (rst) 
      counter <= 12'b0;
    else begin
      prev_en <= enable;
      if (prev_en && enable) begin
        counter <= counter + 1; 
        if (counter == SAMPLE_LEN) 
          counter <= 12'b0;
      end else if (prev_en && ~enable)
        counter <= 12'b0;
    end
  end

  always_ff @(posedge clk) begin
      out <= audio_mem[counter];
  end
endmodule


module controller (
    input clk, rst,
    input set_edit, set_play, set_raw,
    output logic [1:0] mode
);

    typedef enum logic [1:0] { EDIT = 2'd0, PLAY = 2'd1, RAW = 2'd2 } sysmode_t;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            mode <= EDIT;
        end else begin
            if (set_edit) begin
                mode <= EDIT;
            end else if (set_play) begin
                mode <= PLAY;
            end else if (set_raw) begin
                mode <= RAW;
            end
        end
    end
endmodule
