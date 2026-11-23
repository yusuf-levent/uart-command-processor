module uart_tx (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick16,     // baud_gen'den gelen darbe (bit hızının 16 katı)
    input  wire       tx_start,   // 1 saat darbesi: göndermeye başla
    input  wire [7:0] tx_data,    // gönderilecek bayt
    output reg        tx,         // seri hat (boşta 1)
    output wire       tx_busy,    // IDLE dışında 1
    output reg        tx_done     // frame bitince 1 saat darbesi
);

    // Durumlar
    localparam IDLE   = 3'd0,
               START  = 3'd1,
               DATA   = 3'd2,
               PARITY = 3'd3,
               STOP   = 3'd4;

    reg [2:0] state;
    reg [3:0] tick_cnt;   // 0-15: bir bitin süresi
    reg [2:0] bit_idx;    // 0-7: hangi veri biti
    reg [7:0] data_reg;   // gönderim boyunca sabit kalan kopya

    assign tx_busy = (state != IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            tx       <= 1'b1;
            tx_done  <= 1'b0;
            tick_cnt <= 4'd0;
            bit_idx  <= 3'd0;
            data_reg <= 8'd0;
        end else begin
            tx_done <= 1'b0;   // varsayılan: darbe sadece STOP sonunda 1 olur

            case (state)

                IDLE: begin
                    tx       <= 1'b1;
                    tick_cnt <= 4'd0;
                    bit_idx  <= 3'd0;
                    if (tx_start) begin
                        data_reg <= tx_data;   // veriyi bir kez kopyala
                        state    <= START;
                    end
                end

                START: begin
                    tx <= 1'b0;
                    if (tick16) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt <= 4'd0;
                            state    <= DATA;
                        end else
                            tick_cnt <= tick_cnt + 4'd1;
                    end
                end

                DATA: begin
                    tx <= data_reg[bit_idx];   // LSB önce
                    if (tick16) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt <= 4'd0;
                            if (bit_idx == 3'd7)
                                state <= PARITY;
                            else
                                bit_idx <= bit_idx + 3'd1;
                        end else
                            tick_cnt <= tick_cnt + 4'd1;
                    end
                end

                PARITY: begin
                    tx <= ^data_reg;           // even parity: 1'ler tekse 1 üretir
                    if (tick16) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt <= 4'd0;
                            state    <= STOP;
                        end else
                            tick_cnt <= tick_cnt + 4'd1;
                    end
                end

                STOP: begin
                    tx <= 1'b1;
                    if (tick16) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt <= 4'd0;
                            tx_done  <= 1'b1;  // 1 saat darbesi
                            state    <= IDLE;
                        end else
                            tick_cnt <= tick_cnt + 4'd1;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
