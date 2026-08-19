// PATCHED VERSION v2 -- lihat catatan di sp_ram_patched_v2.sv, alasan
// sama: array 1D flat sesuai template resmi Xilinx UG901, bukan lagi
// nested 2D packed array yang gagal ke-infer jadi BRAM.
//
// Copyright 2017 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

module dp_ram
  #(
    parameter ADDR_WIDTH = 8
  )(
    input  logic clk,

    input  logic                   en_a_i,
    input  logic [ADDR_WIDTH-1:0]  addr_a_i,
    input  logic [31:0]            wdata_a_i,
    output logic [31:0]            rdata_a_o,
    input  logic                   we_a_i,
    input  logic [3:0]             be_a_i,

    input  logic                   en_b_i,
    input  logic [ADDR_WIDTH-1:0]  addr_b_i,
    input  logic [31:0]            wdata_b_i,
    output logic [31:0]            rdata_b_o,
    input  logic                   we_b_i,
    input  logic [3:0]             be_b_i
  );

  localparam words = 2**ADDR_WIDTH;

  (* ram_style = "block" *) logic [31:0] mem [0:words-1];

  integer i;

  always_ff @(posedge clk) begin
    if (en_a_i) begin
      if (we_a_i) begin
        for (i = 0; i < 4; i = i + 1) begin
          if (be_a_i[i])
            mem[addr_a_i][i*8 +: 8] <= wdata_a_i[i*8 +: 8];
        end
      end
      rdata_a_o <= mem[addr_a_i];
    end

    if (en_b_i) begin
      if (we_b_i) begin
        for (i = 0; i < 4; i = i + 1) begin
          if (be_b_i[i])
            mem[addr_b_i][i*8 +: 8] <= wdata_b_i[i*8 +: 8];
        end
      end
      rdata_b_o <= mem[addr_b_i];
    end
  end

endmodule
