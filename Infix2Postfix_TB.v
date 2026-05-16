`include "Infix2Postfix.v"

/*
 * Infix2Postfix_TB
 * ----------------
 * This testbench is a directed regression suite with PASS/FAIL checks.
 * The text log is intentionally concise: one line per testcase with
 * cycle, infix expression, simulated postfix, expected postfix, and status.
 *
 * Generated trace file:
 *   Infix2Postfix_sim.txt
 */
module Infix2Postfix_TB #(
    parameter N = 32,
    parameter W = 8
);

    /*
     * DUT stimulus/control signals.
     * - clk: simulation clock
     * - ST: start pulse for conversion
     * - Reset: async reset for DUT
     * - InputSymbol: streamed token input (one character at a time)
     */
    reg             clk;
    reg             ST;
    reg             Reset;
    reg [W-1:0]     InputSymbol;

    /*
     * DUT output signals.
     * - Result carries the full postfix buffer from the DUT.
     * - Ready indicates FSM idle/completion state.
     */
    wire [N*W-1:0]  Result;
    wire            Ready;

    // Bookkeeping counters for regression summary.
    integer         cycle = 0;
    integer         pass_count = 0;
    integer         fail_count = 0;

    // File descriptor for simulation text log.
    integer         fd = 0;

    // Device Under Test (DUT).
    Infix2Postfix #(.N(N), .W(W)) SimpleCalc (
        .clk        (clk),
        .ST         (ST),
        .Reset      (Reset),
        .InputSymbol(InputSymbol),
        .Result     (Result),
        .Ready      (Ready)
    );

    // 2-time-unit clock period.
    always begin
        #1 clk = ~clk;
        if (clk)
            cycle = cycle + 1;
    end

    /*
     * reset_dut
     * ---------
     * Applies a clean reset sequence and initializes external stimulus signals.
     */
    task automatic reset_dut;
        begin
            ST = 1'b0;
            InputSymbol = {W{1'b0}};
            Reset = 1'b1;

            @(negedge clk);
            @(negedge clk);

            Reset = 1'b0;
        end
    endtask

    /*
     * feed_expression
     * ---------------
     * Streams one expression into InputSymbol, one character per negative edge,
     * until DOT is seen.
     */
    task automatic feed_expression;
        input [N*W-1:0] infix_expr;
        integer idx;
        reg eos_local;
        begin
            ST = 1'b1;
            eos_local = 1'b0;

            for (idx = N - 1; ((idx >= 0) && (!eos_local)); idx = idx - 1) begin
                @(negedge clk);
                InputSymbol = infix_expr[idx*W +: W];
                if (InputSymbol == `DOT) begin
                    eos_local = 1'b1;
                    @(negedge clk);
                end
            end

            ST = 1'b0;
        end
    endtask

    /*
     * build_expected_q
     * ----------------
     * Converts a short expected postfix string into the top-aligned format used
     * by ResultStack.Q (left-packed characters with remaining bytes don't-care).
     */
    task automatic build_expected_q;
        input  [N*W-1:0] expected_short;
        input  integer   expected_len;
        output [N*W-1:0] expected_q;
        integer k;
        begin
            expected_q = {N*W{1'b0}};
            for (k = 0; k < expected_len; k = k + 1) begin
                expected_q[(N-k)*W-1 -: W] = expected_short[(expected_len-k)*W-1 -: W];
            end
        end
    endtask

    /*
     * run_case
     * --------
     * Executes one full testcase and checks DUT Result output against the
     * expected postfix buffer.
     */
    task automatic run_case;
        input [8*64-1:0] case_name;
        input [N*W-1:0]  infix_expr;
        input [N*W-1:0]  expected_postfix_short;
        input integer    expected_len;

        reg   [N*W-1:0]  expected_q;
        integer          case_cycle;
        begin
            reset_dut();

            wait (Ready == 1'b1);
            @(negedge clk);

            feed_expression(infix_expr);

            @(negedge clk);
            wait (Ready == 1'b1);
            case_cycle = cycle;

            build_expected_q(expected_postfix_short, expected_len, expected_q);

            if (Result === expected_q) begin
                pass_count = pass_count + 1;
                $display("PASS [%0s] Infix=%s Postfix=%s", case_name, infix_expr, Result);
                if (fd != 0)
                    $fdisplay(fd, "cycle=%0d | infix=%s | simulated=%s | expected=%s | PASS",
                        case_cycle, infix_expr, Result, expected_q);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL [%0s]", case_name);
                $display("  Infix    = %s", infix_expr);
                $display("  Expected = %s", expected_q);
                $display("  Actual   = %s", Result);

                if (fd != 0) begin
                    $fdisplay(fd, "cycle=%0d | infix=%s | simulated=%s | expected=%s | FAIL",
                        case_cycle, infix_expr, Result, expected_q);
                end
            end
        end
    endtask

    initial begin
        // Open simulation log file.
        fd = $fopen("Infix2Postfix_sim.txt", "w");
        if (fd == 0) begin
            $display("ERROR: could not open Infix2Postfix_sim.txt for writing.");
            $finish;
        end

        $display("Simulation log file: Infix2Postfix_sim.txt");
        $fdisplay(fd, "cycle | infix | simulated_postfix | expected_postfix | status");

        // Initialize external stimulus.
        clk = 1'b0;
        ST = 1'b0;
        Reset = 1'b0;
        InputSymbol = {W{1'b0}};

        // Curated regression set.
        run_case("simple-add",        "3+2.                            ", "32+", 3);
        run_case("space-handling",    "3 +2.                           ", "32+", 3);
        run_case("precedence-parens", "9+8*(7-2).                      ", "9872-*+", 7);
        run_case("single-symbol",     "a+b.                            ", "ab+", 3);
        run_case("single-operand",    "a.                              ", "a", 1);
        run_case("unary-operator",    "!2+3*!5.                        ", "2!35!*+", 7);
        run_case("complex-nested",    "(a*b+c*(d*(e-f+g)+h)).          ", "ab*cdef-g+*h+*+", 15);
        run_case("dot-only",          ".                               ", "", 0);

        // Summary.
        $display("\n==================== TEST SUMMARY ====================");
        $display("Total PASS = %0d", pass_count);
        $display("Total FAIL = %0d", fail_count);
        $display("======================================================");

        if (fail_count == 0) begin
            $display("All Infix2Postfix testcases PASSED.");
        end else begin
            $display("One or more Infix2Postfix testcases FAILED.");
        end

        // Close file and end simulation.
        $fclose(fd);
        fd = 0;
        $finish;
    end

endmodule
