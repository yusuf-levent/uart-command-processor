// Kişi 1 - Baud Rate Üreteci (16x Oversampling Tick FSM: S0..S26)
module baud_gen #(
    parameter DIVISOR = 27  // 50 MHz / (16 * 115200) ~= 27 (S0..S26)
) (
    input  wire clk,
    input  wire rst,
    output reg  tick16
);

    localparam integer CNT_WIDTH = (DIVISOR > 1) ? $clog2(DIVISOR) : 1;

    reg [CNT_WIDTH-1:0] state;
    reg [CNT_WIDTH-1:0] next_state;

    // Durum register'ı (senkron aktif-yüksek reset -> S0)
    always @(posedge clk) begin
        if (rst) begin
            state <= {CNT_WIDTH{1'b0}};
        end else begin
            state <= next_state;
        end
    end

    // Sonraki durum ve Moore çıkış mantığı (S0..S25: OUT=0, S26: OUT=1)
    always @(*) begin
        if (state == DIVISOR - 1) begin
            next_state = {CNT_WIDTH{1'b0}};
            tick16     = 1'b1;
        end else begin
            next_state = state + 1'b1;
            tick16     = 1'b0;
        end
    end

endmodule
