`timescale 1ns/1ps
// ============================================================================
// tb_fifo.v  -  rtl/fifo.v tekil testi (8 derinlik x 8 bit, FWFT)
//
// Arayuz (README Faz 2 sozlesmesi):
//   clk, rst, wr_en, wr_data[7:0], rd_en, rd_data[7:0], full, empty
//   FWFT: rd_data her zaman kuyrugun basindaki bayti gosterir (rd_en'den once gecerli);
//         rd_en bir clock darbesiyle o baytı kuyruktan atar.
//
// Calistirma:
//   iverilog -g2012 -o fifo.vvp rtl/fifo.v tb/tb_fifo.v
//   vvp fifo.vvp
// ============================================================================
module tb_fifo;

    localparam DEPTH = 8;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        wr_en = 1'b0;
    reg  [7:0] wr_data = 8'h00;
    reg        rd_en = 1'b0;
    wire [7:0] rd_data;
    wire       full;
    wire       empty;

    fifo dut (
        .clk     (clk),
        .rst     (rst),
        .wr_en   (wr_en),
        .wr_data (wr_data),
        .rd_en   (rd_en),
        .rd_data (rd_data),
        .full    (full),
        .empty   (empty)
    );

    always #5 clk = ~clk;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // ------------------------------------------------------------------ referans model
    reg [7:0] model [0:DEPTH-1];
    integer   m_rd = 0;      // model okuma gostergesi
    integer   m_cnt = 0;     // model eleman sayisi

    task model_reset;
        begin m_rd = 0; m_cnt = 0; end
    endtask

    task model_push(input [7:0] d);
        begin
            model[(m_rd + m_cnt) % DEPTH] = d;
            m_cnt = m_cnt + 1;
        end
    endtask

    task model_pop;
        begin
            m_rd  = (m_rd + 1) % DEPTH;
            m_cnt = m_cnt - 1;
        end
    endtask

    // ------------------------------------------------------------------ kontrol yardimcilari
    task check(input cond, input [8*48-1:0] msg);
        begin
            if (cond) begin
                pass_cnt = pass_cnt + 1;
                $display("PASS | %0s", msg);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL | %0s | full=%b empty=%b rd_data=%02h (model cnt=%0d)",
                         msg, full, empty, rd_data, m_cnt);
            end
        end
    endtask

    // Sessiz kontrol: sadece hata durumunda yazar (rastgele testte kullanilir)
    integer silent_err = 0;
    task check_model_state;
        begin
            if (full !== (m_cnt == DEPTH)) begin
                silent_err = silent_err + 1;
                $display("FAIL | full bayragi yanlis: full=%b model cnt=%0d t=%0t", full, m_cnt, $time);
            end
            if (empty !== (m_cnt == 0)) begin
                silent_err = silent_err + 1;
                $display("FAIL | empty bayragi yanlis: empty=%b model cnt=%0d t=%0t", empty, m_cnt, $time);
            end
            if (m_cnt > 0 && rd_data !== model[m_rd]) begin
                silent_err = silent_err + 1;
                $display("FAIL | rd_data=%02h beklenen=%02h t=%0t", rd_data, model[m_rd], $time);
            end
        end
    endtask

    // Bir clock adimi: negedge'de surer, posedge'de DUT calisir, modeli gunceller.
    // Esanlı yazma+okuma sadece full/empty olmadiginda kullanilmalidir
    // (sinir durumunda davranis tasarima bagli oldugundan test edilmez).
    task step(input wr, input [7:0] wd, input rd);
        reg do_push, do_pop;
        begin
            wr_en = wr; wr_data = wd; rd_en = rd;
            do_pop  = rd && (m_cnt > 0);
            do_push = wr && (m_cnt < DEPTH);
            @(posedge clk);
            if (do_pop)  model_pop;
            if (do_push) model_push(wd);
            @(negedge clk);
            wr_en = 1'b0; rd_en = 1'b0;
        end
    endtask

    task write_byte(input [7:0] d);
        begin step(1'b1, d, 1'b0); end
    endtask

    // FWFT: okumadan ONCE rd_data'yi kontrol et, sonra rd_en darbesi ver
    task read_check(input [7:0] expected, input [8*48-1:0] msg);
        begin
            if (rd_data === expected) begin
                pass_cnt = pass_cnt + 1;
                $display("PASS | %0s (okunan=%02h)", msg, rd_data);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL | %0s | okunan=%02h beklenen=%02h", msg, rd_data, expected);
            end
            step(1'b0, 8'h00, 1'b1);
        end
    endtask

    integer i, k, seed;
    reg [7:0] rnd;
    reg       rw, rr;

    // ------------------------------------------------------------------ senaryolar
    initial begin
        $dumpfile("dump_fifo.vcd");
        $dumpvars(0, tb_fifo);

        // ---- reset
        rst = 1'b1; model_reset;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        $display("=== 1) Reset sonrasi ===");
        check(empty === 1'b1 && full === 1'b0, "reset sonrasi empty=1, full=0");

        // ---- 8 bayt doldur
        $display("=== 2) 8 bayt yaz -> full ===");
        for (i = 0; i < DEPTH; i = i + 1) begin
            write_byte(8'hA0 + i);
            if (i == 0)
                check(empty === 1'b0, "ilk yazmadan sonra empty=0");
            if (i == 0)
                check(rd_data === 8'hA0, "FWFT: ilk bayt rd_data'da gorunuyor");
            if (i < DEPTH-1 && full !== 1'b0) begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL | %0d. yazmadan sonra full erken 1 oldu", i+1);
            end
        end
        check(full === 1'b1 && empty === 1'b0, "8 yazmadan sonra full == 1");

        // ---- 9. yazma: overflow korumasi
        $display("=== 3) 9. yazma -> overflow korumasi ===");
        write_byte(8'hEE);
        check(full === 1'b1, "9. yazmadan sonra full hala 1");
        check(rd_data === 8'hA0, "9. yazma bas bayti bozmadi");

        // ---- 8 bayt oku, sirayi dogrula
        $display("=== 4) 8 bayt oku -> sira ve empty ===");
        for (i = 0; i < DEPTH; i = i + 1)
            read_check(8'hA0 + i, "okuma sirasi (FIFO)");
        check(empty === 1'b1 && full === 1'b0, "8 okumadan sonra empty == 1, full == 0");

        // 9. yazilan 0xEE kuyruga girmis olmamali
        check(empty === 1'b1, "0xEE kuyruga girmedi (hala bos)");

        // ---- underflow
        $display("=== 5) Bos FIFO'dan okuma (underflow) ===");
        step(1'b0, 8'h00, 1'b1);
        step(1'b0, 8'h00, 1'b1);
        check(empty === 1'b1 && full === 1'b0, "bos iken rd_en: empty=1 kaldi");
        write_byte(8'h5A);
        check(empty === 1'b0 && rd_data === 8'h5A, "underflow sonrasi yazma/okuma normal");
        read_check(8'h5A, "underflow sonrasi okuma");
        check(empty === 1'b1, "tekrar bos");

        // ---- pointer wrap-around
        $display("=== 6) Gosterge tasma (wrap-around) ===");
        for (k = 0; k < 3; k = k + 1) begin
            for (i = 0; i < 5; i = i + 1) write_byte(8'h10 * k + i + 8'h01);
            for (i = 0; i < 5; i = i + 1) read_check(8'h10 * k + i + 8'h01, "wrap-around okuma");
        end
        check(empty === 1'b1, "wrap-around sonrasi bos");

        // ---- esanlı okuma + yazma
        $display("=== 7) Esanli okuma + yazma ===");
        silent_err = 0;
        for (i = 0; i < 4; i = i + 1) write_byte(8'hC0 + i);     // 4 eleman
        for (i = 0; i < 12; i = i + 1) begin
            // beklenen: bastaki bayt okunurken yeni bayt yazilir, doluluk 4 kalir
            if (rd_data !== model[m_rd]) begin
                silent_err = silent_err + 1;
                $display("FAIL | esanli okuma: rd_data=%02h beklenen=%02h", rd_data, model[m_rd]);
            end
            step(1'b1, 8'hD0 + i, 1'b1);
        end
        check(full === 1'b0 && empty === 1'b0, "esanli islem sonrasi 4 eleman (full=0, empty=0)");
        for (i = 0; i < 4; i = i + 1) begin
            if (rd_data !== model[m_rd]) begin
                silent_err = silent_err + 1;
                $display("FAIL | bosaltma: rd_data=%02h beklenen=%02h", rd_data, model[m_rd]);
            end
            step(1'b0, 8'h00, 1'b1);
        end
        check(empty === 1'b1, "esanli test sonrasi bos");
        check(silent_err == 0, "esanli okuma+yazma: tum baytlar sirayla dogru");

        // ---- rastgele test (referans modelle karsilastirma)
        $display("=== 8) Rastgele okuma/yazma (referans model) ===");
        seed = 32'h1234_ABCD;
        silent_err = 0;
        for (i = 0; i < 2000; i = i + 1) begin
            rnd = $random(seed);
            rw = $random(seed);
            rr = $random(seed);
            // sinirda (bos/dolu) esanli islem yapma: davranis tasarima bagli
            if (m_cnt == 0 || m_cnt == DEPTH) begin
                if (rw && rr) rr = 1'b0;
            end
            check_model_state;
            step(rw, rnd, rr);
        end
        check_model_state;
        check(silent_err == 0, "2000 rastgele adim: full/empty/rd_data model ile uyumlu");

        // ---- reset: dolu FIFO'yu bosaltir
        $display("=== 9) Dolu FIFO'da reset ===");
        for (i = 0; i < DEPTH; i = i + 1) write_byte(8'h30 + i);
        rst = 1'b1; model_reset;
        @(posedge clk); @(negedge clk);
        rst = 1'b0;
        check(empty === 1'b1 && full === 1'b0, "reset sonrasi empty=1, full=0");
        write_byte(8'h77);
        read_check(8'h77, "reset sonrasi ilk bayt");

        $display("----------------------------------------");
        $display("SONUC: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
        $display("%0s", (fail_cnt == 0) ? "TUM TESTLER GECTI" : "BAZI TESTLER BASARISIZ");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("WATCHDOG: simulasyon cok uzadi");
        $finish;
    end

endmodule
