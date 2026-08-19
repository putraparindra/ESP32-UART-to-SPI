// zybo_top.sv
//
// Top module BARU untuk build ZYBO -- membungkus modul resmi "pulpino"
// (fpga/rtl/pulpino_wrap.v) dan HANYA mengekspos 8 sinyal yang benar-benar
// kita pakai (SPI Slave 4 sinyal + clk + rst_n + fetch_enable_i + gpio_out
// 1 bit untuk LED). 131 port lain (GPIO 31 bit sisanya, UART, I2C, SPI
// Master AXI terpisah, JTAG, dst) di-tie off di sini -- input diikat ke
// konstanta aman, output dibiarkan dangling (tidak dipakai) -- supaya
// Vivado TIDAK mencoba mencari pin fisik untuk semuanya (itu penyebab
// error "IO placement is infeasible: 139 ports > 50 pin tersedia").
//
// File ini yang jadi TOP di project Vivado, BUKAN "pulpino" langsung.

module zybo_top
  (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        fetch_enable_i,

    input  logic        spi_clk_i,
    input  logic        spi_cs_i,
    input  logic        spi_sdi0_i,
    output logic        spi_sdo0_o,

    output logic        gpio_out0
  );

  // ------------------------------------------------------------------
  // Sinyal internal untuk port yang tidak dipakai (di-tie off)
  // ------------------------------------------------------------------
  wire [1:0]  spi_mode_o_unused;
  wire        spi_sdo1_o_unused, spi_sdo2_o_unused, spi_sdo3_o_unused;

  wire        spi_master_clk_o_unused;
  wire        spi_master_csn0_o_unused, spi_master_csn1_o_unused;
  wire        spi_master_csn2_o_unused, spi_master_csn3_o_unused;
  wire [1:0]  spi_master_mode_o_unused;
  wire        spi_master_sdo0_o_unused, spi_master_sdo1_o_unused;
  wire        spi_master_sdo2_o_unused, spi_master_sdo3_o_unused;

  wire        uart_tx_unused, uart_rts_unused, uart_dtr_unused;

  wire        scl_o_unused, scl_oen_o_unused;
  wire        sda_o_unused, sda_oen_o_unused;

  wire [31:0] gpio_out_full;
  wire [31:0] gpio_dir_unused;

  wire        tdo_o_unused;

  assign gpio_out0 = gpio_out_full[0];

  // ------------------------------------------------------------------
  // Instansiasi modul resmi "pulpino"
  // ------------------------------------------------------------------
  pulpino pulpino_i
  (
    .clk                ( clk                ),
    .rst_n              ( rst_n              ),

    .fetch_enable_i     ( fetch_enable_i     ),

    .spi_clk_i          ( spi_clk_i          ),
    .spi_cs_i           ( spi_cs_i           ),
    .spi_mode_o         ( spi_mode_o_unused  ),
    .spi_sdo0_o         ( spi_sdo0_o         ),
    .spi_sdo1_o         ( spi_sdo1_o_unused  ),
    .spi_sdo2_o         ( spi_sdo2_o_unused  ),
    .spi_sdo3_o         ( spi_sdo3_o_unused  ),
    .spi_sdi0_i         ( spi_sdi0_i         ),
    .spi_sdi1_i         ( 1'b0               ),
    .spi_sdi2_i         ( 1'b0               ),
    .spi_sdi3_i         ( 1'b0               ),

    .spi_master_clk_o   ( spi_master_clk_o_unused  ),
    .spi_master_csn0_o  ( spi_master_csn0_o_unused ),
    .spi_master_csn1_o  ( spi_master_csn1_o_unused ),
    .spi_master_csn2_o  ( spi_master_csn2_o_unused ),
    .spi_master_csn3_o  ( spi_master_csn3_o_unused ),
    .spi_master_mode_o  ( spi_master_mode_o_unused ),
    .spi_master_sdo0_o  ( spi_master_sdo0_o_unused ),
    .spi_master_sdo1_o  ( spi_master_sdo1_o_unused ),
    .spi_master_sdo2_o  ( spi_master_sdo2_o_unused ),
    .spi_master_sdo3_o  ( spi_master_sdo3_o_unused ),
    .spi_master_sdi0_i  ( 1'b0               ),
    .spi_master_sdi1_i  ( 1'b0               ),
    .spi_master_sdi2_i  ( 1'b0               ),
    .spi_master_sdi3_i  ( 1'b0               ),

    .uart_tx            ( uart_tx_unused     ),
    .uart_rx            ( 1'b1               ), // idle level UART = HIGH
    .uart_rts           ( uart_rts_unused    ),
    .uart_dtr           ( uart_dtr_unused    ),
    .uart_cts           ( 1'b0               ),
    .uart_dsr           ( 1'b0               ),

    .scl_i              ( 1'b1               ),
    .scl_o              ( scl_o_unused       ),
    .scl_oen_o          ( scl_oen_o_unused   ),
    .sda_i              ( 1'b1               ),
    .sda_o              ( sda_o_unused       ),
    .sda_oen_o          ( sda_oen_o_unused   ),

    .gpio_in            ( 32'h0              ),
    .gpio_out           ( gpio_out_full      ),
    .gpio_dir           ( gpio_dir_unused    ),

    .tck_i              ( 1'b0               ),
    .trstn_i            ( 1'b1               ),
    .tms_i              ( 1'b0               ),
    .tdi_i              ( 1'b0               ),
    .tdo_o              ( tdo_o_unused       )
  );

endmodule
