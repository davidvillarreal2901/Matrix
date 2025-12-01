module memory#(
    parameter FILENAME = "image.hex",
    // 64 cols * 32 rows = 2048 words per frame
    parameter WORDS_PER_FRAME = 2048,
    parameter N_FRAMES = 15, // De momento caben 15, pero hay que ajustar seg'un se pueda
                             //TAMBI'EN REVISAR EN EL TOP
    // Tamaño total = Frames * Words per frame
    parameter MEM_SIZE = WORDS_PER_FRAME * N_FRAMES
)(
    input             clk,
    input  [10:0]     pixel_addr, // Dirección dentro del frame (0-2047)
    input  [7:0]      frame_num,  // Qué frame mostrar
    output reg [23:0] rdata
);

    // Memoria inferida (Block RAM)
    reg [23:0] MEM [0:MEM_SIZE-1];

    initial begin
        $readmemh(FILENAME, MEM);
    end

    // Calcular dirección real: (Frame * 2048) + Pixel
    wire [31:0] real_addr;
    assign real_addr = (frame_num * WORDS_PER_FRAME) + pixel_addr;

    always @(posedge clk) begin
        rdata <= MEM[real_addr];
    end

endmodule