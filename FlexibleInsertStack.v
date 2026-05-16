/*
 * Module FlexibleInsertStack
 * --------------------------
 * A stack with four commands:
 *   HOLD         : No change to stored data/state.
 *   INSERT_END   : Insert DataIn at the first available empty slot (leftmost free).
 *   INSERT_FRONT : Push DataIn to the top (leftmost) and shift existing entries right.
 *   POP          : Remove top entry (leftmost) and shift remaining entries left.
 *
 * Representation:
 *   - Storage is flattened as Q[N*W-1:0].
 *   - "Top" of stack is the leftmost word: Q[(N-1)*W +: W].
 *   - Enables is a one-hot marker shifted right as entries are added;
 *     Enables[N-1]=1 means the stack is empty.
 */

`timescale 1ps/1ps

// Command encodings.
`define HOLD         2'b00
`define INSERT_END   2'b01
`define INSERT_FRONT 2'b10
`define POP          2'b11

// Special symbol used for cleared entries.
`define Blank        8'b00000000
`define DOT          8'h2e

module FlexibleInsertStack #(
    parameter N = 32, // Number of entries in the stack.
    parameter W = 8   // Bit-width of each entry.
) (
    input  wire           clk,    // Clock input.
    input  wire           Reset,  // Active-high asynchronous reset.
    input  wire [1:0]     CMD,    // Operation selector.
    input  wire [W-1:0]   DataIn, // New symbol/data to insert.
    output wire           Empty,  // 1 when stack has no valid elements.
    output reg            Full,   // 1 when stack cannot accept more inserts.
    output reg  [W-1:0]   Top,    // Current top element (leftmost word).
    output wire [N*W-1:0] QView   // Full stack contents for observation/debug.
);

    // Current-state storage of all stack words (flattened).
    reg [N*W-1:0] Q;
    // Next-state version computed in combinational logic.
    reg [N*W-1:0] QNext;

    // Current and next-state one-hot empty-slot marker.
    // Enables[N-1]=1 → stack empty; Enables[0]=1 → one slot left before full.
    reg [N-1:0] Enables, EnablesNext;

    // Next-state value for Full flag.
    reg FullNext;

    // Loop index for word-by-word operations.
    integer i;

    // Empty is derived from marker position.
    assign Empty  = Enables[N-1];
    // Expose internal storage for waveform/debug visibility.
    assign QView  = Q;

    // -----------------------------------------------------------------------
    // Combinational Next-State Logic
    // -----------------------------------------------------------------------
    always @(*) begin
        // Top always reflects the leftmost (highest-index) word.
        Top = Q[(N-1)*W +: W];

        // Default: hold current state.
        QNext       = Q;
        EnablesNext = Enables;
        FullNext    = Full;

        case (CMD)
            // ------------------------------------------------------------------
            // HOLD: no change (defaults already applied above).
            // ------------------------------------------------------------------
            `HOLD: begin
                // Nothing to do.
            end

            // ------------------------------------------------------------------
            // INSERT_FRONT: push DataIn at the top; shift everything right by 1.
            //   Before: [A, B, C, _, _, ...]   (A is top)
            //   After:  [D, A, B, C, _, ...]   (D is new top)
            // ------------------------------------------------------------------
            `INSERT_FRONT: begin
                if (!Full) begin
                    // Shift all existing words one position to the right
                    // (from index N-2 down to 0, moving word[i+1] <- word[i]).
                    for (i = N-2; i >= 0; i = i - 1)
                        QNext[i*W +: W] = Q[(i+1)*W +: W];
                    // Place DataIn at the top (leftmost = index N-1).
                    QNext[(N-1)*W +: W] = DataIn;

                    // Advance Enables one position to the right (shift right by 1).
                    EnablesNext = Enables >> 1;

                    // If Enables was already at bit 0, the stack is now full.
                    FullNext = Enables[0];
                end
            end

            // ------------------------------------------------------------------
            // INSERT_END: place DataIn at the first empty slot (rightmost used + 1).
            //   Enables[k]=1 means slot k is the next free slot.
            //   The physical slot index in Q is (N-1) - (position from left of Enables).
            //
            //   Example N=4: Enables = 4'b0010 means slot index 1 is free.
            //   Before: [A, B, _, _]   (A at index 3, B at index 2)
            //   After : [A, B, C, _]   (C inserted at index 1)
            // ------------------------------------------------------------------
            `INSERT_END: begin
                if (!Full) begin
                    // Find the one-hot position in Enables and write DataIn there.
                    for (i = 0; i < N; i = i + 1) begin
                        if (Enables[i]) begin
                            QNext[i*W +: W] = DataIn;
                        end
                    end
                    // Advance Enables one position to the right (shift right by 1).
                    EnablesNext = Enables >> 1;

                    // Stack becomes full when Enables had only bit 0 set.
                    FullNext = Enables[0];
                end
            end

            // ------------------------------------------------------------------
            // POP: remove top; shift remaining entries left by one word.
            //   Before: [A, B, C, _, ...]
            //   After:  [B, C, _, _, ...]   (A removed, blank inserted at right end)
            // ------------------------------------------------------------------
            `POP: begin
                if (!Empty) begin
                    // Shift all words one position to the left
                    // (from index N-1 down to 1, moving word[i] <- word[i-1]).
                    for (i = N-1; i >= 1; i = i - 1)
                        QNext[i*W +: W] = Q[(i-1)*W +: W];
                    // Vacated rightmost slot gets a blank.
                    QNext[0*W +: W] = `Blank;

                    // Compute new Enables position.
                    if (Full) begin
                        // Full means Enables was all zeros (no free slot marker).
                        // After popping, exactly one slot (bit 0) is free.
                        EnablesNext = {{N-1{1'b0}}, 1'b1};
                    end else begin
                        // Normal case: shift the one-hot marker left by 1.
                        EnablesNext = (Enables << 1);
                        // Edge case: if Enables was at MSB (last element),
                        // shifting left overflows to 0 — force MSB to signal empty.
                        if (EnablesNext == {N{1'b0}})
                            EnablesNext[N-1] = 1'b1;
                    end

                    // Pop always frees a slot → Full can never be true afterward.
                    FullNext = 1'b0;
                end
            end

            default: begin
                // Treat as HOLD (safe fallback).
            end
        endcase
    end

    // -----------------------------------------------------------------------
    // Sequential State Registers
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge Reset) begin
        if (Reset) begin
            Q       <= {N{`Blank}};
            Enables <= {1'b1, {N-1{1'b0}}};  // All slots empty; top marker at MSB.
            Full    <= 1'b0;
        end else begin
            Q       <= QNext;
            Enables <= EnablesNext;
            Full    <= FullNext;
        end
    end

endmodule // FlexibleInsertStack
