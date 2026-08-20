/*
 * UART (USB) <-> SPI Converter
 * ESP32 sebagai SPI MASTER
 * Framework   : Arduino (arduino-esp32 core)
 * Pola data   : Buffered per-frame
 *
 * Framing yang dipakai (bisa disesuaikan):
 *   [START_BYTE 0xAA] [LEN 1 byte] [PAYLOAD...N byte] [CHECKSUM 1 byte]
 *
 * Alur:
 *  1. Komputer -> UART -> ESP32   : ESP32 kumpulkan bytes sampai 1 frame lengkap
 *     -> kirim payload ke SPI slave via SPI.transfer()
 *     -> data yang "masuk" dari MISO saat transfer itu langsung dikirim balik ke UART
 *  2. Kalau mau polling SPI slave secara independen (bukan cuma balasan),
 *     tinggal panggil pollSpiSlave() di loop() sesuai kebutuhan device slave-nya.
 */

#include <SPI.h>

// ================= KONFIGURASI PIN SPI =================
// Default VSPI/FSPI pada ESP32 klasik: SCLK=18, MISO=19, MOSI=23, SS=5
// Ganti sesuai wiring kamu kalau pakai pin custom.
#define PIN_SCK   18
#define PIN_MISO  19
#define PIN_MOSI  23
#define PIN_CS    5

static const uint32_t SPI_CLOCK_HZ = 1000000; // 1 MHz, aman untuk mulai. Naikkan bertahap setelah stabil.
static const uint8_t  SPI_MODE     = SPI_MODE0;

SPIClass spiMaster(VSPI);

// ================= KONFIGURASI FRAMING =================
#define START_BYTE     0xAA
#define MAX_PAYLOAD    128   // sesuaikan kebutuhan
#define UART_BAUD      115200

// ================= STATE MACHINE PARSER UART =================
enum RxState {
  WAIT_START,
  WAIT_LEN,
  WAIT_PAYLOAD,
  WAIT_CHECKSUM
};

RxState rxState = WAIT_START;
uint8_t rxBuffer[MAX_PAYLOAD];
uint8_t rxLen = 0;
uint8_t rxIndex = 0;
uint8_t rxChecksum = 0;

// ================= FUNGSI BANTUAN =================

uint8_t calcChecksum(const uint8_t *data, uint8_t len) {
  uint8_t sum = 0;
  for (uint8_t i = 0; i < len; i++) sum ^= data[i]; // XOR checksum sederhana
  return sum;
}

// Kirim satu frame lengkap ke SPI slave, hasil baliknya (MISO) dikirim ke UART
void sendFrameToSpi(uint8_t *payload, uint8_t len) {
  uint8_t rxFromSpi[MAX_PAYLOAD];

  spiMaster.beginTransaction(SPISettings(SPI_CLOCK_HZ, MSBFIRST, SPI_MODE));
  digitalWrite(PIN_CS, LOW);

  for (uint8_t i = 0; i < len; i++) {
    rxFromSpi[i] = spiMaster.transfer(payload[i]); // full-duplex: kirim & terima sekaligus
  }

  digitalWrite(PIN_CS, HIGH);
  spiMaster.endTransaction();

  // Kirim balik hasil dari slave (MISO) ke komputer via UART
  // Bisa dibungkus dengan framing yang sama, atau raw. Contoh raw dulu:
  Serial.write(rxFromSpi, len);
}

// Parser byte-per-byte dari UART, state machine sederhana
void processUartByte(uint8_t b) {
  switch (rxState) {
    case WAIT_START:
      if (b == START_BYTE) {
        rxState = WAIT_LEN;
      }
      break;

    case WAIT_LEN:
      rxLen = b;
      rxIndex = 0;
      if (rxLen == 0 || rxLen > MAX_PAYLOAD) {
        rxState = WAIT_START; // frame invalid, reset
      } else {
        rxState = WAIT_PAYLOAD;
      }
      break;

    case WAIT_PAYLOAD:
      rxBuffer[rxIndex++] = b;
      if (rxIndex >= rxLen) {
        rxState = WAIT_CHECKSUM;
      }
      break;

    case WAIT_CHECKSUM:
      rxChecksum = calcChecksum(rxBuffer, rxLen);
      if (rxChecksum == b) {
        // Frame valid -> teruskan ke SPI
        sendFrameToSpi(rxBuffer, rxLen);
      }
      // kalau checksum salah: bisa tambahkan logging/error handling di sini
      rxState = WAIT_START;
      break;
  }
}

// ================= (OPSIONAL) POLLING SPI SLAVE MANDIRI =================
// Kalau device SPI slave kamu perlu dipoll berkala (bukan cuma respon ke UART),
// panggil fungsi ini di loop() sesuai interval yang dibutuhkan.
void pollSpiSlave() {
  // contoh: kirim dummy byte, baca hasilnya, teruskan ke UART
  // uint8_t dummy = 0x00;
  // spiMaster.beginTransaction(SPISettings(SPI_CLOCK_HZ, MSBFIRST, SPI_MODE));
  // digitalWrite(PIN_CS, LOW);
  // uint8_t result = spiMaster.transfer(dummy);
  // digitalWrite(PIN_CS, HIGH);
  // spiMaster.endTransaction();
  // Serial.write(result);
}

// ================= SETUP & LOOP =================
void setup() {
  Serial.begin(UART_BAUD);

  pinMode(PIN_CS, OUTPUT);
  digitalWrite(PIN_CS, HIGH); // idle high

  spiMaster.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
}

void loop() {
  while (Serial.available() > 0) {
    uint8_t b = Serial.read();
    processUartByte(b);
  }

  // pollSpiSlave(); // aktifkan kalau perlu polling independen
}
