`default_nettype none

module top (
  // I/O ports
  input  logic hz100, reset,
  input  logic [20:0] pb,
  output logic [7:0] left, right,
         ss7, ss6, ss5, ss4, ss3, ss2, ss1, ss0,
  output logic red, green, blue,

  // UART ports
  output logic [7:0] txdata,
  input  logic [7:0] rxdata,
  output logic txclk, rxclk,
  input  logic txready, rxready
);

  
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

module clkdiv (
  input logic clk, rst, 
  input logic [7:0] lim, 
  output logic hzX
);

  logic [7:0] ctr;
  logic hz;
  logic [7:0] next_ctr; // next-state values

  always_ff @ (posedge clk, posedge rst) begin
    if (rst) begin
      hz <= 1'b0;
      ctr <= 8'b0;
    end else begin
      hz <= ctr == lim;
      ctr <= next_ctr;
    end
  end
  
  always_ff @ (posedge hz, posedge rst) begin
    if (rst)
      hzX <= 1'b0;
    else
      hzX <= ~hzX;
  end
  
  // Counter
  always_comb begin // next-state equations
    if (ctr ==  lim) begin
      next_ctr = 8'b0;
    end
    else begin
      next_ctr[0] = ~ctr[0];
      next_ctr[1] = ctr[1] ^ ctr[0];
      next_ctr[2] = ctr[2] ^ (&(ctr[1:0]));
      next_ctr[3] = ctr[3] ^ (&(ctr[2:0]));
      next_ctr[4] = ctr[4] ^ (&(ctr[3:0]));
      next_ctr[5] = ctr[5] ^ (&(ctr[4:0]));
      next_ctr[6] = ctr[6] ^ (&(ctr[5:0]));
      next_ctr[7] = ctr[7] ^ (&(ctr[6:0]));
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
      next_seq_out = seq_out << 1;
    else if (go_right)
      next_seq_out = seq_out >> 1;
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
  always_ff @ (posedge clk) begin
    seq_smpl_1 <= seq_smpl[0];
    seq_smpl_2 <= seq_smpl[1];
    seq_smpl_3 <= seq_smpl[2];
    seq_smpl_4 <= seq_smpl[3];
    seq_smpl_5 <= seq_smpl[4];
    seq_smpl_6 <= seq_smpl[5];
    seq_smpl_7 <= seq_smpl[6];
    seq_smpl_8 <= seq_smpl[7];
  end
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

module pwm (
  input logic clk, rst, enable,
  input logic [7:0] duty_cycle,
  output logic [7:0] counter,
  output logic pwm_out
);

  always_ff @(posedge clk, posedge rst) begin
    if (rst)
      counter <= 8'b0;
    else begin
      if (enable)
        counter <= counter + 1;
    end
  end
  
  assign pwm_out = (duty_cycle == 8'b11111111) ? 1'b1 : 
                   (duty_cycle == 8'b0) ? 1'b0 : 
                   (counter <= duty_cycle);
endmodule

module sample #(
  parameter SAMPLE_FILE = "kick.mem",
  parameter SAMPLE_LEN = 4000
)(
  input clk, rst, enable,
  output logic [7:0] out
);

  logic [7:0] audio_mem [4095:0];
  initial $readmemh(SAMPLE_FILE, audio_mem, 0, SAMPLE_LEN);

  logic counter [11:0];
  logic prev_en;
  always_ff @(posedge clk, posedge rst) begin
    if (rst) 
      counter <= 12'b0;
    else begin
      prev_en <= enable;
      
      if (prev_en && enable) begin
        counter <= counter + 1; 
      
        if (counter == SAMPLE_LEN - 1) 
          counter <= 12'b0;
      end else if (prev_en && ~enable) begin
                counter <= 12'b0;
      end
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
