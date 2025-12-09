module spi_loader (
    input wire clk,           // 25MHz
    input wire rst_n,
    
    // Pines Físicos Flash
    output reg spi_cs,
    output reg spi_clk,
    output reg spi_mosi,
    input wire spi_miso,
    
    // Interfaz hacia la RAM
    output reg [11:0] ram_addr,
    output reg [23:0] ram_data,
    output reg ram_wren
);

    // - CONFIGURACIÓN DEL GIF -
    localparam START_ADDR  = 24'h300000; // Dirección en Flash
    localparam FRAME_SIZE  = 12288;      // 64x64 * 3 bytes

    // 25MHz = 25,000,000 ciclos/seg.
    // 1,000,000 ~= 40ms (25 FPS). Aumenta para ir más lento.
    localparam FRAME_DELAY = 2000000;

    // Máquina de Estados
    localparam S_INIT=0, S_CMD=1, S_READ_PIXEL=2, S_WAIT=3;

    reg [2:0] state;
    reg [31:0] timer;
    reg [23:0] flash_ptr; // Puntero de lectura en Flash
    reg [31:0] shift_out; // Para enviar comandos
    reg [5:0]  bit_cnt;   // Contador de bits SPI
    reg [7:0]  r, g, b;   // Buffers de color temporal

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= S_INIT;
            spi_cs <= 1; spi_clk <= 0; spi_mosi <= 0;
            ram_wren <= 0; ram_addr <= 0;
            flash_ptr <= START_ADDR;
            timer <= 0;
        end else begin
            case(state)
                // 1. INICIO / NUEVO FRAME
                S_INIT: begin
                    spi_cs <= 1;
                    ram_wren <= 0;
                    ram_addr <= 0; // Reset dirección RAM para empezar a llenar desde 0

                    timer <= timer + 1;
                    if(timer > 1000) begin // Pequeña pausa
                        state <= S_CMD;
                        timer <= 0;
                    end
                end

                // 2. ENVIAR COMANDO DE LECTURA (03h + Dirección)
                S_CMD: begin
                    spi_cs <= 0;
                    if(timer == 0) begin
                        shift_out <= {8'h03, flash_ptr}; // Cmd 03h + 24bit Addr
                        bit_cnt <= 31;
                        timer <= 1;
                    end else begin
                        if(timer[0]) begin          // Timer Impar: Bajada -> Cambiar Datos (MOSI)
                            spi_clk <= 0;
                            spi_mosi <= shift_out[bit_cnt];
                        end else begin              // Timer Par: Subida -> Latch en Flash
                            spi_clk <= 1;           // IMPORTANTE: El reloj DEBE subir aquí

                            if(bit_cnt == 0) begin
                                // Último bit enviado correctamente (con clk=1)
                                state <= S_READ_PIXEL;
                                bit_cnt <= 23;
                                timer <= 0;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end

                        if(state == S_CMD) timer <= timer + 1;
                    end
                end

                // 3. LEER PIXEL (R, G, B) Y ESCRIBIR A RAM
                S_READ_PIXEL: begin
                    if(timer[0] == 0) begin // Bajada (SPI_CLK -> 0)
                        spi_clk <= 0;
                        timer <= timer + 1;
                        ram_wren <= 0;
                    end else begin // Subida (SPI_CLK -> 1) -> Leer MISO
                        spi_clk <= 1;
                        ram_data[bit_cnt] <= spi_miso;

                        if(bit_cnt == 0) begin
                            // Pixel Completo
                            ram_wren <= 1;
                            if(ram_addr == 4095) begin
                                spi_cs <= 1;
                                spi_clk <= 0;
                                state <= S_WAIT;
                            end else begin
                                bit_cnt <= 23;
                            end
                        end else begin

                            bit_cnt <= bit_cnt - 1;
                        end
                        timer <= timer + 1;
                    end

                    if(ram_wren) ram_addr <= ram_addr + 1;
                end
                // 4. ESPERA DE ANIMACIÓN (Delay entre frames)
                S_WAIT: begin
                    ram_wren <= 0;
                    timer <= timer + 1;

                    // Acá ajustamos los FPS
                    if(timer > FRAME_DELAY) begin
                        timer <= 0;

                        // Avanzar al siguiente frame
                        flash_ptr <= flash_ptr + FRAME_SIZE;

                        if (flash_ptr >= 24'h400000) begin
                             flash_ptr <= START_ADDR;
                        end

                        state <= S_INIT;
                    end
                end
            endcase
        end
    end
endmodule