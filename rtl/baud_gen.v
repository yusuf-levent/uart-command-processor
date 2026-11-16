// Kişi 1 (Sen) - Baud Rate Üreteci
module baud_gen #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire clk,
    input  wire rst_n,
    output reg  baud_tick
);

    // TODO: Baud rate üreteci mantığını ekleyin

endmodule
