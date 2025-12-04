module spi_flash_diag (
    input wire clk, rst_n,
    output reg spi_cs, output reg spi_clk, output reg spi_mosi, input wire spi_miso,
    output reg uart_tx_line, output reg diag_active
);

    // --- 1. UART 9600 BAUDIOS (Reloj 25MHz) ---
    localparam BAUD_DIV = 2604; 
    
    reg [7:0] uart_byte_to_send;
    reg uart_trigger;
    reg uart_busy;
    reg [12:0] uart_clk_count;
    reg [3:0] uart_bit_index;
    reg [7:0] uart_shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            uart_tx_line <= 1;
            uart_busy <= 0;
            uart_clk_count <= 0;
            uart_bit_index <= 0;
            uart_shift_reg <= 0;
        end else begin
            if(uart_trigger && !uart_busy) begin
                uart_busy <= 1;
                uart_shift_reg <= uart_byte_to_send; 
                uart_clk_count <= 0; 
                uart_bit_index <= 0; 
                uart_tx_line <= 0; 
            end else if(uart_busy) begin
                if(uart_clk_count < BAUD_DIV) 
                    uart_clk_count <= uart_clk_count + 1;
                else begin
                    uart_clk_count <= 0;
                    if(uart_bit_index < 8) begin 
                        uart_tx_line <= uart_shift_reg[0];
                        uart_shift_reg <= {1'b0, uart_shift_reg[7:1]};
                        uart_bit_index <= uart_bit_index + 1;
                    end else if(uart_bit_index == 8) begin 
                        uart_tx_line <= 1;
                        uart_bit_index <= uart_bit_index + 1;
                    end else begin 
                        uart_busy <= 0;
                    end
                end
            end
        end
    end

    // --- 2. MAQUINA DE ESTADOS: LEER 4 BYTES DESDE 0x000000 ---
    reg [5:0] state; // Ampliado a 6 bits
    reg [23:0] timer;
    
    reg [7:0] spi_cmd;       
    reg [31:0] addr_seq; // Para guardar Comando + Dirección (32 bits)
    reg [5:0] bit_cnt;       
    reg [7:0] data_read;     
    reg [2:0] byte_counter; // Contar cuántos bytes leemos
    
    // Estados
    localparam S_IDLE        = 0;
    
    // Fase 1: Reset / Exit QPI (Seguridad)
    localparam S_RST_CS_L    = 1;
    localparam S_RST_SEND    = 2;
    localparam S_RST_CLK_H   = 3;
    localparam S_RST_CLK_L   = 4;
    localparam S_RST_CS_H    = 5;
    localparam S_WAIT_RECOV  = 6;

    // Fase 2: Enviar Comando Lectura + Dirección
    localparam S_READ_CS_L   = 7;
    localparam S_ADDR_SEND   = 8;
    localparam S_ADDR_CLK_H  = 9;
    localparam S_ADDR_CLK_L  = 10;

    // Fase 3: Leer Byte
    localparam S_READ_BIT    = 11;
    localparam S_READ_CLK_L  = 12;

    // Fase 4: Imprimir UART
    localparam S_UART_HIGH   = 13;
    localparam S_WAIT_U1     = 14;
    localparam S_UART_LOW    = 15;
    localparam S_WAIT_U2     = 16;
    localparam S_UART_SPACE  = 17;
    localparam S_WAIT_U3     = 18;
    
    // Fin
    localparam S_READ_NEXT   = 19;
    localparam S_CS_H_FINAL  = 20;
    localparam S_UART_CR     = 21;
    localparam S_WAIT_U4     = 22;
    localparam S_UART_LF     = 23;
    localparam S_WAIT_U5     = 24;

    function [7:0] to_ascii(input [3:0] val);
        if (val < 10) to_ascii = 8'h30 + val;       
        else          to_ascii = 8'h37 + val;       
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= S_IDLE;
            diag_active <= 0;
            uart_trigger <= 0;
            spi_cs <= 1;
            spi_clk <= 0;
            spi_mosi <= 0;
            timer <= 0;
        end else begin
            uart_trigger <= 0; 
            
            case(state)
                // --- ESPERA ---
                S_IDLE: begin
                    spi_cs <= 1;
                    timer <= timer + 1;
                    if(timer == 12500000) begin // 0.5s
                        timer <= 0;
                        diag_active <= ~diag_active; 
                        state <= S_RST_CS_L; 
                    end
                end

                // --- FASE 1: RESET (0xFF) ---
                S_RST_CS_L: begin
                    spi_cs <= 0;
                    spi_cmd <= 8'hFF; 
                    bit_cnt <= 7;
                    state <= S_RST_SEND;
                end
                S_RST_SEND: begin
                    spi_mosi <= spi_cmd[bit_cnt];
                    state <= S_RST_CLK_H;
                end
                S_RST_CLK_H: begin
                    spi_clk <= 1;
                    state <= S_RST_CLK_L;
                end
                S_RST_CLK_L: begin
                    spi_clk <= 0;
                    if(bit_cnt == 0) state <= S_RST_CS_H;
                    else begin
                        bit_cnt <= bit_cnt - 1;
                        state <= S_RST_SEND;
                    end
                end
                S_RST_CS_H: begin
                    spi_cs <= 1;
                    timer <= 0;
                    state <= S_WAIT_RECOV;
                end
                S_WAIT_RECOV: begin
                    timer <= timer + 1;
                    if(timer == 1000) state <= S_READ_CS_L; 
                end

                // --- FASE 2: COMANDO 03h + DIRECCION 000000h ---
                S_READ_CS_L: begin
                    spi_cs <= 0;
                    // Cmd(03) + Addr(00) + Addr(00) + Addr(00)
                    addr_seq <= 32'h03000000; 
                    bit_cnt <= 31; // 32 bits total
                    byte_counter <= 0; // Vamos a leer 4 bytes
                    state <= S_ADDR_SEND;
                end
                S_ADDR_SEND: begin
                    spi_mosi <= addr_seq[bit_cnt];
                    state <= S_ADDR_CLK_H;
                end
                S_ADDR_CLK_H: begin
                    spi_clk <= 1;
                    state <= S_ADDR_CLK_L;
                end
                S_ADDR_CLK_L: begin
                    spi_clk <= 0;
                    if(bit_cnt == 0) begin
                        bit_cnt <= 7; // Preparar para leer byte
                        state <= S_READ_BIT;
                    end else begin
                        bit_cnt <= bit_cnt - 1;
                        state <= S_ADDR_SEND;
                    end
                end

                // --- FASE 3: LEER BYTE ---
                S_READ_BIT: begin
                    spi_clk <= 1; // LEER
                    data_read <= {data_read[6:0], spi_miso};
                    state <= S_READ_CLK_L;
                end
                S_READ_CLK_L: begin
                    spi_clk <= 0;
                    if(bit_cnt == 0) state <= S_UART_HIGH; // Byte completo -> Imprimir
                    else begin
                        bit_cnt <= bit_cnt - 1;
                        state <= S_READ_BIT;
                    end
                end

                // --- FASE 4: IMPRIMIR BYTE EN HEX ---
                S_UART_HIGH: begin
                    uart_byte_to_send <= to_ascii(data_read[7:4]);
                    uart_trigger <= 1;
                    state <= S_WAIT_U1;
                end
                S_WAIT_U1: if(!uart_busy && !uart_trigger) state <= S_UART_LOW;

                S_UART_LOW: begin
                    uart_byte_to_send <= to_ascii(data_read[3:0]);
                    uart_trigger <= 1;
                    state <= S_WAIT_U2;
                end
                S_WAIT_U2: if(!uart_busy && !uart_trigger) state <= S_UART_SPACE;

                S_UART_SPACE: begin
                    uart_byte_to_send <= 8'h20; // Espacio
                    uart_trigger <= 1;
                    state <= S_WAIT_U3;
                end
                S_WAIT_U3: if(!uart_busy && !uart_trigger) state <= S_READ_NEXT;

                // --- DECIDIR: LEER OTRO O TERMINAR ---
                S_READ_NEXT: begin
                    if(byte_counter < 3) begin // Leer 4 bytes (0,1,2,3)
                        byte_counter <= byte_counter + 1;
                        bit_cnt <= 7;
                        state <= S_READ_BIT; // Volver a leer sin subir CS
                    end else begin
                        state <= S_CS_H_FINAL;
                    end
                end

                S_CS_H_FINAL: begin
                    spi_cs <= 1; // Terminar transacción SPI
                    state <= S_UART_CR;
                end

                S_UART_CR: begin
                    uart_byte_to_send <= 8'h0D; // \r
                    uart_trigger <= 1;
                    state <= S_WAIT_U4;
                end
                S_WAIT_U4: if(!uart_busy && !uart_trigger) state <= S_UART_LF;

                S_UART_LF: begin
                    uart_byte_to_send <= 8'h0A; // \n
                    uart_trigger <= 1;
                    state <= S_WAIT_U5;
                end
                S_WAIT_U5: if(!uart_busy && !uart_trigger) state <= S_IDLE;

            endcase
        end
    end
endmodule