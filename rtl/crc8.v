// Kişi 1 - CRC-8/SMBUS Hesaplama Modülü (Polinom: 0x07, Başlangıç: 0x00, MSB-first)
// 1 clock çevriminde tek baytlık CRC-8 güncellemesi yapar.
module crc8 (
    input  wire       clk,
    input  wire       rst,
    input  wire       crc_init,  // 1 iken CRC sıfırlanır (8'h00)
    input  wire       crc_en,    // 1 iken data_in baytı CRC'ye işlenir
    input  wire [7:0] data_in,
    output reg  [7:0] crc_out
);

    function [7:0] crc8_step;
        input [7:0] crc_prev;
        input [7:0] data_byte;
        integer i;
        reg [7:0] c;
        begin
            c = crc_prev ^ data_byte;
            for (i = 0; i < 8; i = i + 1) begin
                if (c[7])
                    c = {c[6:0], 1'b0} ^ 8'h07;
                else
                    c = {c[6:0], 1'b0};
            end
            crc8_step = c;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            crc_out <= 8'h00;
        end else if (crc_init && crc_en) begin
            // Yeni paketi sıfırdan başlatıp aynı clock'ta ilk baytı işle
            crc_out <= crc8_step(8'h00, data_in);
        end else if (crc_init) begin
            crc_out <= 8'h00;
        end else if (crc_en) begin
            crc_out <= crc8_step(crc_out, data_in);
        end
    end

endmodule
