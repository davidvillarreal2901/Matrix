module spi_flash_diag (
    input wire clk, rst_n,
    output reg spi_cs, output reg spi_clk, output reg spi_mosi, input wire spi_miso,
    output reg uart_tx_line, output reg diag_active
);

    // --- 1. UART 9600 BAUDIOS (25MHz) ---
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

    // --- 2. MAQUINA DE ESTADOS ---
    // CORRECCIÓN CRITICA: Aumentado a 8 bits para soportar estados > 63
    reg [7:0] state; 
    reg [25:0] timer; 
    
    reg [39:0] write_seq; 
    reg [5:0] bit_cnt;       
    reg [7:0] data_read;     
    reg [2:0] byte_counter; 
    
    function [7:0] to_ascii(input [3:0] val);
        if (val < 10) to_ascii = 8'h30 + val;       
        else          to_ascii = 8'h37 + val;       
    endfunction

    // Estados
    localparam S_IDLE        = 0;
    localparam S_WREN_CS_L   = 1;
    localparam S_WREN_SEND   = 2;
    localparam S_WREN_CS_H   = 3;
    localparam S_WREN_WAIT   = 4;
    localparam S_ERASE_CS_L  = 5;
    localparam S_ERASE_SEND  = 6;
    localparam S_ERASE_CS_H  = 7;
    localparam S_ERASE_WAIT  = 8; 
    localparam S_WREN2_CS_L  = 9;
    localparam S_WREN2_SEND  = 10;
    localparam S_WREN2_CS_H  = 11;
    localparam S_WREN2_WAIT  = 12;
    localparam S_PROG_CS_L   = 13;
    localparam S_PROG_SEND   = 14;
    localparam S_PROG_CS_H   = 15;
    localparam S_PROG_WAIT   = 16; 
    localparam S_READ_CS_L   = 17;
    localparam S_ADDR_SEND   = 18;
    localparam S_READ_BIT    = 19;
    localparam S_READ_CLK_L  = 20;
    localparam S_UART_HIGH   = 21;
    localparam S_WAIT_U1     = 22;
    localparam S_UART_LOW    = 23;
    localparam S_WAIT_U2     = 24;
    localparam S_UART_SPACE  = 25;
    localparam S_WAIT_U3     = 26;
    localparam S_READ_NEXT   = 27;
    localparam S_CS_H_FINAL  = 28;
    localparam S_UART_CR     = 29;
    localparam S_WAIT_U4     = 30;
    localparam S_UART_LF     = 31;
    localparam S_WAIT_U5     = 32;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= S_IDLE;
            diag_active <= 0;
            uart_trigger <= 0;
            spi_cs <= 1;
            spi_clk <= 0;
            spi_mosi <= 0;
            timer <= 0;
            write_seq <= 0;
            bit_cnt <= 0;
            data_read <= 0;
            byte_counter <= 0;
            uart_byte_to_send <= 0;
        end else begin
            uart_trigger <= 0; 
            
            case(state)
                S_IDLE: begin
                    spi_cs <= 1;
                    timer <= timer + 1;
                    if(timer == 25000) begin // 1ms start
                        timer <= 0;
                        diag_active <= ~diag_active; 
                        state <= S_WREN_CS_L; 
                    end
                end

                // 1. ENABLE WRITE
                S_WREN_CS_L: begin
                    spi_cs <= 0;
                    write_seq <= {8'h06, 32'h0}; 
                    bit_cnt <= 7;
                    state <= S_WREN_SEND;
                end
                S_WREN_SEND: begin 
                     spi_clk <= 0;
                     spi_mosi <= write_seq[bit_cnt + 32];
                     state <= S_WREN_CS_H + 100; 
                end
                S_WREN_CS_H + 100: begin 
                     spi_clk <= 1;
                     if(bit_cnt == 0) state <= S_WREN_CS_H;
                     else begin
                         bit_cnt <= bit_cnt - 1;
                         state <= S_WREN_SEND;
                     end
                end
                S_WREN_CS_H: begin
                    spi_clk <= 0;
                    spi_cs <= 1;
                    state <= S_WREN_WAIT;
                end
                S_WREN_WAIT: begin
                    timer <= timer + 1;
                    if(timer == 100) begin timer <= 0; state <= S_ERASE_CS_L; end
                end

                // 2. SECTOR ERASE (0x20)
                S_ERASE_CS_L: begin
                    spi_cs <= 0;
                    write_seq <= 32'h20000000; 
                    bit_cnt <= 31;
                    state <= S_ERASE_SEND;
                end
                S_ERASE_SEND: begin
                    spi_clk <= 0;
                    spi_mosi <= write_seq[bit_cnt];
                    state <= S_ERASE_CS_H + 100;
                end
                S_ERASE_CS_H + 100: begin
                    spi_clk <= 1;
                    if(bit_cnt == 0) state <= S_ERASE_CS_H;
                    else begin
                        bit_cnt <= bit_cnt - 1;
                        state <= S_ERASE_SEND;
                    end
                end
                S_ERASE_CS_H: begin
                    spi_clk <= 0;
                    spi_cs <= 1;
                    state <= S_ERASE_WAIT;
                end
                S_ERASE_WAIT: begin
                    timer <= timer + 1;
                    // ~150ms espera de borrado
                    if(timer == 4000000) begin 
                        timer <= 0; 
                        state <= S_WREN2_CS_L; 
                    end
                end

                // 3. ENABLE WRITE 2
                S_WREN2_CS_L: begin
                    spi_cs <= 0;
                    write_seq <= {8'h06, 32'h0}; 
                    bit_cnt <= 7;
                    state <= S_WREN2_SEND;
                end
                S_WREN2_SEND: begin
                    spi_clk <= 0;
                    spi_mosi <= write_seq[bit_cnt + 32];
                    state <= S_WREN2_CS_H + 100; 
                end
                S_WREN2_CS_H + 100: begin 
                    spi_clk <= 1;
                    if(bit_cnt == 0) state <= S_WREN2_CS_H;
                    else begin
                         bit_cnt <= bit_cnt - 1;
                         state <= S_WREN2_SEND;
                    end
                end
                S_WREN2_CS_H: begin
                    spi_clk <= 0;
                    spi_cs <= 1;
                    state <= S_WREN2_WAIT;
                end
                S_WREN2_WAIT: begin
                    timer <= timer + 1;
                    if(timer == 100) begin timer <= 0; state <= S_PROG_CS_L; end
                end

                // 4. PROGRAM "HOLA"
                S_PROG_CS_L: begin
                    spi_cs <= 0;
                    // Cmd(02) + Addr(000000)
                    write_seq <= 32'h02000000; 
                    bit_cnt <= 31;
                    state <= S_PROG_SEND;
                end
                S_PROG_SEND: begin 
                    spi_clk <= 0;
                    spi_mosi <= write_seq[bit_cnt];
                    state <= S_PROG_CS_H + 100;
                end
                S_PROG_CS_H + 100: begin
                    spi_clk <= 1;
                    if(bit_cnt == 0) state <= S_PROG_SEND + 200; 
                    else begin
                        bit_cnt <= bit_cnt - 1;
                        state <= S_PROG_SEND;
                    end
                end
                // Datos "HOLA"
                S_PROG_SEND + 200: begin
                     write_seq <= 32'h484F4C41; 
                     bit_cnt <= 31;
                     state <= S_PROG_SEND + 201;
                end
                S_PROG_SEND + 201: begin
                    spi_clk <= 0;
                    spi_mosi <= write_seq[bit_cnt];
                    state <= S_PROG_SEND + 202;
                end
                S_PROG_SEND + 202: begin
                    spi_clk <= 1;
                    if(bit_cnt == 0) state <= S_PROG_CS_H; 
                    else begin
                        bit_cnt <= bit_cnt - 1;
                        state <= S_PROG_SEND + 201;
                    end
                end
                S_PROG_CS_H: begin
                    spi_clk <= 0;
                    spi_cs <= 1;
                    state <= S_PROG_WAIT;
                end
                S_PROG_WAIT: begin
                    timer <= timer + 1;
                    // ~3ms program
                    if(timer == 100000) begin 
                        timer <= 0; 
                        state <= S_READ_CS_L; 
                    end
                end

                // 5. READ (0x03)
                S_READ_CS_L: begin
                    spi_cs <= 0;
                    write_seq <= 32'h03000000; 
                    bit_cnt <= 31;
                    byte_counter <= 0;
                    state <= S_ADDR_SEND;
                end
                S_ADDR_SEND: begin
                    spi_clk <= 0;
                    spi_mosi <= write_seq[bit_cnt];
                    state <= S_ADDR_SEND + 100;
                end
                S_ADDR_SEND + 100: begin
                    spi_clk <= 1;
                    if(bit_cnt == 0) begin
                        bit_cnt <= 7;
                        state <= S_READ_BIT; 
                    end else begin
                        bit_cnt <= bit_cnt - 1;
                        state <= S_ADDR_SEND;
                    end
                end
                S_READ_BIT: begin
                    spi_clk <= 0; 
                    state <= S_READ_BIT + 100;
                end
                S_READ_BIT + 100: begin
                    spi_clk <= 1; 
                    data_read <= {data_read[6:0], spi_miso};
                    if(bit_cnt == 0) state <= S_UART_HIGH; 
                    else begin
                        bit_cnt <= bit_cnt - 1;
                        state <= S_READ_BIT;
                    end
                end

                // 6. UART OUTPUT
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
                    uart_byte_to_send <= 8'h20; 
                    uart_trigger <= 1;
                    state <= S_WAIT_U3;
                end
                S_WAIT_U3: if(!uart_busy && !uart_trigger) state <= S_READ_NEXT;

                S_READ_NEXT: begin
                    if(byte_counter < 3) begin 
                        byte_counter <= byte_counter + 1;
                        bit_cnt <= 7;
                        state <= S_READ_BIT;
                    end else begin
                        state <= S_CS_H_FINAL;
                    end
                end

                S_CS_H_FINAL: begin
                    spi_cs <= 1;
                    spi_clk <= 0;
                    state <= S_UART_CR;
                end
                S_UART_CR: begin
                    uart_byte_to_send <= 8'h0D; 
                    uart_trigger <= 1;
                    state <= S_WAIT_U4;
                end
                S_WAIT_U4: if(!uart_busy && !uart_trigger) state <= S_UART_LF;

                S_UART_LF: begin
                    uart_byte_to_send <= 8'h0A; 
                    uart_trigger <= 1;
                    state <= S_WAIT_U5;
                end
                S_WAIT_U5: if(!uart_busy && !uart_trigger) state <= S_IDLE; 

            endcase
        end
    end
endmodule