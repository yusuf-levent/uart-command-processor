// Kişi 2 - UART Verici (TX) Modülü
module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       baud_tick,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx,
    output reg        tx_busy
);

    // TODO: UART TX durum makinesi ve veri gönderme mantığını ekleyin

endmodule
