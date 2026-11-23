// Kişi 1 - Uçuş Kontrol FSM
module flight_fsm (
    input  wire       clk,
    input  wire       rst,
    input  wire       cmd_exec,
    input  wire [7:0] cmd_in,
    output reg        flight_ok
);

    localparam [2:0]
        DISARMED = 3'd0,
        ARMED    = 3'd1,
        FLIGHT   = 3'd2,
        LANDING  = 3'd3,
        FAILSAFE = 3'd4;

    reg [2:0] state;
    reg [2:0] next_state;

    // Durum register'ı (senkron aktif-yüksek reset; sadece cmd_exec == 1 iken geçiş yapar)
    always @(posedge clk) begin
        if (rst) begin
            state <= DISARMED;
        end else if (cmd_exec) begin
            state <= next_state;
        end
    end

    // Kombinasyonel geçiş ve flight_ok mantığı
    always @(*) begin
        next_state = state;
        flight_ok  = 1'b0;

        case (state)
            DISARMED: begin
                if (cmd_in == "A") begin
                    flight_ok  = 1'b1;
                    next_state = ARMED;
                end
            end

            ARMED: begin
                if (cmd_in == "D") begin
                    flight_ok  = 1'b1;
                    next_state = DISARMED;
                end else if (cmd_in == "T") begin
                    flight_ok  = 1'b1;
                    next_state = FLIGHT;
                end
            end

            FLIGHT: begin
                if (cmd_in == "L") begin
                    flight_ok  = 1'b1;
                    next_state = LANDING;
                end else if (cmd_in == "F") begin
                    flight_ok  = 1'b1;
                    next_state = FAILSAFE;
                end
            end

            LANDING: begin
                if (cmd_in == "D") begin
                    flight_ok  = 1'b1;
                    next_state = DISARMED;
                end else if (cmd_in == "F") begin
                    flight_ok  = 1'b1;
                    next_state = FAILSAFE;
                end
            end

            FAILSAFE: begin
                if (cmd_in == "D" || cmd_in == "R") begin
                    flight_ok  = 1'b1;
                    next_state = DISARMED;
                end
            end

            default: begin
                flight_ok  = 1'b0;
                next_state = DISARMED;
            end
        endcase
    end

endmodule
