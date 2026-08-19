// PATCHED VERSION -- lihat catatan di bawah
//
// Versi asli file ini (rtl/components/sp_ram.sv) memakai array packed 2D
// (logic [DATA_WIDTH/8-1:0][7:0] mem[words]) untuk memori byte-addressable.
// Pola ini membingungkan heuristik auto-inferensi BRAM Vivado -- alih-alih
// dipetakan ke Block RAM fisik, malah disintesis jadi puluhan ribu flip-flop
// individual (untuk RAM 8192 word x 32-bit, ini artinya ratusan ribu bit
// register -- sangat lambat disintesis dan boros resource FPGA).
//
// Patch ini menambahkan atribut (* ram_style = "block" *) yang MEMAKSA
// Vivado memetakan array 'mem' ke Block RAM (BRAM) fisik, terlepas dari
// bagaimana heuristik auto-inferensinya membaca pola kode di atas.
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

module sp_ram
  #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter NUM_WORDS  = 256
  )(
    // Clock and Reset
    input  logic                    clk,

    input  logic                    en_i,
    input  logic [ADDR_WIDTH-1:0]   addr_i,
    input  logic [DATA_WIDTH-1:0]   wdata_i,
    output logic [DATA_WIDTH-1:0]   rdata_o,
    input  logic                    we_i,
    input  logic [DATA_WIDTH/8-1:0] be_i
  );

  localparam words = NUM_WORDS/(DATA_WIDTH/8);

  (* ram_style = "block" *) logic [DATA_WIDTH/8-1:0][7:0] mem[words];
  logic [DATA_WIDTH/8-1:0][7:0] wdata;
  logic [ADDR_WIDTH-1-$clog2(DATA_WIDTH/8):0] addr;

  integer i;


  assign addr = addr_i[ADDR_WIDTH-1:$clog2(DATA_WIDTH/8)];


  always @(posedge clk)
  begin
    if (en_i && we_i)
    begin
      for (i = 0; i < DATA_WIDTH/8; i++) begin
        if (be_i[i])
          mem[addr][i] <= wdata[i];
      end
    end

    rdata_o <= mem[addr];
  end

  genvar w;
  generate for(w = 0; w < DATA_WIDTH/8; w++)
    begin
      assign wdata[w] = wdata_i[(w+1)*8-1:w*8];
    end
  endgenerate

endmodule
