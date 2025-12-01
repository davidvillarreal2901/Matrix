from PIL import Image
import sys
import os

def process_gif(input_path, output_filename="../image.hex"):
    img = Image.open(input_path)
    
    # Parámetros fijos para la matriz de 64x64
    WIDTH = 64
    HEIGHT = 64
    SCAN_RATE = 32  # 1/32 scan (controlando 2 filas a la vez)
    
    frames_data = []
    
    try:
        while True:
            # Convertir frame actual a RGB y redimensionar
            frame = img.copy().convert('RGB').resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
            pixels = frame.load()
            
            frame_lines = []
            
            # Recorremos solo la mitad superior (0-31)
            # Porque procesamos la fila 'y' (arriba) y 'y+32' (abajo) juntas
            for y in range(SCAN_RATE):
                for x in range(WIDTH):
                    # --- Pixel Superior (R0, G0, B0) ---
                    b0, g0, r0 = pixels[x, y]
                    # Convertir a 4 bits (0-15)
                    val0 = ((r0 >> 4) << 8) | ((g0 >> 4) << 4) | (b0 >> 4)
                    
                    # --- Pixel Inferior (R1, G1, B1) ---
                    b1, g1, r1 = pixels[x, y + SCAN_RATE]
                    val1 = ((r1 >> 4) << 8) | ((g1 >> 4) << 4) | (b1 >> 4)
                    
                    # --- Empaquetar: {RGB0, RGB1} o {RGB1, RGB0} ---
                    # Según memory.v: reg [23:0] rdata
                    # Asumimos Upper 12 bits = RGB1, Lower 12 bits = RGB0
                    combined = (val0 << 12) | val1
                    
                    # Formato Hexadecimal de 24 bits (6 dígitos)
                    frame_lines.append(f"{combined:06X}")
            
            frames_data.extend(frame_lines)
            img.seek(img.tell() + 1)
            
    except EOFError:
        pass # Fin de los frames

    # Guardar archivo .hex
    with open(output_filename, 'w') as f:
        # Escribir cada valor en una nueva línea para $readmemh
        f.write('\n'.join(frames_data))
    
    print(f"Generado {output_filename} con {len(frames_data)//(WIDTH*SCAN_RATE)} frames.")
    print(f"Total líneas HEX: {len(frames_data)}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python gif_to_hex.py archivo.gif")
    else:
        process_gif(sys.argv[1])