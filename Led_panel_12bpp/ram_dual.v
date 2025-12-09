module ram_dual (
    input wire clk,
    // Puerto A: Escritura
    input wire we_a, 
    input wire [11:0] addr_a, // 12 bits para llegar a 4095
    input wire [23:0] data_a,

    // Puerto B: Lectura (Lo usa el Panel LED)
    input wire [11:0] addr_b,
    output reg [23:0] data_b
);
    // 64 filas * 64 columnas = 4096 píxeles
    reg [23:0] ram [0:4095];

    always @(posedge clk) begin
        if (we_a) ram[addr_a] <= data_a;
        data_b <= ram[addr_b];
    end
endmodule