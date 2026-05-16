// ============================================================
//  PolyN.v  —  nth-degree polynomial evaluator
//  Method : Horner's rule   f(x) = ((...(aₙ·x + aₙ₋₁)·x + ...)·x + a₀
//  Interface:
//    clk, reset  — clock and synchronous reset
//    st          — start pulse (high on first cycle)
//    Data        — serial input: n, then aₙ down to a₀
//    x           — value at which polynomial is evaluated
//    READY       — high when idle / result valid
//    fn_x        — output result
//
//  Structure: 3-segment style
//    Segment 1 — state register
//    Segment 2 — next-state logic
//    Segment 3 — output / datapath logic
// ============================================================

// ------------------------------------------------------------
// MAC module:  z = a * x + b
// ------------------------------------------------------------
module MAC #(parameter N = 16)(
    input  signed [N-1:0] a,
    input  signed [N-1:0] x,
    input  signed [N-1:0] b,
    output signed [N-1:0] z
);
    assign z = a * x + b;
endmodule


// ------------------------------------------------------------
// PolyN top-level module
// ------------------------------------------------------------
module PolyN #(parameter N = 16)(
    input                  clk,
    input                  reset,
    input                  st,
    input  signed [N-1:0]  Data,   // n, then aₙ, aₙ₋₁ ... a₀
    input  signed [N-1:0]  x,
    output reg             READY,
    output reg signed [N-1:0] fn_x
);

    // ---------------------------------------------------------
    // State encoding
    // ---------------------------------------------------------
    localparam IDLE       = 3'd0,
               LOAD_N     = 3'd1,
               LOAD_COEFF = 3'd2,
               CHECK      = 3'd3,
               COMPUTE    = 3'd4,
               DONE       = 3'd5;

    // ---------------------------------------------------------
    // Registers
    // ---------------------------------------------------------
    reg [2:0]              state, next_state;
    reg signed [N-1:0]     n_reg;   // stores degree n
    reg signed [N-1:0]     i;       // loop counter
    reg signed [N-1:0]     acc;     // accumulator

    // ---------------------------------------------------------
    // MAC wiring
    // ---------------------------------------------------------
    wire signed [N-1:0]    mac_out;

    MAC #(N) mac_unit (
        .a  (acc),
        .x  (x),
        .b  (Data),     // current coefficient aᵢ fed in via Data
        .z  (mac_out)
    );

    // ---------------------------------------------------------
    // Status signal
    // ---------------------------------------------------------
    wire i_lt_zero = (i < 0);

    // =========================================================
    // SEGMENT 1 — State Register
    // =========================================================
    always @(posedge clk) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    // =========================================================
    // SEGMENT 2 — Next-State Logic
    // =========================================================
    always @(*) begin
        next_state = state;   // default: stay
        case (state)
            IDLE       : next_state = st        ? LOAD_N     : IDLE;
            LOAD_N     : next_state =               LOAD_COEFF;
            LOAD_COEFF : next_state =               CHECK;
            CHECK      : next_state = i_lt_zero ? DONE       : COMPUTE;
            COMPUTE    : next_state =               CHECK;
            DONE       : next_state =               IDLE;
            default    : next_state =               IDLE;
        endcase
    end

    // =========================================================
    // SEGMENT 3 — Output & Datapath Logic
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            READY  <= 1'b1;
            fn_x   <= 0;
            n_reg  <= 0;
            i      <= 0;
            acc    <= 0;
        end
        else begin
            // Default outputs
            READY <= 1'b0;

            case (state)

                // ------------------------------------------
                IDLE: begin
                    READY <= 1'b1;    // signal ready
                end

                // ------------------------------------------
                // Read degree n from Data
                LOAD_N: begin
                    n_reg <= Data;
                end

                // ------------------------------------------
                // Read leading coefficient aₙ into acc
                // Set counter i = n - 1
                LOAD_COEFF: begin
                    acc <= Data;
                    i   <= n_reg - 1;
                end

                // ------------------------------------------
                // CHECK state — no datapath action,
                // just evaluate i_lt_zero (combinational)
                CHECK: begin
                    // nothing — next-state logic handles branching
                end

                // ------------------------------------------
                // Horner step: acc = acc*x + aᵢ  (via MAC)
                // Decrement counter
                COMPUTE: begin
                    acc <= mac_out;   // MAC(acc, x, Data) = acc*x + Data
                    i   <= i - 1;
                end

                // ------------------------------------------
                // Latch result, assert READY
                DONE: begin
                    fn_x  <= acc;
                    READY <= 1'b1;
                end

            endcase
        end
    end

endmodule


// ============================================================
// Testbench — verifies f(x) = 2x² + 3x + 4  at x = 2
//   Horner:  ((2)*2 + 3)*2 + 4 = 18
//   Input sequence on Data:  n=2, a2=2, a1=3, a0=4
// ============================================================
module tb_PolyN;
    parameter N = 16;

    reg                  clk, reset, st;
    reg  signed [N-1:0]  Data, x;
    wire                 READY;
    wire signed [N-1:0]  fn_x;

    PolyN #(N) dut (
        .clk(clk), .reset(reset), .st(st),
        .Data(Data), .x(x),
        .READY(READY), .fn_x(fn_x)
    );

    // 10 ns clock
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("PolyN.vcd");
        $dumpvars(0, tb_PolyN);

        // Reset
        reset = 1; st = 0; Data = 0; x = 2;
        @(posedge clk); #1;
        reset = 0;

        // Cycle 1: assert st, send n = 2
        @(posedge clk); #1;
        st = 1; Data = 2;   // n = 2

        // Cycle 2: send a2 = 2  (leading coefficient)
        @(posedge clk); #1;
        st = 0; Data = 2;   // a2

        // Cycle 3: send a1 = 3
        @(posedge clk); #1;
        Data = 3;            // a1

        // Cycle 4: send a0 = 4
        @(posedge clk); #1;
        Data = 4;            // a0

        // Wait for READY
        repeat(10) @(posedge clk);

        $display("f(2) = %0d  (expected 18)", fn_x);

        if (fn_x === 18)
            $display("PASS");
        else
            $display("FAIL — got %0d", fn_x);

        $finish;
    end
endmodule
