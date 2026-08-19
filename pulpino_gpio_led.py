"""
Nyalakan LED PULPino lewat rantai:
Python (UART) -> ESP32 (SPI Master, mode framed) -> SPI Slave PULPino -> AXI -> APB -> GPIO

STATUS VERIFIKASI: TERKONFIRMASI dari source resmi pulpino-master/tb/tb_spi_pkg.sv
(task spi_write_word dan spi_read_word / spi_read_nword), bukan dugaan lagi.
- Command WRITE = 0x02 (spi_send_cmd_addr(use_qspi, 8'h2, addr))
- Command READ  = 0x0B (command = 8'hB), butuh 33 dummy clock cycle setelah address
  sebelum data keluar di MISO -- read TIDAK dipakai di skrip ini.
- Command, address, dan data dikirim MSB-dulu (big-endian per byte, MSB-first per byte)
  -- sama persis dengan .to_bytes(4, byteorder="big") yang dipakai di bawah.
- CS tetap LOW sepanjang satu transaksi CMD+ADDR+DATA. Tidak ada dummy cycle untuk WRITE.

Frame yang dikirim ke ESP32 (sesuai firmware uart_to_spi_master.ino / versi framed):
    [0xAA] [LEN] [PAYLOAD...] [CHECKSUM XOR]
Payload untuk satu transaksi SPI Slave WRITE:
    [CMD=0x02] [ADDR 4 byte, MSB dulu] [DATA 4 byte, MSB dulu]

Instalasi:
    pip install pyserial
"""

import serial
import time

# ================= KONFIGURASI =================
PORT = "COM13"        # sesuaikan dengan port ESP32 kamu
BAUD = 115200
TIMEOUT = 1

START_BYTE = 0xAA
CMD_WRITE = 0x02      # terkonfirmasi dari tb/tb_spi_pkg.sv (spi_write_word)

# Alamat register GPIO PULPino (dari datasheet)
ADDR_PADDIR = 0x1A10_1000
ADDR_PADOUT = 0x1A10_1008

LED_BIT = 0            # ganti sesuai bit gpio_out yang kamu sambungkan ke LED di constraint Vivado


def open_connection():
    ser = serial.Serial(PORT, BAUD, timeout=TIMEOUT)
    time.sleep(2.5)  # tunggu ESP32 selesai reset (dinaikkan sedikit dari 2 detik)

    # PENTING: membuka port serial otomatis memicu ESP32 reset lewat
    # sirkuit auto-reset (DTR/RTS) bawaan board. Reset itu mengirim banner
    # boot ROM ("ets Jul 29 2019 12:21:46...") lewat UART yang sama dengan
    # jalur data kita. Kalau tidak dibuang, sisa teks boot itu bisa
    # terbaca seolah-olah balasan SPI (padahal bukan). Buang semua yang
    # masih mengendap di buffer sebelum mulai komunikasi sungguhan.
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    return ser


def build_spi_write_payload(addr: int, data: int) -> bytes:
    """Susun payload: CMD + ADDR (4 byte, MSB dulu) + DATA (4 byte, MSB dulu)."""
    payload = bytearray()
    payload.append(CMD_WRITE)
    payload += addr.to_bytes(4, byteorder="big")
    payload += data.to_bytes(4, byteorder="big")
    return bytes(payload)


def build_uart_frame(payload: bytes) -> bytes:
    """Bungkus payload dengan START_BYTE, LEN, dan checksum XOR sesuai firmware ESP32."""
    if len(payload) == 0 or len(payload) > 255:
        raise ValueError("Panjang payload tidak valid")

    checksum = 0
    for b in payload:
        checksum ^= b

    frame = bytearray()
    frame.append(START_BYTE)
    frame.append(len(payload))
    frame += payload
    frame.append(checksum)
    return bytes(frame)


def spi_slave_write(ser: serial.Serial, addr: int, data: int):
    """Kirim satu transaksi WRITE ke SPI Slave PULPino lewat ESP32."""
    payload = build_spi_write_payload(addr, data)
    frame = build_uart_frame(payload)

    print(f"  Payload SPI  : {payload.hex(' ').upper()}")
    print(f"  Frame ke ESP32: {frame.hex(' ').upper()}")

    ser.write(frame)
    ser.flush()

    # ESP32 akan membalas raw byte hasil MISO sepanjang payload SPI (lihat firmware)
    response = ser.read(len(payload))
    print(f"  Balasan MISO : {response.hex(' ').upper()}")

    # Deteksi dini: kalau balasan kebetulan berisi banyak karakter ASCII
    # yang bisa dicetak, itu kemungkinan besar bukan data SPI asli, tapi
    # sisa teks boot ESP32 yang belum sempat ke-flush. Data SPI asli
    # (alamat/nilai register PULPino) harusnya terlihat acak sebagai byte,
    # bukan membentuk teks yang terbaca.
    printable = sum(1 for b in response if 32 <= b <= 126)
    if printable >= len(response) * 0.6 and len(response) > 3:
        try:
            as_text = response.decode("ascii", errors="replace")
        except Exception:
            as_text = "?"
        print(f"  PERINGATAN: balasan ini kelihatan seperti teks ('{as_text}'), bukan data SPI.")
        print("  Kemungkinan besar ini sisa boot ESP32 yang belum ke-flush, bukan balasan asli.")


def run_led_demo(ser: serial.Serial):
    """Demo tetap: nyalakan LED lewat 2 transaksi write (PADDIR lalu PADOUT)."""
    current_paddir = 0x00000000  # asumsi reset value, sesuaikan jika sudah pernah diubah
    new_paddir = current_paddir | (1 << LED_BIT)

    print("1) Set PADDIR: jadikan pin LED sebagai output")
    spi_slave_write(ser, ADDR_PADDIR, new_paddir)

    time.sleep(0.05)

    current_padout = 0x00000000
    new_padout = current_padout | (1 << LED_BIT)

    print("\n2) Set PADOUT: nyalakan LED (set bit HIGH)")
    spi_slave_write(ser, ADDR_PADOUT, new_padout)

    print("\nSelesai. Jika LED belum menyala, kemungkinan besar di:")
    print("- Pemetaan gpio_out[LED_BIT] ke pin fisik LED di constraint Vivado (.xdc)")
    print("- Constraint pin spi_clk_i/spi_cs_i/spi_sdi0_i/spi_sdo0_o di project FPGA")
    print("- Kecepatan clock SPI ESP32 vs axi_aclk PULPino (axi_aclk harus >= ~4x spi_sclk)")


def run_interactive_write(ser: serial.Serial):
    """
    Mode bebas: user ketik address dan data sendiri (format hex), dikirim
    sebagai transaksi WRITE yang valid (framing + protokol SPI Slave PULPino
    tetap benar -- bukan raw passthrough seperti uart_spi_client.py).

    CATATAN: mode READ (cmd 0x0B) sengaja TIDAK disediakan di sini. SPI Slave
    PULPino butuh persis 33 dummy clock cycle setelah address sebelum data
    keluar -- 33 bit itu TIDAK genap byte (33/8 = 4.125), sedangkan firmware
    ESP32 kita mengirim per-byte lewat SPI.transfer(). Kalau dipaksa kirim 5
    byte (40 clock) sebagai dummy, keluaran data akan bergeser 7 bit dan hasil
    baca jadi salah. Implementasi READ yang benar butuh firmware ESP32 versi
    bit-level (bit-banging atau transferBits), belum tersedia di versi ini.
    """
    while True:
        addr_str = input("\nAlamat register (hex, misal 1A101008, atau 'q' untuk kembali): ").strip()
        if addr_str.lower() == "q":
            break
        data_str = input("Data yang ditulis (hex, misal 00000001): ").strip()

        try:
            addr = int(addr_str, 16)
            data = int(data_str, 16)
        except ValueError:
            print("Format hex tidak valid, coba lagi.")
            continue

        if addr > 0xFFFFFFFF or data > 0xFFFFFFFF:
            print("Nilai melebihi 32-bit, coba lagi.")
            continue

        spi_slave_write(ser, addr, data)


def main():
    ser = open_connection()
    print(f"Terhubung ke {PORT} @ {BAUD} baud\n")

    try:
        while True:
            mode = input(
                "\nPilih mode:\n"
                "  1) Demo nyalakan LED (PADDIR + PADOUT otomatis)\n"
                "  2) Tulis manual ke address+data bebas (hex)\n"
                "  q) Keluar\n"
                "> "
            ).strip()

            if mode == "1":
                run_led_demo(ser)
            elif mode == "2":
                run_interactive_write(ser)
            elif mode.lower() == "q":
                break
            else:
                print("Pilihan tidak dikenal.")

    finally:
        ser.close()
        print("\nKoneksi ditutup.")


if __name__ == "__main__":
    main()
