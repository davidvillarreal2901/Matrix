module led_panel_4k (
    input wire clk,           // 25MHz (Pin P3)
    input wire resetn,        // Pin K18 (No lo usamos para evitar bloqueos)
    input wire RXD,           // Pin H18 (No usado)

    // Interfaz SPI Flash Externa
    output wire spi_cs,       // B18
    output wire spi_clk,      // A19
    output wire spi_mosi,     // B20
    input  wire spi_miso,     // B19

    // UART y Estado
    output wire TXD,          // Pin J17
    output wire [0:0] LEDS,   // Pin U16

    // HUB75 a tierra
    output wire LP_CLK, LATCH, NOE,
    output wire [4:0] ROW,
    output wire [2:0] RGB0, RGB1
);

    // --- 1. Reset Automático (Power-On Reset) ---
    reg [3:0] startup_cnt = 0;
    reg sys_rst_n = 0;
    always @(posedge clk) begin
        if (startup_cnt < 15) begin
            startup_cnt <= startup_cnt + 1;
            sys_rst_n <= 0;
        end else begin
            sys_rst_n <= 1;
        end
    end

    // --- IMPORTANTE: Ignoramos el botón 'resetn' por ahora ---
    wire rst_global_n = sys_rst_n;

    // --- 2. Instancia del Diagnóstico ---
    wire diag_led;
    assign LEDS[0] = ~diag_led; // LED parpadea cuando el diagnóstico corre

    spi_flash_diag u_diag (
        .clk(clk),
        .rst_n(rst_global_n),
        .spi_cs(spi_cs),
        .spi_clk(spi_clk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .uart_tx_line(TXD),
        .diag_active(diag_led)
    );

    // --- 3. Apagar Matriz ---
    assign {LP_CLK, LATCH, NOE, ROW, RGB0, RGB1} = 0;

endmodule