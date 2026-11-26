`timescale 1ns/1ps
// ============================================================================
// tb_uart_top.v  -  Faz 2 testbench (FIFO + Paket + CRC-8)
//
// Paket formati : [0x7E] [LEN] [DATA_0..DATA_LEN-1] [CRC8]
// CRC-8/SMBUS   : poly 8'h07, init 8'h00, sadece LEN + DATA uzerinden
// UART cercevesi: 8E1 (start, 8 bit LSB-first, even parity, stop)
//
//   Loopback (tb oz-testi): iverilog -g2012 -o loop.vvp tb/tb_uart_top.v
//   Gercek sistem         : iverilog -g2012 -DUSE_DUT -o sim.vvp rtl/*.v tb/tb_uart_top.v
//   vvp sim.vvp   ->   gtkwave dump.vcd
// ============================================================================
module tb_uart_top;

    // ------------------------------------------------------------------ zamanlama
    localparam CLK_FREQ     = 50_000_000;
    localparam BAUD_RATE    = 115200;
    localparam CLK_DIV      = CLK_FREQ / (16 * BAUD_RATE);   // 27
    localparam BIT_CLKS     = CLK_DIV * 16;                  // 432
    localparam CLK_HALF_NS  = 10;                            // 50 MHz
    localparam TX_PARITY    = 1;                             // cevap cercevesinde parity var
    localparam TIMEOUT_CLKS = 80 * BIT_CLKS;                 // cevap bekleme zaman asimi

    // ------------------------------------------------------------------ sadece dis portlar
    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    reg  rx    = 1'b1;
    wire tx;

    always #(CLK_HALF_NS) clk = ~clk;

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
    assign tx = rx;    // loopback
`endif

    // ------------------------------------------------------------------ sayaclar
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // ------------------------------------------------------------------ CRC-8/SMBUS
    function [7:0] crc8_byte(input [7:0] crc_in, input [7:0] b);
        integer k;
        reg [7:0] c;
        begin
            c = crc_in ^ b;
            for (k = 0; k < 8; k = k + 1)
                c = c[7] ? ({c[6:0], 1'b0} ^ 8'h07) : {c[6:0], 1'b0};
            crc8_byte = c;
        end
    endfunction

    // LEN + tek DATA baytinin CRC'si (LEN=1 paketleri icin)
    function [7:0] crc8_calc(input [7:0] len, input [7:0] data);
        crc8_calc = crc8_byte(crc8_byte(8'h00, len), data);
    endfunction

    // Yazdirilabilir karakter (konsola bozuk bayt basmamak icin)
    function [7:0] pc(input [7:0] c);
        pc = (c >= 8'h20 && c <= 8'h7E) ? c : "?";
    endfunction

    // ------------------------------------------------------------------ send_byte (8E1)
    // bad_stop ise stop biti 0 gonderilir, ardindan 1 bit bosluk birakilir
    // (hat yukselmezse alici yeniden senkronlanamaz).
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
            rx = bad_stop ? 1'b0 : 1'b1;                 // Stop
            repeat (BIT_CLKS) @(posedge clk);
            rx = 1'b1;
            if (bad_stop) repeat (BIT_CLKS) @(posedge clk);
        end
    endtask

    task idle_bits(input integer n);
        begin
            rx = 1'b1;
            repeat (n * BIT_CLKS) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------ send_packet
    // Paket baytlari: idx0=7E, idx1=LEN, idx2..LEN+1=DATA (hepsi cmd), idx LEN+2=CRC
    //   len       : LEN alani (0 ve 5 gibi gecersiz degerler de verilebilir)
    //   flip_idx  : bu indeksteki bayti flip_mask ile XOR'la (CRC hesabindan SONRA); -1 = yok
    //   bp_idx    : bu indeksteki bayti bozuk parity ile gonder; -1 = yok
    //   bs_idx    : bu indeksteki bayti bozuk stop ile gonder; -1 = yok
    //   nsend     : sadece ilk nsend bayti gonder (kisa paket); -1 = hepsi
    task send_packet(input [7:0] cmd, input [7:0] len,
                     input integer flip_idx, input [7:0] flip_mask,
                     input integer bp_idx, input integer bs_idx,
                     input integer nsend);
        integer idx, total;
        reg [7:0] crc, b;
        begin
            crc = crc8_byte(8'h00, len);
            for (idx = 0; idx < len; idx = idx + 1) crc = crc8_byte(crc, cmd);

            total = len + 3;
            if (nsend >= 0 && nsend < total) total = nsend;

            for (idx = 0; idx < total; idx = idx + 1) begin
                if (idx == 0)            b = 8'h7E;
                else if (idx == 1)       b = len;
                else if (idx == len + 2) b = crc;
                else                     b = cmd;
                if (idx == flip_idx) b = b ^ flip_mask;
                send_byte(b, (idx == bp_idx), (idx == bs_idx));
            end
        end
    endtask

    // ------------------------------------------------------------------ receive_byte
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
                repeat (BIT_CLKS/2) @(posedge clk);
                if (tx !== 1'b0) frame_ok = 1'b0;
                for (i = 0; i < 8; i = i + 1) begin
                    repeat (BIT_CLKS) @(posedge clk);
                    data[i] = tx;
                end
                if (TX_PARITY) begin
                    repeat (BIT_CLKS) @(posedge clk);
                    if (tx !== ^data) frame_ok = 1'b0;
                end
                repeat (BIT_CLKS) @(posedge clk);
                if (tx !== 1'b1) frame_ok = 1'b0;
            end
        end
    endtask

    // ------------------------------------------------------------------ receive_packet
    // 4 bayt okur: pkt = {7E, LEN, DATA, CRC}
    // frame_ok = tum UART cerceveleri saglam
    task receive_packet(output [31:0] pkt, output timed_out, output frame_ok);
        integer n;
        reg [7:0] b;
        reg       to, fok;
        begin
            pkt = 32'h0; timed_out = 1'b0; frame_ok = 1'b1;
            for (n = 0; n < 4; n = n + 1) begin
                if (!timed_out) begin
                    receive_byte(b, to, fok);
                    if (to) timed_out = 1'b1;
                    else begin
                        pkt = {pkt[23:0], b};
                        if (!fok) frame_ok = 1'b0;
                    end
                end
            end
        end
    endtask

    // ------------------------------------------------------------------ raporlama
    task report(input [7:0] sent, input [7:0] expected, input [31:0] got_pkt,
                input to, input fok, input [8*40-1:0] label);
        reg [31:0] exp_pkt;
        begin
            exp_pkt = {8'h7E, 8'h01, expected, crc8_calc(8'h01, expected)};
            if (to) begin
                fail_cnt = fail_cnt + 1;
                $display("Gonderilen: %c | Beklenen: %c | Gelen: -(zaman asimi) | FAIL | %0s",
                         pc(sent), pc(expected), label);
            end else if (got_pkt === exp_pkt && fok) begin
                pass_cnt = pass_cnt + 1;
                $display("Gonderilen: %c | Beklenen: %c | Gelen: %c [%02X %02X %02X %02X] | PASS | %0s",
                         pc(sent), pc(expected), pc(got_pkt[15:8]),
                         got_pkt[31:24], got_pkt[23:16], got_pkt[15:8], got_pkt[7:0], label);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("Gonderilen: %c | Beklenen: %c [%02X %02X %02X %02X] | Gelen: %c [%02X %02X %02X %02X] | FAIL%0s | %0s",
                         pc(sent), pc(expected),
                         exp_pkt[31:24], exp_pkt[23:16], exp_pkt[15:8], exp_pkt[7:0],
                         pc(got_pkt[15:8]),
                         got_pkt[31:24], got_pkt[23:16], got_pkt[15:8], got_pkt[7:0],
                         fok ? "" : " (cerceve hatasi)", label);
            end
        end
    endtask

    // ------------------------------------------------------------------ run_pkt_test
    // Paketi gonderirken es zamanli olarak 4 baytlik cevap paketini dinler.
    task run_pkt_test(input [7:0] cmd, input [7:0] expected, input [7:0] len,
                      input integer flip_idx, input [7:0] flip_mask,
                      input integer bp_idx, input integer bs_idx, input integer nsend,
                      input [8*40-1:0] label);
        reg [31:0] got;
        reg        to, fok;
        begin
            fork
                send_packet(cmd, len, flip_idx, flip_mask, bp_idx, bs_idx, nsend);
                receive_packet(got, to, fok);
            join
            report(cmd, expected, got, to, fok, label);
            idle_bits(2);
        end
    endtask

    // Normal, hatasiz LEN=1 paketi
    task run_cmd(input [7:0] cmd, input [7:0] expected, input [8*40-1:0] label);
        run_pkt_test(cmd, expected, 8'h01, -1, 8'h00, -1, -1, -1, label);
    endtask

    // ------------------------------------------------------------------ arka arkaya 3 paket
    // Cevap beklenmeden peş peşe gonderilir, 3 ayri cevap paketi okunur.
    task run_burst3(input [7:0] c0, input [7:0] c1, input [7:0] c2,
                    input [7:0] e0, input [7:0] e1, input [7:0] e2);
        reg [31:0] g0, g1, g2;
        reg        t0, t1, t2, f0, f1, f2;
        begin
            fork
                begin
                    send_packet(c0, 8'h01, -1, 8'h00, -1, -1, -1);
                    send_packet(c1, 8'h01, -1, 8'h00, -1, -1, -1);
                    send_packet(c2, 8'h01, -1, 8'h00, -1, -1, -1);
                end
                begin
                    receive_packet(g0, t0, f0);
                    receive_packet(g1, t1, f1);
                    receive_packet(g2, t2, f2);
                end
            join
            report(c0, e0, g0, t0, f0, "Back-to-back 1/3");
            report(c1, e1, g1, t1, f1, "Back-to-back 2/3");
            report(c2, e2, g2, t2, f2, "Back-to-back 3/3");
            idle_bits(2);
        end
    endtask

    // ------------------------------------------------------------------ CRC oz-testi
    task crc_check(input [7:0] cmd, input [7:0] expected_crc);
        begin
            if (crc8_calc(8'h01, cmd) === expected_crc) begin
                pass_cnt = pass_cnt + 1;
                $display("CRC8 oz-test: 7E 01 %02X %02X | PASS", cmd, expected_crc);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("CRC8 oz-test: 7E 01 %02X | Beklenen: %02X | Hesaplanan: %02X | FAIL",
                         cmd, expected_crc, crc8_calc(8'h01, cmd));
            end
        end
    endtask

    // tx hatti n bit suresince bos (1) kalmali
    task check_silence(input integer n, input [8*40-1:0] label);
        integer c;
        reg bad;
        begin
            bad = 1'b0;
            for (c = 0; c < n * BIT_CLKS; c = c + 1) begin
                @(posedge clk);
                if (tx !== 1'b1) bad = 1'b1;
            end
            if (bad) begin
                fail_cnt = fail_cnt + 1;
                $display("tx sessizlik kontrolu | FAIL (hatta beklenmeyen aktivite) | %0s", label);
            end else begin
                pass_cnt = pass_cnt + 1;
                $display("tx sessizlik kontrolu | PASS | %0s", label);
            end
        end
    endtask

    // ------------------------------------------------------------------ senaryolar
    // Ucus durumu her senaryo basinda/sonunda DISARMED olacak sekilde tutulur.
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_uart_top);

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        idle_bits(4);

        $display("=== CRC-8 oz-testi (README referans paketleri) ===");
        crc_check("A", 8'hD5);  crc_check("D", 8'hCE);
        crc_check("T", 8'hBE);  crc_check("L", 8'hF6);
        crc_check("F", 8'hC0);  crc_check("R", 8'hAC);
        crc_check("K", 8'hE3);  crc_check("E", 8'hC9);

`ifndef USE_DUT
        // ---------------- LOOPBACK: gonderilen paket = okunan paket
        $display("=== LOOPBACK oz-test (tx = rx) ===");
        run_cmd("K", "K", "loopback K paketi");
        run_cmd("E", "E", "loopback E paketi");
        run_burst3("K", "E", "K", "K", "E", "K");
`else
        // ---------------- 1) Normal ucus paketleri
        $display("=== 1) Normal ucus paketleri ===");
        run_cmd("A", "K", "Arm");
        run_cmd("T", "K", "Flight");
        run_cmd("L", "K", "Landing");
        run_cmd("D", "K", "Disarm");

        // ---------------- 2) Failsafe akisi
        $display("=== 2) Failsafe akisi ===");
        run_cmd("A", "K", "Arm");
        run_cmd("T", "K", "Flight");
        run_cmd("F", "K", "Failsafe");
        run_cmd("A", "E", "Failsafe'de Arm reddedilmeli");
        run_cmd("R", "K", "Reset -> DISARMED");

        // ---------------- 3) CRC bit bozma (DISARMED'da kalmali)
        $display("=== 3) CRC bit bozma ===");
        run_pkt_test("A", "E", 8'h01, 3, 8'h01, -1, -1, -1, "A paketi, CRC bit0 bozuk");
        run_cmd("T", "E", "DISARMED'da kaldi mi? (T -> E)");
        run_pkt_test("A", "E", 8'h01, 2, 8'h01, -1, -1, -1, "A paketi, DATA bit0 bozuk");
        run_cmd("T", "E", "DISARMED'da kaldi mi? (T -> E)");

        // ---------------- 4) Kisa / yarim paket (timeout)
        $display("=== 4) Kisa paket ===");
        run_pkt_test("A", "E", 8'h01, -1, 8'h00, -1, -1, 2, "Sadece 7E 01, timeout bekle");
        run_cmd("A", "K", "Toparlanma: Arm (ARMED)");

        // ---------------- 5) Yanlis uzunluk
        $display("=== 5) Yanlis uzunluk ===");
        run_pkt_test("A", "E", 8'h00, -1, 8'h00, -1, -1, -1, "LEN = 0");
        run_pkt_test("A", "E", 8'h05, -1, 8'h00, -1, -1, -1, "LEN = 5");
        run_cmd("D", "K", "Toparlanma: Disarm (DISARMED)");

        // ---------------- 6) Arka arkaya paketler
        $display("=== 6) Back-to-back paketler ===");
        run_burst3("A", "T", "L", "K", "K", "K");
        run_cmd("D", "K", "Temizlik: Disarm (DISARMED)");

        // ---------------- 7) Orta yerde rst_n
        $display("=== 7) Orta yerde reset ===");
        run_cmd("A", "K", "Hazirlik: Arm");
        run_cmd("T", "K", "Hazirlik: Flight (FLIGHT)");
        send_byte(8'h7E, 1'b0, 1'b0);              // yarim paket: 7E 01 ...
        send_byte(8'h01, 1'b0, 1'b0);
        rst_n = 1'b0;                               // paket ortasinda reset
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        check_silence(30, "reset sonrasi cevap gelmemeli");
        run_cmd("A", "K", "Reset sonrasi Arm kabul (DISARMED)");
        run_cmd("D", "K", "Temizlik: Disarm (DISARMED)");

        // ---------------- 8) Paket icinde bozuk parity / stop
        $display("=== 8) Bozuk parity ve bozuk stop ===");
        run_pkt_test("A", "E", 8'h01, -1, 8'h00, 2, -1, -1, "A paketi, DATA baytinda bozuk parity");
        run_cmd("A", "K", "Toparlanma: Arm (ARMED)");
        run_pkt_test("D", "E", 8'h01, -1, 8'h00, -1, 2, -1, "D paketi, DATA baytinda bozuk stop");
        run_cmd("D", "K", "Toparlanma: Disarm (DISARMED)");
`endif

        $display("----------------------------------------");
        $display("SONUC: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
        $display("%0s", (fail_cnt == 0) ? "TUM TESTLER GECTI" : "BAZI TESTLER BASARISIZ");
        $finish;
    end

    // ------------------------------------------------------------------ watchdog
    initial begin
        #400_000_000;   // 400 ms
        $display("WATCHDOG: simulasyon cok uzadi, sonlandiriliyor");
        $finish;
    end

endmodule
