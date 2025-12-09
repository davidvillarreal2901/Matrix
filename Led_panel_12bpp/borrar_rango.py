import serial
import sys
import time
import struct


print("DEBUG: El script ha arrancao' ")


def main():
    if len(sys.argv) < 4:
        print("\n BORRADO SELECTIVO SPI ")
        print("Uso: python borrar_rango.py <PUERTO> <INICIO_HEX> <FIN_HEX>")
        print("Ejemplo: python borrar_rango.py COM3 0x300000 0x350000")
        return

    port = sys.argv[1]
    
    # Convertir argumentos Hexadecimales (string) a Enteros
    try:
        start_addr = int(sys.argv[2], 16)
        end_addr = int(sys.argv[3], 16)
    except ValueError:
        print("Error: Las direcciones deben estar en formato HEX (ej. 0x300000)")
        return

    if end_addr <= start_addr:
        print("Error: La dirección final debe ser mayor a la de inicio.")
        return
    
    if start_addr % 4096 != 0:
        print("Advertencia: La dirección de inicio se redondeará al sector anterior (4KB).")
        start_addr = (start_addr // 4096) * 4096

    size_to_erase = end_addr - start_addr
    
    # Redondear tamaño hacia arriba para cubrir el último sector si no es exacto
    if size_to_erase % 4096 != 0:
        size_to_erase = ((size_to_erase // 4096) + 1) * 4096

    print(f" CONFIGURACIÓN ")
    print(f"Puerto: {port}")
    print(f"Inicio: 0x{start_addr:X}")
    print(f"Fin:    0x{start_addr + size_to_erase:X}")
    print(f"Total:  {size_to_erase} bytes ({size_to_erase/1024:.1f} KB)")
    
    confirm = input("¿Confirmar borrado? (y/n): ")
    if confirm.lower() != 'y':
        print("Abortado.")
        return

    try:
        ser = serial.Serial(port, 115200, timeout=10)
        time.sleep(2)
        ser.reset_input_buffer()
    except Exception as e:
        print(f"Error puerto: {e}")
        return

    print("1. Conectando con ESP32...")
    ser.write(b'E') # Comando Erase
    
    while True:
        line = ser.readline().decode('latin-1', errors='ignore').strip()
        if "SYNC_ERASE_OK" in line:
            break

    print("2. Enviando coordenadas...")
    ser.write(struct.pack('<I', start_addr))   # 4 bytes Inicio
    ser.write(struct.pack('<I', size_to_erase)) # 4 bytes Tamaño

    print("3. Borrando...")
    
    start_time = time.time()
    sector_count = 0
    total_sectors = size_to_erase / 4096
    
    while True:
        char = ser.read(1).decode('latin-1', errors='ignore')
        
        if char == 'X':
            sector_count += 1
            percent = (sector_count / total_sectors) * 100
            sys.stdout.write(f"\r   Progreso: {percent:.1f}% ({sector_count}/{int(total_sectors)} sectores)")
            sys.stdout.flush()
        else:
            line = char + ser.readline().decode('latin-1', errors='ignore').strip()
            if "ERASE_DONE" in line:
                break
            elif "ERROR" in line:
                print(f"\n{line}")
                return
    
    duration = time.time() - start_time
    print(f"\n\n¡LISTO! Memoria limpia en {duration:.2f} segundos.")
    ser.close()

if __name__ == "__main__":
    main()