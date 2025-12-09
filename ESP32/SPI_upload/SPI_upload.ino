#include <SPI.h>

// --- PINES ---
#define PIN_CS   32  
#define PIN_SCK  33  
#define PIN_MISO 35  
#define PIN_MOSI 25  

#define DEFAULT_WRITE_ADDR 0x300000 //Dirección de escritura

#define W25Q_WRITE_ENABLE      0x06
#define W25Q_SECTOR_ERASE      0x20
#define W25Q_PAGE_PROGRAM      0x02
#define W25Q_READ_STATUS_1     0x05

void setup() {
  Serial.begin(115200);
  SPI.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
  pinMode(PIN_CS, OUTPUT);
  digitalWrite(PIN_CS, HIGH);
  SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));
  delay(100);
  Serial.println("ESP32_SMART_ERASER"); 
}

void loop() {
  if (Serial.available() > 0) {
    char cmd = Serial.read();
    
    // 'S' = Escribir (Usa dirección fija para no complicar)
    if (cmd == 'S') { 
      Serial.println("SYNC_WRITE_OK");
      writeRoutine();
    }
    
    // 'E' = Borrado Inteligente (Recibe Dirección y Tamaño)
    else if (cmd == 'E') {
      Serial.println("SYNC_ERASE_OK");
      smartEraseRoutine();
    }
  }
}

// Rutina de borrado
// IA
void smartEraseRoutine() {
  // 1. Leer DIRECCIÓN DE INICIO (4 bytes)
  while (Serial.available() < 4);
  uint32_t startAddr = 0;
  startAddr |= Serial.read();
  startAddr |= (Serial.read() << 8);
  startAddr |= (Serial.read() << 16);
  startAddr |= (Serial.read() << 24);

  // 2. Leer TAMAÑO A BORRAR (4 bytes)
  while (Serial.available() < 4);
  uint32_t size = 0;
  size |= Serial.read();
  size |= (Serial.read() << 8);
  size |= (Serial.read() << 16);
  size |= (Serial.read() << 24);

  Serial.printf("CMD: Borrar desde 0x%X (Tam: %d bytes)\n", startAddr, size);

  // Validar alineación (Los sectores son de 4096 bytes)
  if (startAddr % 4096 != 0) {
    Serial.println("ERROR: La direccion de inicio debe ser multiplo de 4096 (0x1000)");
    return;
  }

  uint32_t currentAddr = startAddr;
  uint32_t endAddr = startAddr + size;
  
  while (currentAddr < endAddr) {
    eraseSector(currentAddr);
    Serial.print("X"); // Feedback visual
    currentAddr += 4096;
  }
  
  Serial.println("\nERASE_DONE");
}

// ESCRITURA
void writeRoutine() {
  while (Serial.available() < 4);
  uint32_t fileSize = 0;
  fileSize |= Serial.read();
  fileSize |= (Serial.read() << 8);
  fileSize |= (Serial.read() << 16);
  fileSize |= (Serial.read() << 24);
  
  Serial.printf("START:%d\n", fileSize);
  
  uint32_t currentAddr = DEFAULT_WRITE_ADDR;
  uint32_t bytesWritten = 0;
  uint8_t buffer[256];
  
  while (bytesWritten < fileSize) {
   if (currentAddr % 4096 == 0) eraseSector(currentAddr); 
    int bytesToRead = min((uint32_t)256, fileSize - bytesWritten);
    int bufferIdx = 0;
    while (bufferIdx < bytesToRead) {
      if (Serial.available()) buffer[bufferIdx++] = Serial.read();
    }
    writePage(currentAddr, buffer, bytesToRead);
    Serial.write('K'); 
    currentAddr += bytesToRead;
    bytesWritten += bytesToRead;
  }
  Serial.println("\nDONE");
}

// SPI
void waitForBusy() {
  uint8_t status;
  do {
    digitalWrite(PIN_CS, LOW);
    SPI.transfer(W25Q_READ_STATUS_1);
    status = SPI.transfer(0x00);
    digitalWrite(PIN_CS, HIGH);
  } while (status & 0x01);
}
void writeEnable() {
  digitalWrite(PIN_CS, LOW);
  SPI.transfer(W25Q_WRITE_ENABLE);
  digitalWrite(PIN_CS, HIGH);
}
void eraseSector(uint32_t addr) {
  waitForBusy();
  writeEnable();
  digitalWrite(PIN_CS, LOW);
  SPI.transfer(W25Q_SECTOR_ERASE);
  SPI.transfer((addr >> 16) & 0xFF);
  SPI.transfer((addr >> 8) & 0xFF);
  SPI.transfer(addr & 0xFF);
  digitalWrite(PIN_CS, HIGH);
  waitForBusy();
}
void writePage(uint32_t addr, uint8_t* data, int len) {
  waitForBusy();
  writeEnable();
  digitalWrite(PIN_CS, LOW);
  SPI.transfer(W25Q_PAGE_PROGRAM);
  SPI.transfer((addr >> 16) & 0xFF);
  SPI.transfer((addr >> 8) & 0xFF);
  SPI.transfer(addr & 0xFF);
  for (int i = 0; i < len; i++) SPI.transfer(data[i]);
  digitalWrite(PIN_CS, HIGH);
  waitForBusy();
}