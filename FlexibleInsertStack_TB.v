`include "FlexibleInsertStack.v"

/* 
 * Testbench for FlexibleInsertStack
 * Purpose: Verifies all 4 commands (HOLD, INSERT_END, INSERT_FRONT, POP),
 *          as well as edge cases like underflow (popping when empty) and 
 *          overflow (inserting when full).
 */
module FlexibleInsertStack_TB #(
    // Standard size of the stack
    parameter N = 32,  
    parameter W = 8
);

    // Inputs to the module under test
    reg              clk;
    reg              Reset;
    reg [1:0]        CMD;
    reg [W-1:0]      DataIn;
    
    // Outputs from the module under test
    wire [W-1:0]     Top;
    wire             Empty;
    wire             Full;
    wire [N*W-1:0]   QView;

    // Simulation tracking variables
    integer cycle = 0;
    integer j;
    integer fd; // Changed from `integer f` due to iverilog descriptor bugs
         
    // Instantiate the module
    FlexibleInsertStack #(
        .N(N), 
        .W(W)
    ) FlexibleInsertStack8 (
        .clk(clk), 
        .Reset(Reset), 
        .CMD(CMD),
        .DataIn(DataIn),  
        .Empty(Empty), 
        .Full(Full), 
        .Top(Top),
        .QView(QView)
    );

    // The $monitor block will automatically print to the console every time
    // one of the listed variables changes its value.
    // We use $monitor along with log file redirection in bash/powershell or
    // simply write values manually inside the clock loop if raw logging is needed.
    // But since iverilog doesn't support $fmonitor, we will use a loop to $fdisplay manually at each clock.
    initial begin
        fd = $fopen("flexibleinsertstack_sim.txt", "w");
    end

    // Monitor changes every negative edge so data is stable before the next cycle
    always @(negedge clk) begin
        if (fd) begin
            $fdisplay(fd, "time = %2d | cycle = %2d | Reset = %b | CMD = %b | DataIn = %s | Full = %b | Empty = %b | Top = %s | Q = %s",
                     $time, cycle, Reset, CMD, DataIn, Full, Empty, Top, QView);
        end
    end

    // Generate a clock with a period of 2 time units
    always begin
        #1 clk = ~clk;
        if (clk) begin
            cycle = cycle + 1; // Increment cycle counter on rising edge
        end
    end
   
    initial begin
        // Reset the system to a known empty state
        clk = 1'b0;
        Reset = 1'b1;  // Assert reset
        CMD = `HOLD;
        DataIn = `Blank;

        #2 Reset = 1'b0; // De-assert reset before the first negative edge

        // We apply inputs on the negative edge of the clock (@(negedge clk)).
        // This ensures the inputs are stable before the positive edge, mimicking 
        // ideal setup/hold times and preventing race conditions in simulation.

        // 1. Test HOLD when Empty
        // Checks that default 'HOLD' does not corrupt empty state
        $fdisplay(fd, "\n--- Testing: HOLD (Expected: No change, Empty = 1) ---");
        @(negedge clk); CMD = `HOLD;

        // 2. Test INSERT_END into Empty Stack
        // Adds items linearly; they should appear from left to right as the array 'fills'
        $fdisplay(fd, "\n--- Testing: INSERT_END (Expected: Insert A, B, C from the left) ---");
        @(negedge clk); CMD = `INSERT_END; DataIn = "A";
        @(negedge clk); CMD = `INSERT_END; DataIn = "B";
        @(negedge clk); CMD = `INSERT_END; DataIn = "C";

        // 3. Test INSERT_FRONT (Push to top)
        // A standard Stack "Push". Old elements (A,B,C) shift right; new item goes to leftmost slot (Top).
        $fdisplay(fd, "\n--- Testing: INSERT_FRONT (Expected: Insert X at left, A/B/C shift right) ---");
        @(negedge clk); CMD = `INSERT_FRONT; DataIn = "X";
        @(negedge clk); CMD = `INSERT_FRONT; DataIn = "Y";

        // 4. Test HOLD with Data
        // Put a fake DataIn on the wire, but assert HOLD to make sure the stack ignores the data wire.
        $fdisplay(fd, "\n--- Testing: HOLD (Expected: DataIn Z is ignored, stack unchanged) ---");
        @(negedge clk); CMD = `HOLD; DataIn = "Z";
        @(negedge clk);

        // 5. Test POP
        // A standard Stack "Pop". Removes the leftmost element and shifts everything else left.
        $fdisplay(fd, "\n--- Testing: POP (Expected: Top element Y is removed, everything shifts left) ---");
        @(negedge clk); CMD = `POP;
        @(negedge clk); CMD = `POP; // Should pop X too, leaving A at the top

        // 6. Test FULL condition overflow
        // Fill up all N slots to verify 'Full' flag triggers. We currently have 3 items (A, B, C)
        $fdisplay(fd, "\n--- Testing: FILL TO FULL (Expected: Full flag high after inserting N-3 more) ---");
        CMD = `INSERT_END;
        for (j = 0; j < (N - 3); j = j + 1) begin
            @(negedge clk);
            DataIn = 8'h41 + (j % 26); // Just inserts 'A', 'B', 'C'... wrapping around
        end
        $fdisplay(fd, "--- Expect Full=1 Next Cycle ---");
        
        // This insert should automatically be ignored by the design since Full is active.
        @(negedge clk); DataIn = "!"; 

        // 7. Test POPPING until EMPTY
        // Drain the entire array to make sure the Empty flag triggers and data clears.
        $fdisplay(fd, "\n--- Testing: POP UNTIL EMPTY (Expected: Empty flag high after N pops) ---");
        CMD = `POP;
        for (j = 0; j < (N + 1); j = j + 1) begin
            @(negedge clk);
        end

        // 8. Test POP on EMPTY (Underflow check)
        // Ensure no weird array wrap-around happens if we try to pop an empty array.
        $fdisplay(fd, "\n--- Testing: POP ON EMPTY (Expected: Ignored, Empty stays 1) ---");
        @(negedge clk); CMD = `POP;
        
        // Let simulation run one more cycle to observe final state before closing.
        @(negedge clk);
        $fdisplay(fd, "\n--- Simulation Complete ---");
        $fclose(fd);
        fd = 0; // Clear file descriptor to prevent invalid descriptor warnings
        $display("Simulation output generated perfectly to flexibleinsertstack_sim.txt");
        $finish;
    end

endmodule // FlexibleInsertStack_TB
