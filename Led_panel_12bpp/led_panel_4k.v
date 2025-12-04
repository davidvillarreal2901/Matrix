module led_panel_4k (
    input wire clk,           // 25MHz (Pin P3)
    input wire resetn,        // Botón Reset (Active Low - Pin K18)
    input wire RXD,           // UART RX (Pin H18) - No usado pero definido en LPF

    // Interfaz SPI Flash Externa
    output wire spi_cs,       // B18
    output wire spi_clk,      // A19
    output wire spi_mosi,     // B20
    input  wire spi_miso,     // B19

    // UART y Estado
    output wire TXD,          // UART TX (Pin J17)
    output wire [0:0] LEDS,   // LED de estado (Pin U16)

    // Señales HUB75 (Definidas en LPF, las ponemos a 0 por seguridad)
    output wire LP_CLK,
    output wire LATCH,
    output wire NOE,
    output wire [4:0] ROW,
    output wire [2:0] RGB0,
    output wire [2:0] RGB1
);

    // --- Gestión de Reset ---
    // Combinamos el reset interno (arranque suave) con el botón externo
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

    // Reset general: Activo si el botón se pulsa (0) O si está arrancando (0)
    wire rst_global_n = sys_rst_n & resetn;

    // --- Instancia del Diagnóstico SPI ---
    // Usamos LEDS[0] para ver el parpadeo de estado
    wire diag_led;
    assign LEDS[0] = diag_led; // Invertimos porque a veces los LEDs en placa son Active Low (si no parpadea, quita el ~)

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

    // --- Apagar pines de la Matriz (Safety) ---
    // Evita que la matriz haga cosas raras mientras pruebas la memoria
    assign LP_CLK = 0;
    assign LATCH  = 0;
    assign NOE    = 1; // NOE alto apaga los LEDs (Output Enable negado)
    assign ROW    = 5'b0;
    assign RGB0   = 3'b0;
    assign RGB1   = 3'b0;

endmodule