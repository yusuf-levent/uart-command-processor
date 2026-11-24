// Kişi 1 - Tüm Modülleri Birbirine Bağlayan Ana Modül
module uart_top #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire clk,
    input  wire rst_n,
    input  wire rx,
    output wire tx
);

    localparam integer DIVISOR = CLK_FREQ / (16 * BAUD_RATE);

    // Dış aktif-düşük reset (rst_n) -> iç aktif-yüksek reset (rst)
    wire rst = ~rst_n;

    // İç bağlantı sinyalleri
    wire       tick16;
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_err;
    wire       cmd_exec;
    wire [7:0] cmd_out;
    wire       flight_ok;
    wire       tx_start;
    wire [7:0] tx_data;
    wire       tx_busy;
    wire       tx_done;

    // 1) Baud rate üreteci (16x oversampling tick)
    baud_gen #(
        .DIVISOR (DIVISOR)
    ) u_baud_gen (
        .clk    (clk),
        .rst    (rst),
        .tick16 (tick16)
    );

    // 2) UART alıcı (RX)
    uart_rx u_uart_rx (
        .clk      (clk),
        .rst      (rst),
        .rx       (rx),
        .tick16   (tick16),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .rx_err   (rx_err)
    );

    // 3) Komut çözümleyici FSM
    cmd_fsm u_cmd_fsm (
        .clk       (clk),
        .rst       (rst),
        .rx_data   (rx_data),
        .pkt_len   (8'd1),     // Faz 2'de rx_parser.pkt_len bağlanacak
        .rx_valid  (rx_valid),
        .rx_err    (rx_err),
        .tx_busy   (tx_busy),
        .flight_ok (flight_ok),
        .cmd_exec  (cmd_exec),
        .cmd_out   (cmd_out),
        .tx_start  (tx_start),
        .tx_data   (tx_data)
    );

    // 4) Uçuş kontrol FSM
    flight_fsm u_flight_fsm (
        .clk       (clk),
        .rst       (rst),
        .cmd_exec  (cmd_exec),
        .cmd_in    (cmd_out),
        .flight_ok (flight_ok)
    );

    // 5) UART verici (TX)
    uart_tx u_uart_tx (
        .clk      (clk),
        .rst      (rst),
        .tick16   (tick16),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (tx),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

endmodule
