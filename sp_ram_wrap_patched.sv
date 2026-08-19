// PATCHED VERSION -- lihat catatan di bawah
//
// Versi asli file ini (rtl/sp_ram_wrap.sv) meng-hardcode instansiasi IP
// Xilinx 'xilinx_mem_8192x32' di dalam blok `ifdef PULP_FPGA_EMUL, TANPA
// PEDULI parameter RAM_SIZE yang sebenarnya (di PULPino default RAM_SIZE =
// 32768 kata untuk Instr/Data RAM, bukan 8192). Ini menyebabkan error
// "module 'xilinx_mem_8192x32' not found" saat sintesis untuk RAM 32768,
// dan bahkan kalau IP itu digenerate manual pun ukurannya akan salah/tidak
// cukup untuk RAM_SIZE=32768.
//
// Patch ini menghapus jalur `ifdef PULP_FPGA_EMUL sepenuhnya dan SELALU
// memakai module generic 'sp_ram' (rtl/components/sp_ram.sv) yang portable
// -- Vivado otomatis meng-infer Block RAM (BRAM) dari situ tanpa perlu IP
// Xilinx yang di-generate manual lewat Vivado IP Catalog.
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

`include "config.sv"

module sp_ram_wrap
  #(
    parameter RAM_SIZE   = 32768,              // in bytes
    parameter ADDR_WIDTH = $clog2(RAM_SIZE),
    parameter DATA_WIDTH = 32
  )(
    // Clock and Reset
    input  logic                    clk,
    input  logic                    rstn_i,
    input  logic                    en_i,
    input  logic [ADDR_WIDTH-1:0]   addr_i,
    input  logic [DATA_WIDTH-1:0]   wdata_i,
    output logic [DATA_WIDTH-1:0]   rdata_o,
    input  logic                    we_i,
    input  logic [DATA_WIDTH/8-1:0] be_i,
    input  logic                    bypass_en_i
  );

  sp_ram
  #(
    .ADDR_WIDTH ( ADDR_WIDTH ),
    .DATA_WIDTH ( DATA_WIDTH ),
    .NUM_WORDS  ( RAM_SIZE   )
  )
  sp_ram_i
  (
    .clk     ( clk       ),

    .en_i    ( en_i      ),
    .addr_i  ( addr_i    ),
    .wdata_i ( wdata_i   ),
    .rdata_o ( rdata_o   ),
    .we_i    ( we_i      ),
    .be_i    ( be_i      )
  );

endmodule
