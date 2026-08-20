# UART-to-SPI Bridge (ESP32) ke SPI Slave PULPino di ZYBO

Project ini menghubungkan **komputer** ke **SPI Slave milik SoC PULPino** (RISC-V, diimplementasikan di FPGA ZYBO/Zynq-7010) lewat **ESP32** sebagai jembatan protokol UART-ke-SPI. Hasil akhirnya: menyalakan LED fisik di board ZYBO dengan menulis register GPIO PULPino dari komputer, murni lewat jalur SPI eksternal — tanpa software apa pun yang berjalan di dalam core RISC-V.

```
Python (komputer) --USB/UART--> ESP32 (SPI Master) --SPI--> SPI Slave PULPino
                                                                    |
                                                                    v
                                                     AXI4 Interconnect -> APB -> GPIO -> LED
```

## Daftar Isi

- [Arsitektur](#arsitektur)
- [Kebutuhan Hardware](#kebutuhan-hardware)
- [Kebutuhan Software](#kebutuhan-software)
- [Struktur Repository](#struktur-repository)
- [Tutorial Lengkap](#tutorial-lengkap)
  1. [Menyiapkan Repository PULPino](#1-menyiapkan-repository-pulpino)
  2. [Build FPGA dengan Vivado](#2-build-fpga-dengan-vivado)
  3. [Program FPGA lewat JTAG](#3-program-fpga-lewat-jtag)
  4. [Upload Firmware ke ESP32](#4-upload-firmware-ke-esp32)
  5. [Wiring Fisik ESP32 ke Pmod JE](#5-wiring-fisik-esp32-ke-pmod-je)
  6. [Menjalankan Skrip Python](#6-menjalankan-skrip-python)
- [Protokol SPI Slave PULPino](#protokol-spi-slave-pulpino)
- [Masalah yang Ditemukan & Cara Mengatasinya](#masalah-yang-ditemukan--cara-mengatasinya)
- [Referensi](#referensi)
- [Lisensi](#lisensi)

---

## Arsitektur

| Komponen | Peran |
|---|---|
| **Python** (`pulpino_gpio_led.py`) | Menyusun transaksi SPI (command + address + data), mengirim lewat USB-Serial |
| **ESP32** (`uart_to_spi_master/uart_to_spi_master.ino`) | SPI Master, menjembatani UART <-> SPI dengan framing `[START][LEN][PAYLOAD][CHECKSUM]`, CS tetap LOW sepanjang satu transaksi |
| **SPI Slave PULPino** | Peripheral aktif di PULPino dengan akses AXI langsung ke memori/peripheral — tidak butuh core RISC-V berjalan |
| **AXI4 / APB** | Interconnect PULPino yang menjembatani SPI Slave ke peripheral GPIO |
| **GPIO PULPino** | Register `PADDIR` (arah pin) dan `PADOUT` (nilai output) yang dikendalikan lewat SPI |
| **LED0 (LD0)** | Output fisik di board ZYBO, terhubung ke `gpio_out[0]` |

## Kebutuhan Hardware

- Board **Digilent ZYBO** (Zynq-7010, revisi original — bukan ZYBO Z7)
- **ESP32 Dev Module** (chip ESP32 klasik)
- Kabel jumper **female-to-male** (Pmod JE female, pin ESP32 male)
- 2x kabel USB (satu untuk ZYBO/JTAG via port J11, satu untuk ESP32)

## Kebutuhan Software

- **Vivado 2025.2** (atau versi kompatibel) dengan board file ZYBO terinstall
- **Arduino IDE** dengan board package `esp32` (Espressif)
- **Python 3** + `pyserial` (`pip install pyserial`)
- **Git**

## Struktur Repository

```
uart2spi/
├── rtl/, ips/, fpga/, sw/, tb/, doc/   <- source resmi PULPino (pulp-platform/pulpino)
├── uart_to_spi_master/
│   └── uart_to_spi_master.ino          <- firmware ESP32 (SPI Master, mode framed)
├── pulpino_gpio_led.py                 <- skrip Python (kirim transaksi SPI dari komputer)
├── build_pulpino_zybo.tcl              <- script build Vivado end-to-end (batch, tanpa GUI)
├── zybo_pulpino_spi_led.xdc            <- constraint pin ZYBO (Pmod JE + LED0 + clock + reset)
├── zybo_top.sv                         <- wrapper top-level (batasi port fisik yang diekspos)
├── sp_ram_wrap_patched.sv / dp_ram_wrap_patched.sv   <- patch: memori generic, bukan IP Xilinx
├── sp_ram_patched.sv / dp_ram_patched.sv             <- patch: BRAM inference yang benar
└── ips_list.yml                        <- daftar 22 IP dependency PULPino
```

> **Catatan:** file-file `*_patched.sv`, `zybo_top.sv`, `build_pulpino_zybo.tcl`, dan `zybo_pulpino_spi_led.xdc` **bukan bagian resmi** dari `pulp-platform/pulpino` — ini ditambahkan khusus untuk project ini, untuk mengatasi berbagai masalah build di FPGA ZYBO (lihat bagian [Masalah yang Ditemukan](#masalah-yang-ditemukan--cara-mengatasinya)).

---

## Tutorial Lengkap

### 1. Menyiapkan Repository PULPino

PULPino mem-package dependency IP-nya lewat script `update-ips.py`, **bukan** git submodule biasa. Sayangnya script itu Python 2 dan menurut maintainer-nya **tidak didukung di Windows**, serta butuh akses ke tool internal ETH Zurich (`IPApproX`) yang tidak bisa diakses publik.

**Solusi:** clone tiap IP secara manual dari `github.com/pulp-platform/<nama-repo>`, branch `pulpinov1` (kecuali `adv_dbg_if` yang pakai tag `Pulpino_v2.1`), sesuai daftar di `ips_list.yml`. 22 IP yang dibutuhkan:

```
apb: apb_node, apb_event_unit, apb_fll_if, apb_gpio, apb_i2c, apb_pulpino,
     apb_spi_master, apb_timer, apb_uart, apb_uart_sv, apb2per
axi: axi2apb, axi_mem_if_DP, axi_node, axi_slice, axi_slice_dc,
     axi_spi_master, axi_spi_slave, core2axi
lainnya: adv_dbg_if, riscv, zero-riscy, fpu
```

Taruh hasil clone-nya di `ips/<kategori>/<nama-ip>/` sesuai struktur `ips_list.yml`.

### 2. Build FPGA dengan Vivado

Semua langkah build (create project, tambah source RTL, set include directory, set macro `PULP_FPGA_EMUL`, tambah constraint, synthesis, implementation, generate bitstream) sudah otomatis lewat satu script:

```tcl
# Sesuaikan dulu 4 variabel di baris atas file (REPO, XDC, PROJ_DIR, PROJ_NAME)
# Buka Vivado, lalu di Tcl Console:
source "path/ke/build_pulpino_zybo.tcl"
```

Proses ini bisa memakan waktu cukup lama (bisa berjam-jam tergantung spesifikasi komputer) untuk synthesis penuh SoC RISC-V. Script berhenti otomatis dengan pesan jelas kalau ada tahap yang gagal.

### 3. Program FPGA lewat JTAG

Sambungkan ZYBO ke komputer lewat port **J11** (micro-USB, kombinasi JTAG+UART), lalu di Vivado Tcl Console:

```tcl
open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [get_hw_devices xc7z010_1]
refresh_hw_device -update_hw_probes false [current_hw_device]
set_property PROGRAM.FILE {path/ke/zybo_top.bit} [current_hw_device]
program_hw_devices [current_hw_device]
```

Setelah selesai, LED **DONE** di board ZYBO akan menyala.

**Setel switch fisik:**
- `SW0` = HIGH → `fetch_enable_i` (mengizinkan core RISC-V mulai jalan, meski tidak wajib untuk operasi SPI Slave)
- `SW1` = HIGH → `rst_n` (melepas reset SoC — **wajib HIGH**, lihat catatan di bagian masalah di bawah)

### 4. Upload Firmware ke ESP32

Buka `uart_to_spi_master/uart_to_spi_master.ino` di Arduino IDE, pilih board **ESP32 Dev Module**, pilih port COM yang sesuai, upload.

### 5. Wiring Fisik ESP32 ke Pmod JE

| Pmod JE | Sinyal | Pin FPGA | GPIO ESP32 |
|---|---|---|---|
| JE1 | `spi_clk_i` (SCK) | V12 | GPIO 18 |
| JE2 | `spi_cs_i` (CS) | W16 | GPIO 5 |
| JE3 | `spi_sdi0_i` (MOSI) | J15 | GPIO 23 |
| JE4 | `spi_sdo0_o` (MISO) | H15 | GPIO 19 |
| GND | — | — | GND |

`VCC` Pmod **tidak perlu** disambung (ESP32 punya daya sendiri dari USB). **GND wajib** disambung — koneksi longgar di GND adalah penyebab paling umum pembacaan data yang kacau.

### 6. Menjalankan Skrip Python

```bash
pip install pyserial
python pulpino_gpio_led.py
```

Sesuaikan `PORT` di bagian atas file dengan port COM ESP32 kamu. Pilih mode **1** untuk demo otomatis (set `PADDIR` lalu `PADOUT`, menyalakan LED0), atau mode **2** untuk menulis address+data bebas secara manual.

---

## Protokol SPI Slave PULPino

Diverifikasi langsung dari source resmi `tb/tb_spi_pkg.sv` (task `spi_write_word`, `spi_read_nword`):

| Elemen | Nilai |
|---|---|
| Command WRITE | `0x02` |
| Command READ | `0x0B` (butuh 33 dummy clock sebelum data keluar) |
| Urutan bit | MSB dulu |
| Struktur transaksi | `CS low -> CMD (1 byte) -> ADDR (4 byte) -> DATA (4 byte) -> CS high`, tanpa CS naik di tengah |

Alamat register GPIO yang relevan (dari datasheet PULPino):
- `PADDIR` = `0x1A10_1000` (arah pin: 0=input, 1=output)
- `PADOUT` = `0x1A10_1008` (nilai output)

## Masalah yang Ditemukan & Cara Mengatasinya

Build untuk target FPGA standalone (bukan `pulpemu_top` yang berbasis Zynq PS) ternyata punya beberapa isu yang belum terselesaikan di source resmi. Dicatat di sini supaya tidak perlu debug ulang dari nol:

| Masalah | Penyebab | Solusi |
|---|---|---|
| `cannot open include file` | Folder `rtl/includes/` dan `ips/*/include/` belum terdaftar sebagai include directory | `set_property include_dirs` mencakup semua folder `include` secara rekursif |
| `module 'apb_uart' not found` | Modul asli ditulis dalam **VHDL**, bukan SystemVerilog | Scan file `.vhd` juga, bukan cuma `.sv`/`.v` |
| Konflik package FPU (`fpu_v0.1` vs `fpu_fmac`) | Dua implementasi FPU berbeda punya parameter bernama sama | Exclude `ips/fpu/` (tidak dipakai karena `RISCY_RV32F=0`) |
| `module 'umcL65_LL_FLL' not found` | Hard macro FLL khusus ASIC UMC 65nm, tidak ada di FPGA | Define macro `PULP_FPGA_EMUL` supaya `clk_rst_gen.sv` bypass FLL |
| `module 'xilinx_mem_8192x32' not found`, ukuran salah | `sp_ram_wrap.sv` hardcode IP Xilinx ukuran salah, tidak sesuai `RAM_SIZE` sebenarnya | Patch pakai memori generic (`sp_ram`/`dp_ram`) |
| Over-utilization ekstrem (butuh 176.000+ LUT, cuma ada 17.600) | Memori generic dengan array packed 2D tidak ter-infer jadi BRAM, disintesis jadi ratusan ribu flip-flop | Tulis ulang dengan array 1D flat + atribut `ram_style="block"` (template resmi Xilinx UG901) |
| `IO placement infeasible: 139 ports > 50 pins` | Modul `pulpino` punya 139 port total, jauh lebih banyak dari pin fisik yang tersedia | Buat wrapper `zybo_top.sv` yang cuma mengekspos 8 sinyal yang dipakai, sisanya di-tie off internal |
| `Poor placement for routing between IO pin and BUFG` | `spi_clk_i` masuk lewat pin biasa, bukan pin clock khusus (CCIO) | `set_property CLOCK_DEDICATED_ROUTE FALSE` (aman untuk clock lambat 1 MHz) |
| LED tidak menyala meski komunikasi SPI bersih | `rst_n` terhubung ke **tombol** yang default LOW saat tidak ditekan, sementara `rst_n` butuh HIGH (aktif-LOW) — SoC selalu dalam kondisi reset permanen kecuali tombol ditahan terus | Pindahkan `rst_n` ke **switch** (bisa disetel stabil HIGH), bukan tombol momentary |

## Referensi

**Arsitektur PULPino & RISC-V**
- A. Traber, M. Gautschi, *"PULPino: A small single-core RISC-V SoC"*, 3rd RISC-V Workshop, 2016
- M. Gautschi et al., *"Near-Threshold RISC-V Core with DSP Extensions for Scalable IoT Endpoint Devices"*, IEEE TVLSI, 2017
- Repository resmi: [pulp-platform/pulpino](https://github.com/pulp-platform/pulpino)
- Digilent, *"ZYBO FPGA Board Reference Manual"*

**Konsep UART-to-SPI Bridge (posisi ESP32 di project ini)**
- *"Design and Analysis of Multi-Protocol Conversion Unit for SPI, I2C and UART"*, IEEE, 2024 — [ieeexplore.ieee.org/document/10533106](https://ieeexplore.ieee.org/document/10533106/)
- *"Optimal implementation of UART-SPI Interface in SoC"* — [academia.edu](https://www.academia.edu/56446056/Optimal_implementation_of_UART_SPI_Interface_in_SoC)
- *"Design of UART Interface for SPI Flash"* — [ijsetr.com](http://ijsetr.com/uploads/346512IJSETR14446-587.pdf)
- Texas Instruments, *"Subsystem Design: UART to SPI Bridge"* (MSPM0), app note [SLAAEK3](https://www.ti.com/lit/SLAAEK3) — format paket (start byte + indikator baca/tulis + panjang + data) yang jadi pembanding desain framing di project ini
- Bridgetek/FTDI, *"AN_374 FT90x UART to SPI Bridge"* — [brtchip.com](https://brtchip.com/wp-content/uploads/Support/Documentation/Application_Notes/ICs/MCU/AN_374-FT90x-UART-to-SPI-Bridge.pdf)
- [FaresMehanna/UART-to-SPI-bridge](https://github.com/FaresMehanna/UART-to-SPI-bridge) — implementasi UART-to-SPI core dalam HDL (FPGA), berbeda dari pendekatan project ini yang berbasis firmware mikrokontroler
- [freecores/uart2spi](https://github.com/freecores/uart2spi) — core UART-to-SPI HDL open source
- [Stulinaz/STM32F103RB_USB_to_UART_SPI_I2C](https://github.com/Stulinaz/STM32F103RB_USB_to_UART_SPI_I2C) — firmware mikrokontroler sebagai bridge multi-protokol, pendekatan paling dekat secara konsep dengan project ini (beda chip: STM32 vs ESP32)

> Kombinasi spesifik *mikrokontroler eksternal sebagai UART-SPI bridge ke SPI Slave sebuah SoC RISC-V open-source di FPGA* tidak ditemukan padanan persisnya di referensi manapun di atas — bagian ini menjadi kontribusi/orisinalitas tersendiri dari project ini.

## Lisensi

Source RTL PULPino (folder `rtl/`, `ips/`, `fpga/`, `tb/`, `sw/`) berlisensi **Solderpad Hardware License 0.51** dari ETH Zurich dan University of Bologna — lihat `LICENSE`. File tambahan project ini (`*.ino`, `*.py`, `*.tcl`, `*_patched.sv`, `zybo_top.sv`) mengikuti lisensi yang sama kecuali dinyatakan lain.
