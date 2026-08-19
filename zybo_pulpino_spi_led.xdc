## =====================================================================
## ZYBO Constraints - SPI Slave PULPino (Pmod JE) + GPIO LED (LD0)
## =====================================================================
## Sesuaikan nama port di sebelah kanan (get_ports "...") dengan nama
## port pada top-level wrapper Vivado kamu (misalnya kalau top-level
## kamu menamai ulang sinyal PULPino, ganti string-nya di sini).
##
## Pmod JE = Standard Pmod, terhubung ke PL lewat resistor seri 200 ohm,
## aman untuk eksperimen SPI kecepatan rendah/menengah.
## Pinout JE (dari ZYBO Reference Manual, Table 9):
##   JE1: V12   JE2: W16   JE3: J15   JE4: H15
##   JE7: V13   JE8: U17   JE9: T17   JE10: Y17
## =====================================================================

## ---------------------------------------------------------------------
## SPI Slave PULPino -> Pmod JE (4 sinyal standar SPI)
## ---------------------------------------------------------------------
# spi_sclk  : clock dari ESP32 (input ke PULPino)
set_property PACKAGE_PIN V12 [get_ports {spi_sclk}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_sclk}]

# spi_cs    : chip select dari ESP32 (input ke PULPino, aktif LOW)
set_property PACKAGE_PIN W16 [get_ports {spi_cs}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_cs}]

# spi_sdi0  : MOSI, data dari ESP32 ke PULPino (input)
set_property PACKAGE_PIN J15 [get_ports {spi_sdi0}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_sdi0}]

# spi_sdo0  : MISO, data dari PULPino ke ESP32 (output)
set_property PACKAGE_PIN H15 [get_ports {spi_sdo0}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_sdo0}]

## Catatan: spi_sdi1-3 / spi_sdo1-3 dan spi_mode[1:0] TIDAK perlu
## di-constrain ke pin fisik selama kamu memakai mode SPI standar
## (bukan QSPI/QuadSPI). Cukup 4 sinyal di atas.

## ---------------------------------------------------------------------
## GPIO PULPino -> LED0 fisik ZYBO (LD0), untuk bit gpio_out[0]
## ---------------------------------------------------------------------
## Ganti "gpio_out[0]" di bawah sesuai nama port top-level kamu kalau
## gpio_out di-flatten jadi bit-bit terpisah (misal gpio_out_0).
set_property PACKAGE_PIN M14 [get_ports {gpio_out[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_out[0]}]

## ---------------------------------------------------------------------
## Timing constraint untuk spi_sclk
## ---------------------------------------------------------------------
## spi_sclk adalah clock eksternal asinkron (dari ESP32), bukan clock
## sistem PULPino. Vivado perlu tahu ini supaya static timing analysis
## tidak menganggapnya generic combinational net, dan supaya tidak
## menganalisis cross-clock path ke axi_aclk seolah-olah sinkron
## (axi_spi_slave sudah menangani clock domain crossing lewat dual-clock
## FIFO internal, jadi path ini memang harus dianggap asynchronous).
##
## Ganti 1000000 (1 MHz) sesuai SPI_CLOCK_HZ yang dipakai di firmware ESP32.
create_clock -period 1000.000 -name spi_sclk_virtual [get_ports {spi_sclk}]

## Tandai clock spi_sclk dan clock sistem PULPino (misal sys_clk atau
## clk_fpga_0 dari Zynq PS) sebagai asynchronous group, supaya Vivado
## tidak coba menutup timing path di antara keduanya.
## Ganti "clk_fpga_0" sesuai nama clock sistem PULPino di project kamu.
set_clock_groups -asynchronous \
  -group [get_clocks spi_sclk_virtual] \
  -group [get_clocks clk_fpga_0]
