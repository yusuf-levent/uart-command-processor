// Kişi 1 (Sen) - Tüm Modülleri Birbirine Bağlayan Ana Modül
module uart_top #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire clk,
    input  wire rst_n,
    input  wire rx,
    output wire tx
);

    // TODO: baud_gen, uart_rx, uart_tx, cmd_fsm ve flight_fsm bağlantılarını yapın

endmodule
