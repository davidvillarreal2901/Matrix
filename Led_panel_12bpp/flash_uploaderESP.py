import serial
import sys
import os
import time
import struct

BAUD_RATE = 115200

def main():
    if len(sys.argv) < 3:
        print("Uso: python flash_uploaderESP.py <PUERTO> <ARCHIVO.BIN>")
        return

    port = sys.argv[1]
    filename = sys.argv[2]
    
    if not os.path.exists(filename):
        print(f"Error: No encuentro el archivo {filename}")
        return

    file_size = os.path.getsize(filename)

    try:
        # Timeout de 2s para conexión inicial
        ser = serial.Serial(port, BAUD_RATE, timeout=2) 
        time.sleep(2) # Esperar a que el ESP32 se reinicie tras abrir puerto
        ser.reset_input_buffer()
    except Exception as e:
        print(f"Error abriendo puerto: {e}")
        return

    print(f" GRABANDO {filename} ({file_size/1024:.2f} KB)")
    print("1. Sincronizando...")
    
    # Enviamos 'S' y esperamos respuesta
    ser.write(b'S')
    
    start_wait = time.time()
    sync_ok = False
    
    while time.time() - start_wait < 5:
        if ser.in_waiting:
            line = ser.readline().decode('latin-1', errors='ignore').strip()
            # ACEPTAMOS AMBAS RESPUESTAS (Viejas y Nuevas)
            if "SYNC_OK" in line or "SYNC_WRITE_OK" in line:
                sync_ok = True
                print(f"   -> ¡Conectado! (ESP32 dijo: {line})")
                break
    
    if not sync_ok:
        print("ERROR: El ESP32 no responde. Presiona el botón RESET (EN) en el ESP32 e intenta de nuevo.")
        return

    # la Flash puede tardar
    ser.timeout = 10 

    print("2. Enviando tamaño...")
    ser.write(struct.pack('<I', file_size))
    
    print("3. Esperando 'START'...")
    # Buscamos el mensaje START para asegurar que el tamaño se recibió
    while True:
        line = ser.readline().decode('latin-1', errors='ignore').strip()
        if "START" in line:
            break
            
    print("4. Transfiriendo datos...")
    
    start_time = time.time()
    with open(filename, 'rb') as f:
        sent = 0
        while sent < file_size:
            chunk = f.read(256) # Leemos bloques de 256 bytes
            ser.write(chunk)
            
            # --- HANDSHAKE: Esperar la 'K' ---
            # IA
            ack = ser.read(1) 
            if ack != b'K':
                print(f"\nERROR DE TRANSMISIÓN: Se esperaba 'K' y llegó: {ack}")
                print("Intenta bajar la velocidad o revisar cables.")
                return

            sent += len(chunk)
            
            # Barra de progreso
            percent = (sent / file_size) * 100
            elapsed = time.time() - start_time
            speed = sent / elapsed if elapsed > 0 else 0
            sys.stdout.write(f"\r   Progreso: {percent:.1f}% | Vel: {speed/1024:.1f} KB/s")
            sys.stdout.flush()

    print("\n\nEsperando confirmación de finalización...")
    while True:
        line = ser.readline().decode('latin-1', errors='ignore').strip()
        if "DONE" in line:
            total_time = time.time() - start_time
            print(f"Grabación completada en {total_time:.1f} segundos.")
            break

    ser.close()

if __name__ == "__main__":
    main()