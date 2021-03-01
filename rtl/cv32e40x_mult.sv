// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Matthias Baer - baermatt@student.ethz.ch                   //
//                                                                            //
// Additional contributions by:                                               //
//                 Andreas Traber - atraber@student.ethz.ch                   //
//                 Michael Gautschi - gautschi@iis.ee.ethz.ch                 //
//                                                                            //
// Design Name:    Subword multiplier and MAC                                 //
// Project Name:   RI5CY                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Advanced MAC unit for PULP.                                //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module cv32e40x_mult import cv32e40x_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        enable_i,
  input  mul_opcode_e operator_i,

  // integer and short multiplier
  input  logic [ 1:0] short_signed_i,

  input  logic [31:0] op_a_i,
  input  logic [31:0] op_b_i,
  input  logic [31:0] op_c_i,

  output logic [31:0] result_o,

  output logic        multicycle_o,
  output logic        ready_o,
  input  logic        ex_ready_i
);


  ///////////////////////////////////////////////////////////////
  //  ___ _  _ _____ ___ ___ ___ ___   __  __ _   _ _  _____   //
  // |_ _| \| |_   _| __/ __| __| _ \ |  \/  | | | | ||_   _|  //
  //  | || .  | | | | _| (_ | _||   / | |\/| | |_| | |__| |    //
  // |___|_|\_| |_| |___\___|___|_|_\ |_|  |_|\___/|____|_|    //
  //                                                           //
  ///////////////////////////////////////////////////////////////

  // MULH control signals
  logic        mulh_shift;
  logic        mulh_carry_q;
  logic        mulh_save;

  // MULH State variables
  mult_state_e mulh_state;
  mult_state_e mulh_state_next;

  // MULH Part select operands
  logic [16:0] mulh_al;
  logic [16:0] mulh_bl;
  logic [16:0] mulh_ah;
  logic [16:0] mulh_bh;

  // MULH Operators
  logic [16:0] mulh_a;
  logic [16:0] mulh_b;
  logic [32:0] mulh_c;

  // MULH Intermediate Results
  logic [33:0] mulh_mul;
  logic [33:0] mulh_sum;
  logic [33:0] mulh_sum_shifted;
  logic [33:0] mulh_result;


  assign mulh_al[15:0] = op_a_i[15:0];
  assign mulh_bl[15:0] = op_b_i[15:0];
  assign mulh_ah[15:0] = op_a_i[31:16];
  assign mulh_bh[15:0] = op_b_i[31:16];

  assign mulh_al[16] = 1'b0;
  assign mulh_bl[16] = 1'b0;
  assign mulh_ah[16] = short_signed_i[0] && op_a_i[31];
  assign mulh_bh[16] = short_signed_i[1] && op_b_i[31];

  assign mulh_c           = $signed({mulh_carry_q, op_c_i});

  assign mulh_mul         = $signed(mulh_a) * $signed(mulh_b);
  assign mulh_sum         = $signed(mulh_mul) + $signed(mulh_c);
  assign mulh_sum_shifted = $signed(mulh_sum) >>> 16;

  assign mulh_result      = (mulh_shift) ? mulh_sum_shifted : mulh_sum;

  always_comb
  begin
    mulh_shift       = 1'b0;
    mulh_save        = 1'b0;
    multicycle_o     = 1'b0;

    mulh_a           = mulh_al;
    mulh_b           = mulh_bl;
    mulh_state_next  = mulh_state;

    case (mulh_state)
      ALBL: begin
        mulh_shift        = 1'b1;
        if ((operator_i == MUL_H) && enable_i) begin
          multicycle_o    = 1'b1;
          mulh_state_next = ALBH;
        end
      end

      ALBH: begin
        multicycle_o     = 1'b1;
        mulh_save        = 1'b1;

        mulh_a           = mulh_al;
        mulh_b           = mulh_bh;
        mulh_state_next  = AHBL;
      end

      AHBL: begin
        multicycle_o     = 1'b1;
        mulh_shift       = 1'b1;

        mulh_a           = mulh_ah;
        mulh_b           = mulh_bl;
        mulh_state_next  = AHBH;
      end

      AHBH: begin
        mulh_a            = mulh_ah;
        mulh_b            = mulh_bh;
        if (ex_ready_i)
          mulh_state_next = ALBL;
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk, negedge rst_n)
  begin
    if (~rst_n)
    begin
      mulh_state      <= ALBL;
      mulh_carry_q <= 1'b0;
    end else begin
      mulh_state      <= mulh_state_next;
      mulh_carry_q    <= mulh_save && mulh_result[32];
    end
  end

  // 32x32 = 32-bit multiplier
  logic [31:0] int_result;

  assign int_result = $signed(op_a_i) * $signed(op_b_i);

  ////////////////////////////////////////////////////////
  //   ____                 _ _     __  __              //
  //  |  _ \ ___  ___ _   _| | |_  |  \/  |_   ___  __  //
  //  | |_) / _ \/ __| | | | | __| | |\/| | | | \ \/ /  //
  //  |  _ <  __/\__ \ |_| | | |_  | |  | | |_| |>  <   //
  //  |_| \_\___||___/\__,_|_|\__| |_|  |_|\__,_/_/\_\  //
  //                                                    //
  ////////////////////////////////////////////////////////

  always_comb
  begin
    if (operator_i == MUL_M32) begin
      result_o = int_result[31:0];
    end else begin
      result_o = mulh_result;
    end
  end

  assign ready_o = !multicycle_o;

endmodule
