// PATCHED VERSION v2 -- lihat catatan di bawah
//
// Percobaan patch v1 (atribut ram_style="block" di atas array packed 2D)
// TERNYATA TIDAK CUKUP -- Vivado tetap mensintesis jadi ratusan ribu
// flip-flop individual (place_design gagal karena over-utilized 10-15x
// lipat dari kapasitas chip). Root cause sebenarnya: struktur array
// packed 2D (logic [DATA_WIDTH/8-1:0][7:0] mem[words]) TIDAK COCOK
// dengan template inferensi BRAM Vivado, sehingga atribut ram_style
// diabaikan diam-diam (tidak ada error/warning yang jelas).
//
// Patch v2 ini menulis ulang total memakai template RESMI Xilinx UG901
// (array 1 dimensi flat, bukan nested 2D) yang PALING TERJAMIN dikenali
// sebagai pola inferensi BRAM oleh Vivado.
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
    parameter NUM_WORDS  = 256   // dalam byte (total ukuran memori)
  )(
    input  logic                    clk,

    input  logic                    en_i,
    input  logic [ADDR_WIDTH-1:0]   addr_i,
    input  logic [DATA_WIDTH-1:0]   wdata_i,
    output logic [DATA_WIDTH-1:0]   rdata_o,
    input  logic                    we_i,
    input  logic [DATA_WIDTH/8-1:0] be_i
  );

  localparam words   = NUM_WORDS/(DATA_WIDTH/8);
  localparam SHIFT    = $clog2(DATA_WIDTH/8);
  localparam WORD_AW  = ADDR_WIDTH - SHIFT;

  // Array 1 dimensi flat -- template resmi Xilinx UG901 untuk inferensi BRAM
  (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:words-1];

  logic [WORD_AW-1:0] addr;
  assign addr = addr_i[ADDR_WIDTH-1:SHIFT];

  integer i;

  always_ff @(posedge clk) begin
    if (en_i) begin
      if (we_i) begin
        for (i = 0; i < DATA_WIDTH/8; i = i + 1) begin
          if (be_i[i])
            mem[addr][i*8 +: 8] <= wdata_i[i*8 +: 8];
        end
      end
      rdata_o <= mem[addr];
    end
  end

endmodule
