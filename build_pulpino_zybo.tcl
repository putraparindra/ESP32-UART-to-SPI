## =====================================================================
## build_pulpino_zybo.tcl
## Build project PULPino untuk ZYBO dari nol lewat command line (batch),
## tanpa GUI, dari create_project sampai generate bitstream.
##
## Cara jalanin (Vivado Tcl Console ATAU Command Prompt / PowerShell):
##   vivado -mode batch -source build_pulpino_zybo.tcl
##
## Sesuaikan 3 variabel di bawah ini kalau path kamu beda.
## =====================================================================

set REPO      "D:/uart2spi"
set XDC       "D:/uart2spi/zybo_pulpino_spi_led.xdc"
set PROJ_DIR  "D:/pulpino_zybo_build"
set PROJ_NAME "pulpino_zybo"

## PATCH: path ke 2 file pengganti sp_ram_wrap.sv dan dp_ram_wrap.sv asli.
## Versi asli meng-hardcode instansiasi IP Xilinx (xilinx_mem_8192x32 /
## xilinx_mem_32768x32_dp) yang butuh di-generate manual dulu lewat Vivado
## IP Catalog -- dan untuk sp_ram_wrap.sv ukurannya bahkan salah/tidak sesuai
## RAM_SIZE=32768 yang sebenarnya dipakai. Versi patch ini selalu memakai
## module generic sp_ram/dp_ram yang portable, di-infer otomatis jadi BRAM
## oleh Vivado tanpa perlu IP tambahan.
set SP_RAM_PATCH "D:/uart2spi/sp_ram_wrap_patched.sv"
set DP_RAM_PATCH "D:/uart2spi/dp_ram_wrap_patched.sv"

## PATCH TAMBAHAN: rtl/components/sp_ram.sv dan dp_ram.sv (component level,
## bukan wrapper) memakai array packed 2D yang membingungkan heuristik
## auto-inferensi BRAM Vivado -- alih-alih Block RAM, malah disintesis jadi
## puluhan ribu flip-flop individual (sangat lambat + boros resource).
## Versi patch menambahkan atribut (* ram_style = "block" *) untuk memaksa
## pemetaan ke BRAM fisik.
set SP_RAM_COMPONENT_PATCH "D:/uart2spi/sp_ram_patched.sv"
set DP_RAM_COMPONENT_PATCH "D:/uart2spi/dp_ram_patched.sv"

## ---------------------------------------------------------------------
## Helper: cari file rekursif (Tcl tidak punya glob ** bawaan)
## Dipindah ke ATAS supaya bisa dipakai di pengecekan langkah 0.
## ---------------------------------------------------------------------
proc findFiles { basedir pattern } {
    set basedir [string trimright [file normalize $basedir] /]
    set fileList {}

    foreach fileName [glob -nocomplain -type f -directory $basedir $pattern] {
        lappend fileList $fileName
    }
    foreach dirName [glob -nocomplain -type d -directory $basedir *] {
        foreach subDirFile [findFiles $dirName $pattern] {
            lappend fileList $subDirFile
        }
    }
    return $fileList
}

## ---------------------------------------------------------------------
## 0. Cek folder ips/ tidak kosong (submodule harus sudah ke-clone)
##    DIPERBAIKI: cek REKURSIF ke semua subfolder (apb/, axi/, riscv/, dst),
##    bukan cuma file yang ada langsung di ips/ -- karena isinya memang
##    semua nested di subfolder.
## ---------------------------------------------------------------------
set ips_check [findFiles "$REPO/ips" *.sv]
set ips_check [concat $ips_check [findFiles "$REPO/ips" *.v]]
if { [llength $ips_check] == 0 } {
    puts "ERROR: tidak ada file .sv/.v ditemukan di $REPO/ips (dicek rekursif)."
    puts "Pastikan subfolder seperti ips/apb, ips/axi, ips/riscv sudah terisi."
    exit 1
}
puts "OK: ditemukan [llength $ips_check] file RTL di dalam ips/."

## ---------------------------------------------------------------------
## 1. Buat project baru
## ---------------------------------------------------------------------
create_project $PROJ_NAME $PROJ_DIR -part xc7z010clg400-1 -force
set_property board_part digilentinc.com:zybo:part0:2.0 [current_project]

## ---------------------------------------------------------------------
## 2. Kumpulkan source RTL: seluruh rtl/ + ips/ (rekursif) + wrapper FPGA
##    Sengaja TIDAK menyentuh folder sw/ dan tb/ supaya tidak ada file
##    testbench / header software yang ikut ke fileset synthesis.
## ---------------------------------------------------------------------
set rtl_files {}
foreach pat {*.sv *.v *.vhd} {
    set rtl_files [concat $rtl_files [findFiles "$REPO/rtl" $pat]]
    set rtl_files [concat $rtl_files [findFiles "$REPO/ips" $pat]]
}
lappend rtl_files "$REPO/fpga/rtl/pulpino_wrap.v"

## Keluarkan ips/apb/apb_uart_sv/ -- TIDAK dipakai (peripherals.sv memanggil
## modul 'apb_uart' yang cuma ada di versi VHDL, ips/apb/apb_uart/), dan
## folder SV ini punya file uart_interrupt.sv yang NAMA MODULNYA SAMA PERSIS
## dengan uart_interrupt.vhd di folder VHDL -- berpotensi bentrok kalau
## dua-duanya ikut di-compile bareng.
##
## Keluarkan ips/fpu/ -- FPU TIDAK dipakai di konfigurasi kita
## (RISCY_RV32F=0 di pulpino_wrap.v), dan folder ini berisi dua
## implementasi FPU berbeda (fpu_v0.1 vs fpu_fmac) yang package-nya
## sama-sama punya parameter bernama sama (mis. C_EXP_INF, C_MANT_ZERO)
## sehingga bentrok "visible via multiple package imports" kalau
## dua-duanya ikut di-compile bareng. Tidak dibutuhkan untuk desain ini.
##
## Keluarkan JUGA rtl/sp_ram_wrap.sv dan rtl/dp_ram_wrap.sv ASLI --
## digantikan versi patch (SP_RAM_PATCH/DP_RAM_PATCH) yang tidak butuh
## IP Xilinx pre-generated. Lihat catatan di bagian atas file ini.
set rtl_files_filtered {}
foreach f $rtl_files {
    if { [string match "*/ips/fpu/*" $f] } {
        continue
    }
    if { [string match "*/ips/apb/apb_uart_sv/*" $f] } {
        continue
    }
    if { [string match "*/rtl/sp_ram_wrap.sv" $f] } {
        continue
    }
    if { [string match "*/rtl/dp_ram_wrap.sv" $f] } {
        continue
    }
    if { [string match "*/rtl/components/sp_ram.sv" $f] } {
        continue
    }
    if { [string match "*/rtl/components/dp_ram.sv" $f] } {
        continue
    }
    lappend rtl_files_filtered $f
}
set rtl_files $rtl_files_filtered
lappend rtl_files $SP_RAM_PATCH
lappend rtl_files $DP_RAM_PATCH
lappend rtl_files $SP_RAM_COMPONENT_PATCH
lappend rtl_files $DP_RAM_COMPONENT_PATCH

if { [llength $rtl_files] == 0 } {
    puts "ERROR: tidak ada file RTL ditemukan di $REPO/rtl atau $REPO/ips."
    puts "Cek lagi isi variabel REPO di atas."
    exit 1
}

puts "Menambahkan [llength $rtl_files] file RTL (ips/fpu & apb_uart_sv dikecualikan, sp_ram_wrap.sv & dp_ram_wrap.sv dipatch)..."
add_files -norecurse $rtl_files

## ---------------------------------------------------------------------
## 3. Include directory
##    (a) rtl/includes -- untuk axi_bus.sv, config.sv, apb_bus.sv, dst
##    (b) SEMUA folder bernama 'include' di dalam ips/ -- karena tiap IP
##        (apb_event_unit, riscv, zero-riscy, dll) punya file include
##        sendiri-sendiri (defines_event_unit.sv, apu_macros.sv,
##        riscv_config.sv, zeroriscy_config.sv, dst) yang letaknya
##        nested di folder include/ masing-masing IP, BUKAN di rtl/includes.
## ---------------------------------------------------------------------
proc findDirs { basedir name } {
    set basedir [string trimright [file normalize $basedir] /]
    set dirList {}
    foreach dirName [glob -nocomplain -type d -directory $basedir *] {
        if { [file tail $dirName] eq $name } {
            lappend dirList $dirName
        }
        foreach subDir [findDirs $dirName $name] {
            lappend dirList $subDir
        }
    }
    return $dirList
}

set inc_dirs [list "$REPO/rtl/includes"]
set inc_dirs [concat $inc_dirs [findDirs "$REPO/ips" "include"]]

puts "Include directories ([llength $inc_dirs]):"
foreach d $inc_dirs { puts "  $d" }

set_property include_dirs $inc_dirs [current_fileset]

## PENTING: rtl/includes/config.sv men-define macro ASIC secara default
## untuk SEMUA synthesis run (`ifdef SYNTHESIS ... `define ASIC), kecuali
## macro PULP_FPGA_EMUL sudah didefinisikan lebih dulu. Kalau ASIC ke-define,
## clk_rst_gen.sv akan coba instansiasi 'umcL65_LL_FLL' -- hard macro analog
## UMC 65nm yang cuma ada di proses fabrikasi ASIC, TIDAK ADA untuk FPGA,
## sehingga selalu error "module not found". Definisikan PULP_FPGA_EMUL di
## sini supaya clk_rst_gen.sv masuk ke cabang bypass FPGA-nya.
set_property verilog_define {PULP_FPGA_EMUL} [current_fileset]

## ---------------------------------------------------------------------
## 4. Tambahkan file constraint (.xdc)
## ---------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse [list $XDC]

## ---------------------------------------------------------------------
## 5. Set top module ke "pulpino" (dari fpga/rtl/pulpino_wrap.v)
## ---------------------------------------------------------------------
set_property top pulpino [current_fileset]
update_compile_order -fileset sources_1

## ---------------------------------------------------------------------
## 6. Jalankan Synthesis
## ---------------------------------------------------------------------
puts "=== Mulai synthesis ==="
launch_runs synth_1 -jobs 6
wait_on_run synth_1

if { [get_property PROGRESS [get_runs synth_1]] != "100%" } {
    puts "ERROR: synth_1 gagal. Cek log:"
    puts "  $PROJ_DIR/$PROJ_NAME.runs/synth_1/runme.log"
    exit 1
}
puts "=== Synthesis selesai ==="

## ---------------------------------------------------------------------
## 7. Jalankan Implementation + Generate Bitstream sekaligus
## ---------------------------------------------------------------------
puts "=== Mulai implementation + bitstream ==="
launch_runs impl_1 -to_step write_bitstream -jobs 6
wait_on_run impl_1

if { [get_property PROGRESS [get_runs impl_1]] != "100%" } {
    puts "ERROR: implementation/bitstream gagal. Cek log:"
    puts "  $PROJ_DIR/$PROJ_NAME.runs/impl_1/runme.log"
    exit 1
}

puts "=== SELESAI ==="
puts "Bitstream ada di:"
puts "  $PROJ_DIR/$PROJ_NAME.runs/impl_1/pulpino.bit"
