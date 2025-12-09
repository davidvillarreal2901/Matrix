from PIL import Image, ImageSequence
import numpy as np
import sys
import os

# Uso: python gif_to_bin.py animacion.gif
if len(sys.argv) < 2:
    print("Uso: python gif_to_bin.py <archivo.gif>")
    sys.exit(1)

nombre_gif = sys.argv[1]
nombre_salida = "../animacion.bin"

try:
    im_gif = Image.open(nombre_gif)
except IOError:
    print("Error: No se pudo abrir el archivo GIF.") # Por si acasoo
    sys.exit(1)

print(f"Procesando GIF: {nombre_gif} -> {nombre_salida}")

frames = []
for frame in ImageSequence.Iterator(im_gif):
    frame = frame.convert('RGB').resize((64, 64))
    frames.append(np.array(frame))

print(f"Total de frames encontrados: {len(frames)}")

with open(nombre_salida, "wb") as f:
    for i, img in enumerate(frames):
        for y in range(32):
            for x in range(64):
                # Pixel Arriba (x, y)
                # Azul(idx 2) -> R, Rojo(idx 0) -> B 
                #Cambio descubierto por el profe de colores invertidos
                r1 = img[y, x, 2] >> 4  
                g1 = img[y, x, 1] >> 4
                b1 = img[y, x, 0] >> 4

                # Pixel Abajo (x, y+32)
                r2 = img[y+32, x, 2] >> 4
                g2 = img[y+32, x, 1] >> 4
                b2 = img[y+32, x, 0] >> 4

                # Empaquetado: 2 pixeles (24 bits) en 3 bytes
                byte1 = (r1 << 4) | g1
                byte2 = (b1 << 4) | r2
                byte3 = (g2 << 4) | b2
                
                f.write(bytes([byte1, byte2, byte3]))
        
        print(f"\rProcesado frame {i+1}/{len(frames)}", end='')

print(f"\n¡Listo! Archivo '{nombre_salida}' generado ({os.path.getsize(nombre_salida)} bytes).")