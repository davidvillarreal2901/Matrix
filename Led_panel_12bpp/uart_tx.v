module uart_tx #(
    parameter CLK_FREQ = 25000000,
    parameter BAUD_RATE = 9600
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [7:0] data,
    output reg tx,
    output reg busy
);

    localparam CLK_DIV = CLK_FREQ / BAUD_RATE;
    reg [2:0] state;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_reg;

    localparam IDLE=0, START=1, DATA=2, STOP=3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tx <= 1;
            busy <= 0;
            clk_cnt <= 0;
            bit_idx <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1;
                    busy <= 0;
                    clk_cnt <= 0;
                    if (start) begin
                        state <= START;
                        busy <= 1;
                        data_reg <= data;
                    end
                end
                START: begin // Start Bit (0)
                    tx <= 0;
                    if (clk_cnt == CLK_DIV-1) begin
                        clk_cnt <= 0;
                        state <= DATA;
                        bit_idx <= 0;
                    end else clk_cnt <= clk_cnt + 1;
                end
                DATA: begin // 8 Bits
                    tx <= data_reg[bit_idx];
                    if (clk_cnt == CLK_DIV-1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 7) state <= STOP;
                        else bit_idx <= bit_idx + 1;
                    end else clk_cnt <= clk_cnt + 1;
                end
                STOP: begin // Stop Bit (1)
                    tx <= 1;
                    if (clk_cnt == CLK_DIV-1) begin
                        state <= IDLE;
                        busy <= 0;
                    end else clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end
endmodule