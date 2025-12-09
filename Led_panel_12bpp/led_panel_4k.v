module led_panel_4k(
    input         clk,      // 25MHz (P3)

    // - PINES DE LA PANTALLA -
    output        LP_CLK,
    output        LATCH,
    output        NOE,
    output  [4:0] ROW,
    output  [2:0] RGB0,
    output  [2:0] RGB1,

    // - PINES DE LA SPI -
    output        spi_cs,
    output        spi_clk,
    output        spi_mosi,
    input         spi_miso
);

    // - Parámetros -
    parameter NUM_COLS = 64;
    parameter NUM_ROWS = 64;
    parameter NUM_ADDR = 2048;
    parameter DELAY = 50;

    // Generamos un reset interno que dura unos microsegundos y se apaga.
    reg [5:0] rst_cnt = 0;


    // Mientras el contador no llene el bit 5 (32 ciclos), w_rst_n es 0 (Reset Activo).
    // Luego se queda en 1 permanentemente (Funcionando).
    wire w_rst_n = rst_cnt[5];
    wire w_rst   = !w_rst_n;

    always @(posedge clk) begin
        if(!w_rst_n) rst_cnt <= rst_cnt + 1;
    end


    // - Cables Internos -
    wire w_ZR, w_ZC, w_ZD, w_ZI;
    wire w_LD, w_SHD;
    wire w_RST_R, w_RST_C, w_RST_D, w_RST_I;
    wire w_INC_R, w_INC_C, w_INC_D, w_INC_I;

    wire [10:0] count_delay;
    wire [10:0] delay;
    wire [1:0]  index;
    wire [($clog2(NUM_COLS)-1):0] COL;

    wire [11:0] PIX_ADDR;
    wire [23:0] mem_data;
    wire tmp_noe, tmp_latch;

    assign LATCH = ~tmp_latch;
    assign NOE   = tmp_noe;

    reg clk1;
    reg [4:0] clk_counter;

    always @(posedge clk) begin
        if (w_rst) begin
            clk_counter <= 0;
            clk1        <= 0;
        end else begin
            if(clk_counter == 1) begin
                clk1        <= ~clk1;
                clk_counter <= 0;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end
    end

    // - LECTURA -

    wire [11:0] loader_addr;
    wire [23:0] loader_data;
    wire        loader_wren;

    spi_loader u_loader (
        .clk(clk),
        .rst_n(w_rst_n),   // Conectado al auto-reset

        // Interfaz SPI
        .spi_cs(spi_cs),
        .spi_clk(spi_clk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),

        // Interfaz RAM
        .ram_addr(loader_addr),
        .ram_data(loader_data),
        .ram_wren(loader_wren)
    );

    // - MEMORIA DE VIDEO (RAM) -
    ram_dual u_video_ram (
        .clk(clk), 
        .we_a(loader_wren),
        .addr_a(loader_addr[10:0]), 
        .data_a(loader_data),
        .addr_b(PIX_ADDR[10:0]),
        .data_b(mem_data)
    );

    // - CONTROLADOR DE PANTALLA -
    assign PIX_ADDR = {ROW, COL};
    assign LP_CLK = clk1 & PX_CLK_EN;

    count #(.width(( $clog2(NUM_ADDR/NUM_COLS) -1) )) count_row (
        .clk(clk1), .reset(w_RST_R), .inc(w_INC_R), .outc(ROW), .zero(w_ZR)
    );
    count #(.width(($clog2(NUM_COLS) -1) )) count_col (
        .clk(clk1), .reset(w_RST_C), .inc(w_INC_C), .outc(COL), .zero(w_ZC)
    );
    count #(.width (10)) cnt_delay (
        .clk(clk1), .reset(w_RST_D), .inc(w_INC_D), .outc(count_delay)
    );
    count #(.width (1)) count_index (
        .clk(clk1), .reset(w_RST_I), .inc(w_INC_I), .outc(index), .zero(w_ZI)
    );
    lsr_led #(.init_value(DELAY), .width(10)) lsr_led0 (
        .clk(clk1), .load(w_LD), .shift(w_SHD), .s_A(delay)
    );
    comp_4k #(.width(10)) compa (
        .in1(delay), .in2(count_delay), .out(w_ZD)
    );
    mux_led mux0 (
        .in0(mem_data),
        .out0({RGB0, RGB1}),
        .sel(index)
    );
    ctrl_lp4k ctrl0 (
        .clk(clk1),
        .rst(w_rst),       // Auto-reset
        .init(1'b1),       // Init siempre activo
        .ZR(w_ZR), .ZC(w_ZC), .ZD(w_ZD), .ZI(w_ZI),
        .RST_R(w_RST_R), .RST_C(w_RST_C), .RST_D(w_RST_D), .RST_I(w_RST_I),
        .INC_R(w_INC_R), .INC_C(w_INC_C), .INC_D(w_INC_D), .INC_I(w_INC_I),
        .LD(w_LD), .SHD(w_SHD),
        .LATCH(tmp_latch), .NOE(tmp_noe),
        .PX_CLK_EN(PX_CLK_EN)
    );

endmodule