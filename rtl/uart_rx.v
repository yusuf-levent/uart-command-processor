// Kişi 3 - UART Alıcı (RX) Modülü
module uart_rx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       baud_tick,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);

    // TODO: UART RX durum makinesi ve örnekleme mantığını ekleyin

endmodule
