// Operator symbols are +, -, ! (unary minus), /
// Precedences are (high to low): !, ^, /, *, (+, -)
// Operands are assumed to be single symbols.

`include "FlexibleInsertStack.v"

// Commands sent to each stack instance.
`define HOLD         2'b00
`define INSERT_END   2'b01
`define INSERT_FRONT 2'b10
`define POP          2'b11

/*
 * Stack command semantics:
 * - HOLD:         Keep stack contents unchanged.
 * - INSERT_END:   Insert at first available empty slot from the left.
 * - INSERT_FRONT: Insert at top (leftmost) and shift older entries right.
 * - POP:          Remove top (leftmost) and shift remaining entries left.
 */

// Controller states.
`define IDLE     2'b00
`define READ     2'b01
`define GETTOKEN 2'b10
`define DONE     2'b11

// Token categories / special symbols.
`define DOT_CHAR     8'h2e   // '.'
`define LEFT_PARENS  8'h28   // '('
`define RIGHT_PARENS 8'h29   // ')'
`define SPACE_CHAR   8'h20   // ' '

module Infix2Postfix #(
    parameter N = 32,  // Maximum number of input/output symbols buffered in stacks.
    parameter W = 8    // Symbol width (ASCII byte).
) (
    input               clk,         // System clock.
    input               ST,          // Start signal from testbench/controller.
    input               Reset,       // Active-high asynchronous reset.
    input  [W-1:0]      InputSymbol, // Streamed infix symbol input (one char per cycle in READ).
    output [N*W-1:0]    Result,      // Full postfix buffer exposed from ResultStack.
    output reg          Ready        // High when converter is idle/finished.
);

    // -------------------------------------------------------------------------
    // Stack status wires
    // -------------------------------------------------------------------------
    wire                InfixExpStackEmpty;
    wire                ResultStackEmpty;
    wire                OperatorStackEmpty;

    wire                InfixExpFull;
    wire                ResultStackFull;
    wire                OperatorStackFull;

    // -------------------------------------------------------------------------
    // Shared DataIn bus — only stacks with INSERT_* commands consume this.
    // -------------------------------------------------------------------------
    reg [W-1:0]         SymbolToInsert;

    // -------------------------------------------------------------------------
    // Top symbol from each stack
    // -------------------------------------------------------------------------
    wire [W-1:0]        InfixExpStack_Top;
    wire [W-1:0]        ResultStack_Top;
    wire [W-1:0]        OperatorStack_Top;

    // Full content of ResultStack (connected to module output).
    wire [N*W-1:0]      ResultStack_Q;

    // -------------------------------------------------------------------------
    // Per-stack command registers
    // -------------------------------------------------------------------------
    reg [1:0]           InfixExpStack_CMD;
    reg [1:0]           ResultStack_CMD;
    reg [1:0]           OperatorStack_CMD;

    // -------------------------------------------------------------------------
    // FSM state registers
    // -------------------------------------------------------------------------
    reg [1:0]           State;
    reg [1:0]           NextState;

    // -------------------------------------------------------------------------
    // Precedence helper
    // Returns higher integers for higher-precedence operators:
    //   "!" -> 4  (unary minus / highest)
    //   "^" -> 3  (exponentiation)
    //   "*","/" -> 2
    //   "+","-" -> 1
    //   anything else (including "(" ) -> 0
    // -------------------------------------------------------------------------
    function integer Precedence(input [W-1:0] Symbol);
        begin
            case (Symbol)
                8'h21:    Precedence = 4;  // '!'
                8'h5e:    Precedence = 3;  // '^'
                8'h2a:    Precedence = 2;  // '*'
                8'h2f:    Precedence = 2;  // '/'
                8'h2b:    Precedence = 1;  // '+'
                8'h2d:    Precedence = 1;  // '-'
                default:  Precedence = 0;
            endcase
        end
    endfunction

    // Helper: returns 1 if Symbol is an operator character.
    function IsOperator(input [W-1:0] Symbol);
        begin
            case (Symbol)
                8'h21, 8'h5e, 8'h2a, 8'h2f, 8'h2b, 8'h2d: IsOperator = 1'b1;
                default: IsOperator = 1'b0;
            endcase
        end
    endfunction

    // Helper: returns 1 if Symbol is an operand (alphanumeric digit).
    function IsOperand(input [W-1:0] Symbol);
        begin
            // Digits 0-9 (0x30-0x39) and letters a-i (0x61-0x69)
            if ((Symbol >= 8'h30 && Symbol <= 8'h39) ||
                (Symbol >= 8'h61 && Symbol <= 8'h69) ||
                (Symbol >= 8'h41 && Symbol <= 8'h5a))
                IsOperand = 1'b1;
            else
                IsOperand = 1'b0;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Wire Result to ResultStack's full content view
    // -------------------------------------------------------------------------
    assign Result = ResultStack_Q;

    // -------------------------------------------------------------------------
    // Stack instances
    // -------------------------------------------------------------------------
    FlexibleInsertStack #(.N(N), .W(W)) InfixExpStack (
        .clk    (clk),
        .Reset  (Reset),
        .CMD    (InfixExpStack_CMD),
        .DataIn (SymbolToInsert),
        .Empty  (InfixExpStackEmpty),
        .Full   (InfixExpFull),
        .Top    (InfixExpStack_Top),
        .QView  ()
    );

    FlexibleInsertStack #(.N(N), .W(W)) ResultStack (
        .clk    (clk),
        .Reset  (Reset),
        .CMD    (ResultStack_CMD),
        .DataIn (SymbolToInsert),
        .Empty  (ResultStackEmpty),
        .Full   (ResultStackFull),
        .Top    (ResultStack_Top),
        .QView  (ResultStack_Q)
    );

    FlexibleInsertStack #(.N(N), .W(W)) OperatorStack (
        .clk    (clk),
        .Reset  (Reset),
        .CMD    (OperatorStack_CMD),
        .DataIn (SymbolToInsert),
        .Empty  (OperatorStackEmpty),
        .Full   (OperatorStackFull),
        .Top    (OperatorStack_Top),
        .QView  ()
    );

    // -------------------------------------------------------------------------
    // Sequential State Register
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge Reset) begin
        if (Reset)
            State <= `IDLE;
        else
            State <= NextState;
    end

    // -------------------------------------------------------------------------
    // Combinational Controller
    // -------------------------------------------------------------------------
    always @(*) begin
        // Safe defaults: no latch risk, no accidental inserts.
        Ready             = 1'b0;
        NextState         = State;
        SymbolToInsert    = InputSymbol;
        InfixExpStack_CMD = `HOLD;
        OperatorStack_CMD = `HOLD;
        ResultStack_CMD   = `HOLD;

        case (State)

            // -----------------------------------------------------------------
            // IDLE: converter ready. Wait for ST to kick off READ.
            // -----------------------------------------------------------------
            `IDLE: begin
                Ready = 1'b1;
                if (ST)
                    NextState = `READ;
                // else stay in IDLE
            end

            // -----------------------------------------------------------------
            // READ: consume input symbols and load them into InfixExpStack
            //       (right-to-left order; DOT marks end of expression).
            //
            // We insert EVERY symbol including DOT so the GETTOKEN stage can
            // pop it off and detect end-of-expression.
            // -----------------------------------------------------------------
            `READ: begin
                Ready          = 1'b0;
                SymbolToInsert = InputSymbol;

                // Always insert the current symbol at the end of InfixExpStack.
                InfixExpStack_CMD = `INSERT_END;

                // When DOT is seen, switch to processing.
                if (InputSymbol == `DOT_CHAR)
                    NextState = `GETTOKEN;
                // else stay in READ
            end

            // -----------------------------------------------------------------
            // GETTOKEN: core infix-to-postfix logic.
            // Each cycle, inspect InfixExpStack_Top and route that token.
            // -----------------------------------------------------------------
            `GETTOKEN: begin
                Ready = 1'b0;

                if (InfixExpStackEmpty) begin
                    // Expression fully consumed, move to DONE.
                    NextState = `DONE;
                end else begin

                    if (InfixExpStack_Top == `DOT_CHAR) begin
                        // ---------------------------------------------------------
                        // DOT encountered: flush remaining operators then finish.
                        // ---------------------------------------------------------
                        if (OperatorStackEmpty) begin
                            // Discard DOT and we're done.
                            InfixExpStack_CMD = `POP;
                            NextState         = `DONE;
                        end else begin
                            // Flush one operator per cycle from OperatorStack to Result.
                            SymbolToInsert    = OperatorStack_Top;
                            OperatorStack_CMD = `POP;
                            ResultStack_CMD   = `INSERT_END;
                        end

                    end else if (InfixExpStack_Top == `SPACE_CHAR) begin
                        // ---------------------------------------------------------
                        // SPACE: discard/skip token.
                        // ---------------------------------------------------------
                        InfixExpStack_CMD = `POP;

                    end else if (InfixExpStack_Top == `LEFT_PARENS) begin
                        // ---------------------------------------------------------
                        // LEFT PARENTHESIS: push "(" onto OperatorStack.
                        // ---------------------------------------------------------
                        SymbolToInsert    = InfixExpStack_Top;
                        InfixExpStack_CMD = `POP;
                        OperatorStack_CMD = `INSERT_FRONT;

                    end else if (InfixExpStack_Top == `RIGHT_PARENS) begin
                        // ---------------------------------------------------------
                        // RIGHT PARENTHESIS:
                        //   - If OperatorStack top is "(": discard both parens.
                        //   - Else: flush one operator per cycle into ResultStack.
                        // ---------------------------------------------------------
                        if (OperatorStack_Top == `LEFT_PARENS) begin
                            // Discard the ")" from infix stack.
                            InfixExpStack_CMD = `POP;
                            // Discard the matching "(" from operator stack.
                            OperatorStack_CMD = `POP;
                        end else begin
                            // Flush one operator to result (do NOT pop ")" yet).
                            SymbolToInsert    = OperatorStack_Top;
                            OperatorStack_CMD = `POP;
                            ResultStack_CMD   = `INSERT_END;
                        end

                    end else if (IsOperator(InfixExpStack_Top)) begin
                        // ---------------------------------------------------------
                        // OPERATOR: standard shunting-yard logic.
                        //   Push if:
                        //     - OperatorStack is empty, OR
                        //     - Top of OperatorStack is "(", OR
                        //     - Current operator has STRICTLY HIGHER precedence.
                        //   Else flush one operator from OperatorStack to Result.
                        // ---------------------------------------------------------
                        if (OperatorStackEmpty ||
                            (OperatorStack_Top == `LEFT_PARENS) ||
                            (Precedence(InfixExpStack_Top) > Precedence(OperatorStack_Top)))
                        begin
                            // Push current operator onto OperatorStack.
                            SymbolToInsert    = InfixExpStack_Top;
                            InfixExpStack_CMD = `POP;
                            OperatorStack_CMD = `INSERT_FRONT;
                        end else begin
                            // Flush one higher/equal-precedence operator to Result.
                            SymbolToInsert    = OperatorStack_Top;
                            OperatorStack_CMD = `POP;
                            ResultStack_CMD   = `INSERT_END;
                        end

                    end else if (IsOperand(InfixExpStack_Top)) begin
                        // ---------------------------------------------------------
                        // OPERAND: move directly from InfixExpStack to ResultStack.
                        // ---------------------------------------------------------
                        SymbolToInsert    = InfixExpStack_Top;
                        InfixExpStack_CMD = `POP;
                        ResultStack_CMD   = `INSERT_END;

                    end else begin
                        // Unknown token — skip it safely.
                        InfixExpStack_CMD = `POP;
                    end
                end
            end

            // -----------------------------------------------------------------
            // DONE: assert Ready, then return to IDLE.
            // -----------------------------------------------------------------
            `DONE: begin
                Ready     = 1'b1;
                NextState = `IDLE;
            end

            default: begin
                // Force IDLE on unexpected state.
                NextState = `IDLE;
            end

        endcase
    end

endmodule
