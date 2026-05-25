# Project 4: verilog-Infix-to-Postfix Converter — FSM-Based Verilog Design

Verilog implementation of a hardware infix-to-postfix expression converter
using a Finite State Machine (FSM) and a custom parameterized stack module,
designed as part of CSE320 (Digital Logic / FPGA Design).

## How It Works

The design implements the **Shunting-Yard Algorithm** in hardware using three
stack instances and a 4-state FSM controller:

| State | Description |
|-------|-------------|
| `IDLE` | Waits for start signal (ST=1) |
| `READ` | Streams input symbols into InfixExpStack one char per clock |
| `GETTOKEN` | Processes each token — routes operands, operators, parentheses |
| `DONE` | Asserts Ready=1, returns to IDLE |

**Operator precedence (high → low):** `!` (unary minus) → `^` → `* /` → `+ -`

## Files

| File | Description |
|------|-------------|
| `FlexibleInsertStack.v` | Parameterized stack — supports HOLD, INSERT\_END, INSERT\_FRONT, POP |
| `Infix2Postfix.v` | Top-level FSM converter — instantiates 3 stack instances |
| `Infix2Postfix_TB.v` | Testbench for the infix-to-postfix converter |
| `FlexibleInsertStack_TB.v` | Testbench for the stack module |
| `PolyN_1.v` | Polynomial evaluation helper module |
| `ASM_Chart_Infix2Postfix.png` | ASM chart — full state/transition diagram |

## Architecture

Three `FlexibleInsertStack` instances are used:

- **InfixExpStack** — holds the incoming infix expression
- **OperatorStack** — holds pending operators during conversion
- **ResultStack** — accumulates the final postfix output

## How to Simulate (Icarus Verilog)

```bash
# Infix-to-Postfix converter
iverilog -o Infix2Postfix_sim Infix2Postfix.v FlexibleInsertStack.v Infix2Postfix_TB.v && vvp Infix2Postfix_sim

# FlexibleInsertStack standalone
iverilog -o flexibleinsertstack_sim FlexibleInsertStack.v FlexibleInsertStack_TB.v && vvp flexibleinsertstack_sim
```

## Tools Used
- Icarus Verilog (functional simulation)
- AMD Vivado (RTL schematic & synthesis)
- Target Board: Xilinx XC7A100TCSG324-1 (Artix-7)
