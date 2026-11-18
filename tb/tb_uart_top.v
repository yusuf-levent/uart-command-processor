`timescale 1ns/1ps
// ============================================================================
// tb_uart_top.v  -  Faz 1 testbench
//
// Varsayilan mod  : LOOPBACK (assign tx = rx)  -> testbench'in kendisini test eder
// Gercek DUT modu : derlerken -DUSE_DUT ekle   -> uart_top baglanir
//
//   Loopback : iverilog -g2012 -o sim.vvp rtl/*.v tb/tb_uart_top.v
//   Gercek   : iverilog -g2012 -DUSE_DUT -o sim.vvp rtl/*.v tb/tb_uart_top.v
//   vvp sim.vvp   ->  gtkwave dump.vcd
// ============================================================================
module tb_uart_top;

    // ------------------------------------------------------------------ zamanlama
    localparam CLK_FREQ     = 50_000_000;      // uart_top ile ayni degerler
    localparam BAUD_RATE    = 115200;
    localparam CLK_DIV      = CLK_FREQ / (16 * BAUD_RATE);  // tick16 basina clock = 27
    localparam BIT_CLKS     = CLK_DIV * 16;                 // 1 bit = 432 clock
    localparam CLK_HALF_NS  = 10;              // 50 MHz
    localparam TX_PARITY    = 1;               // frame: start, 8 bit, parity, stop (plan dokumani)
    localparam TIMEOUT_CLKS = 40 * BIT_CLKS;   // cevap bekleme zaman asimi

    // ------------------------------------------------------------------ sadece dis portlar
    reg  clk = 1'b0;
    reg  rst_n = 1'b0;   // aktif-dusuk reset
    reg  rx  = 1'b1;     // hat bos = 1
    wire tx;

    always #(CLK_HALF_NS) clk = ~clk;   // 50 MHz

    // ------------------------------------------------------------------ DUT / loopback
`ifdef USE_DUT
    uart_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (rx),
        .tx    (tx)
    );
`else
    assign tx = rx;    // gecici loopback
`endif

    // ------------------------------------------------------------------ sayaclar
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // ------------------------------------------------------------------ send_byte
    // Start(0) -> D0..D7 -> Even parity -> Stop(1) -> 1 bit bosluk
    task send_byte(input [7:0] data, input bad_parity, input bad_stop);
        integer i;
        begin
            rx = 1'b0;                                   // Start
            repeat (BIT_CLKS) @(posedge clk);

            for (i = 0; i < 8; i = i + 1) begin          // LSB first
                rx = data[i];
                repeat (BIT_CLKS) @(posedge clk);
            end

            rx = bad_parity ? ~(^data) : (^data);        // Even parity
            repeat (BIT_CLKS) @(posedge clk);

            rx = bad_stop ? 1'b0 : 1'b1;                 // Stop (bozuksa 0)
            repeat (BIT_CLKS) @(posedge clk);

            rx = 1'b1;                                   // hat bos
            repeat (BIT_CLKS) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------ receive_byte
    // tx'in 0'a dusmesini bekle -> yarim bit sonra start'i dogrula -> 8 bit ornekle
    task receive_byte(output [7:0] data, output timed_out, output frame_ok);
        integer i, t;
        begin
            data = 8'h00; timed_out = 1'b0; frame_ok = 1'b1;

            t = 0;
            while (tx !== 1'b0 && t < TIMEOUT_CLKS) begin
                @(posedge clk);
                t = t + 1;
            end

            if (t >= TIMEOUT_CLKS) begin
                timed_out = 1'b1;
            end else begin
                repeat (BIT_CLKS/2) @(posedge clk);          // start bitinin ortasi
                if (tx !== 1'b0) frame_ok = 1'b0;            // glitch

                for (i = 0; i < 8; i = i + 1) begin
                    repeat (BIT_CLKS) @(posedge clk);
                    data[i] = tx;
                end

                if (TX_PARITY) begin
                    repeat (BIT_CLKS) @(posedge clk);
                    if (tx !== ^data) frame_ok = 1'b0;       // parity kontrol
                end

                repeat (BIT_CLKS) @(posedge clk);            // stop
                if (tx !== 1'b1) frame_ok = 1'b0;
            end
        end
    endtask

    // ------------------------------------------------------------------ run_test
    // Gonderme ve dinleme es zamanli (fork/join)
    task run_test(input [7:0] sent, input [7:0] expected,
                  input bp, input bs, input [8*28-1:0] label);
        reg [7:0] got;
        reg       to, fok;
        begin
            fork
                send_byte(sent, bp, bs);
                receive_byte(got, to, fok);
            join

            if (to) begin
                fail_cnt = fail_cnt + 1;
                $display("Gonderilen: %c | Beklenen: %c | Gelen: -(zaman asimi) | FAIL | %0s",
                         sent, expected, label);
            end else if (got === expected && fok) begin
                pass_cnt = pass_cnt + 1;
                $display("Gonderilen: %c | Beklenen: %c | Gelen: %c | PASS | %0s",
                         sent, expected, got, label);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("Gonderilen: %c | Beklenen: %c | Gelen: %c | FAIL%0s | %0s",
                         sent, expected, got, fok ? "" : " (cerceve hatasi)", label);
            end
        end
    endtask

    // ------------------------------------------------------------------ senaryolar
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_uart_top);

        // reset
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (2 * BIT_CLKS) @(posedge clk);

`ifndef USE_DUT
        // ---------------- LOOPBACK: gonderilen = okunan olmali
        $display("=== LOOPBACK oz-test (tx = rx) ===");
        run_test("A", "A", 0, 0, "loopback");
        run_test("K", "K", 0, 0, "loopback");
        run_test("E", "E", 0, 0, "loopback");
        run_test(8'h55, 8'h55, 0, 0, "loopback 01010101");
        run_test("~", "~", 0, 0, "loopback 01111110");
`else
        // ---------------- 1) Normal ucus akisi
        $display("=== Normal ucus akisi ===");
        run_test("A", "K", 0, 0, "Arm");
        run_test("T", "K", 0, 0, "Flight");
        run_test("L", "K", 0, 0, "Landing");
        run_test("D", "K", 0, 0, "Disarm");

        // ---------------- 2) Failsafe
        $display("=== Failsafe testi ===");
        run_test("A", "K", 0, 0, "Arm");
        run_test("T", "K", 0, 0, "Flight");
        run_test("F", "K", 0, 0, "Failsafe");
        run_test("A", "E", 0, 0, "Failsafe'de Arm reddedilmeli");
        run_test("R", "K", 0, 0, "Reset");

        // ---------------- 3) Gecersiz durum (DISARMED)
        $display("=== Gecersiz durum testi ===");
        run_test("T", "E", 0, 0, "DISARMED'da Flight");
        run_test("D", "E", 0, 0, "DISARMED'da Disarm");

        // ---------------- 4) Bilinmeyen harf & hat hatalari
        $display("=== Bilinmeyen harf / hat hatasi ===");
        run_test("Z", "E", 0, 0, "Bilinmeyen komut");
        run_test("A", "E", 1, 0, "Bozuk parity");
        run_test("A", "E", 0, 1, "Bozuk stop biti");

        // hat hatalarindan sonra DUT hala saglam mi?
        run_test("A", "K", 0, 0, "Toparlanma kontrolu: Arm");
`endif

        $display("----------------------------------------");
        $display("SONUC: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
        $display("%0s", (fail_cnt == 0) ? "TUM TESTLER GECTI" : "BAZI TESTLER BASARISIZ");
        $finish;
    end

    // ------------------------------------------------------------------ watchdog
    initial begin
        #200_000_000;   // 200 ms
        $display("WATCHDOG: simulasyon cok uzadi, sonlandiriliyor");
        $finish;
    end

endmodule
