// Kişi 1 - Komut Çözümleyici FSM (Moore)
module cmd_fsm (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] rx_data,
    input  wire       rx_valid,
    input  wire       rx_err,
    input  wire       tx_busy,
    input  wire       flight_ok,
    output reg        cmd_exec,
    output wire [7:0] cmd_out,
    output reg        tx_start,
    output wire [7:0] tx_data
);

    localparam [2:0]
        IDLE     = 3'd0,
        DECODER  = 3'd1,
        EXECUTE  = 3'd2,
        ERROR    = 3'd3,
        RESPONSE = 3'd4,
        SEND     = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;
    reg [7:0] cmd_reg;
    reg [7:0] resp_reg;

    assign cmd_out = cmd_reg;
    assign tx_data = resp_reg;

    // Durum ve veri register'ları (senkron aktif-yüksek reset)
    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            cmd_reg  <= 8'h00;
            resp_reg <= 8'h00;
        end else begin
            state <= next_state;

            if (state == IDLE && !rx_err && rx_valid) begin
                cmd_reg <= rx_data;
            end

            if (state == EXECUTE && flight_ok) begin
                resp_reg <= 8'h4B; // "K"
            end else if (state == ERROR) begin
                resp_reg <= 8'h45; // "E"
            end
        end
    end

    // Moore çıkışları (sadece mevcut state'e bağlı)
    always @(*) begin
        cmd_exec = (state == EXECUTE);
        tx_start = (state == SEND);
    end

    // Sonraki durum mantığı
    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (rx_err) begin
                    next_state = ERROR;
                end else if (rx_valid) begin
                    next_state = DECODER;
                end else begin
                    next_state = IDLE;
                end
            end

            DECODER: begin
                case (cmd_reg)
                    "A", "D", "T", "L", "F", "R": next_state = EXECUTE;
                    default:                      next_state = ERROR;
                endcase
            end

            EXECUTE: begin
                if (flight_ok) begin
                    next_state = RESPONSE;
                end else begin
                    next_state = ERROR;
                end
            end

            ERROR: begin
                next_state = RESPONSE;
            end

            RESPONSE: begin
                if (tx_busy) begin
                    next_state = RESPONSE;
                end else begin
                    next_state = SEND;
                end
            end

            SEND: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
