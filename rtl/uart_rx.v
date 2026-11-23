module uart_rx (
    input wire clk,
    input wire rst,
    input wire rx,
    input wire tick16,

    output reg [7:0] rx_data,
    output reg rx_valid,
    output reg rx_err
);

    // =====================================
    // 1. FSM STATE DEFINITIONS
    // =====================================

    localparam IDLE     = 3'b000;
    localparam START    = 3'b001;
    localparam DATA     = 3'b010;
    localparam PARITY   = 3'b011;
    localparam STOP     = 3'b100;
    localparam DONE_OK  = 3'b101;
    localparam DONE_ERR = 3'b110;

    reg [2:0] state;

    // Internal counters and registers
    reg [3:0] tick_count;
    reg [2:0] bit_index;
    reg parity_err;


    // =====================================
    // 2. SEQUENTIAL FSM
    // =====================================

    always @(posedge clk) begin

        // Active-high synchronous reset
        if (rst == 1'b1) begin

            state      <= IDLE;
            tick_count <= 4'd0;
            bit_index  <= 3'd0;
            rx_data    <= 8'd0;
            parity_err <= 1'b0;

        end

        else begin

            case (state)

                // =================================
                // IDLE STATE
                // =================================

                IDLE: begin

                    tick_count <= 4'd0;

                    if (rx == 1'b0) begin
                        state <= START;
                    end

                    else begin
                        state <= IDLE;
                    end

                end


                // =================================
                // START STATE
                // =================================

                START: begin

                    if (tick16) begin

                        if (tick_count == 4'd7) begin

                            tick_count <= 4'd0;

                            if (rx == 1'b0) begin

                                state      <= DATA;
                                bit_index  <= 3'd0;
                                rx_data    <= 8'd0;
                                parity_err <= 1'b0;

                            end

                            else begin
                                state <= IDLE;
                            end

                        end

                        else begin
                            tick_count <= tick_count + 1'b1;
                        end

                    end

                end


                // =================================
                // DATA STATE
                // =================================

                DATA: begin

                    if (tick16) begin

                        if (tick_count == 4'd15) begin

                            tick_count <= 4'd0;

                            // Shift received bit into register
                            rx_data <= {rx, rx_data[7:1]};

                            if (bit_index == 3'd7) begin

                                state <= PARITY;

                            end

                            else begin

                                bit_index <= bit_index + 1'b1;
                                state <= DATA;

                            end

                        end

                        else begin
                            tick_count <= tick_count + 1'b1;
                        end

                    end

                end


                // =================================
                // PARITY STATE
                // =================================

                PARITY: begin

                    if (tick16) begin

                        if (tick_count == 4'd15) begin

                            tick_count <= 4'd0;

                            // EVEN PARITY CHECK
                            parity_err <= rx ^ (^rx_data);

                            state <= STOP;

                        end

                        else begin
                            tick_count <= tick_count + 1'b1;
                        end

                    end

                end


                // =================================
                // STOP STATE
                // =================================

                STOP: begin

                    if (tick16) begin

                        if (tick_count == 4'd15) begin

                            tick_count <= 4'd0;

                            if ((rx == 1'b1) &&
                                (parity_err == 1'b0)) begin

                                state <= DONE_OK;

                            end

                            else begin

                                state <= DONE_ERR;

                            end

                        end

                        else begin
                            tick_count <= tick_count + 1'b1;
                        end

                    end

                end


                // =================================
                // DONE_OK STATE
                // =================================

                DONE_OK: begin

                    state <= IDLE;
                    tick_count <= 4'd0;

                end


                // =================================
                // DONE_ERR STATE
                // =================================

                DONE_ERR: begin

                    state <= IDLE;
                    tick_count <= 4'd0;

                end


                // =================================
                // DEFAULT
                // =================================

                default: begin

                    state      <= IDLE;
                    tick_count <= 4'd0;
                    bit_index  <= 3'd0;
                    parity_err <= 1'b0;

                end

            endcase

        end

    end


    // =====================================
    // 3. MOORE OUTPUT LOGIC
    // =====================================

    always @(*) begin

        // Default outputs
        rx_valid = 1'b0;
        rx_err   = 1'b0;

        case (state)

            IDLE: begin
                rx_valid = 1'b0;
                rx_err   = 1'b0;
            end

            START: begin
                rx_valid = 1'b0;
                rx_err   = 1'b0;
            end

            DATA: begin
                rx_valid = 1'b0;
                rx_err   = 1'b0;
            end

            PARITY: begin
                rx_valid = 1'b0;
                rx_err   = 1'b0;
            end

            STOP: begin
                rx_valid = 1'b0;
                rx_err   = 1'b0;
            end

            DONE_OK: begin
                rx_valid = 1'b1;
                rx_err   = 1'b0;
            end

            DONE_ERR: begin
                rx_valid = 1'b0;
                rx_err   = 1'b1;
            end

            default: begin
                rx_valid = 1'b0;
                rx_err   = 1'b0;
            end

        endcase

    end

endmodule
