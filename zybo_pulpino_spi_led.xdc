## =====================================================================
## ZYBO Constraints - top module "pulpino" (fpga/rtl/pulpino_wrap.v)
## SPI Slave di Pmod JE + LED0 untuk gpio_out0
## =====================================================================
## Nama port di bawah ini SUDAH DISESUAIKAN dengan port asli top module
## "pulpino" di fpga/rtl/pulpino_wrap.v -- JANGAN diganti kecuali kamu
## mengganti nama port itu sendiri di wrapper.
##
## Pmod JE = Standard Pmod, terhubung ke PL lewat resistor seri 200 ohm.
## Pinout JE (ZYBO Reference Manual, Table 9):
##   JE1: V12   JE2: W16   JE3: J15   JE4: H15
##   JE7: V13   JE8: U17   JE9: T17   JE10: Y17
## =====================================================================

## ---------------------------------------------------------------------
## SPI Slave (port asli: spi_clk_i, spi_cs_i, spi_sdi0_i, spi_sdo0_o)
## ---------------------------------------------------------------------
set_property PACKAGE_PIN V12 [get_ports {spi_clk_i}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_clk_i}]

## spi_clk_i masuk lewat pin biasa (bukan CCIO/clock-capable pin), jadi
## tidak ada jalur dedicated ke BUFG. Ini normal untuk clock eksternal
## dari mikrokontroler yang masuk lewat Pmod -- bukan lewat pin clock
## khusus. Karena kecepatannya rendah (1 MHz dari ESP32, jauh di bawah
## batas kemampuan fabric non-dedicated), memakai rute non-dedicated
## aman dan merupakan solusi yang disarankan langsung oleh Vivado.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets spi_clk_i_IBUF]

set_property PACKAGE_PIN W16 [get_ports {spi_cs_i}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_cs_i}]

set_property PACKAGE_PIN J15 [get_ports {spi_sdi0_i}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_sdi0_i}]

set_property PACKAGE_PIN H15 [get_ports {spi_sdo0_o}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_sdo0_o}]

## spi_sdi1_i/spi_sdi2_i/spi_sdi3_i dan spi_mode_o TIDAK perlu di-constrain
## selama pakai SPI standar (bukan QSPI).

## ---------------------------------------------------------------------
## Clock sistem PULPino -> pin referensi 125 MHz PL (L16), lihat
## ZYBO Reference Manual bagian "Clock Sources"
## ---------------------------------------------------------------------
set_property PACKAGE_PIN L16 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]

## ---------------------------------------------------------------------
## Reset (aktif LOW) -> switch SW1 (P15), BUKAN tombol
## PENTING: tombol ZYBO aktif-HIGH saat ditekan (default TIDAK ditekan =
## LOW). Karena rst_n butuh HIGH supaya SoC TIDAK dalam kondisi reset,
## pakai tombol berarti PULPino selalu ter-reset kecuali ditekan terus
## menerus. Pakai SWITCH supaya bisa disetel stabil HIGH tanpa ditahan.
## SETEL SW1 = HIGH/ON untuk melepas reset (supaya PULPino berjalan normal).
## ---------------------------------------------------------------------
set_property PACKAGE_PIN P15 [get_ports {rst_n}]
set_property IOSTANDARD LVCMOS33 [get_ports {rst_n}]

## ---------------------------------------------------------------------
## fetch_enable_i -> slide switch SW0 (G15), supaya core bisa
## di-start manual setelah reset & SPI siap
## ---------------------------------------------------------------------
set_property PACKAGE_PIN G15 [get_ports {fetch_enable_i}]
set_property IOSTANDARD LVCMOS33 [get_ports {fetch_enable_i}]

## ---------------------------------------------------------------------
## GPIO PULPino -> LED0 fisik ZYBO (LD0)
## TERVERIFIKASI dari source rtl/peripherals.sv dan ips/apb/apb_gpio:
## register PADOUT (yang ditulis lewat SPI Slave) diteruskan mentah-mentah
## tanpa remapping apa pun ke gpio_out[31:0] (apb_gpio.sv: r_gpio_out <=
## PWDATA; lalu peripherals.sv meneruskan gpio_out tanpa disentuh lagi).
## Jadi bit ke-0 dari data yang ditulis ke PADOUT = gpio_out0.
## ---------------------------------------------------------------------
set_property PACKAGE_PIN M14 [get_ports {gpio_out0}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_out0}]

## ---------------------------------------------------------------------
## Timing constraint (gabungan dengan constraints.xdc resmi PULPino)
## ---------------------------------------------------------------------
create_clock -period 8.000  -name clk      [get_nets {clk}]     ;# 125 MHz dari L16
create_clock -period 1000.0 -name spi_sck  [get_nets {spi_clk_i}] ;# sesuaikan SPI_CLOCK_HZ ESP32

set_clock_groups -asynchronous \
                 -group { clk } \
                 -group { spi_sck }
