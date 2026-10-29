// ctrl_decode.v

`default_nettype none

module ctrl_decode (
    input  wire [31:0] i_inst,

    output reg         o_reg_we,        // write the register file
    output reg  [ 1:0] o_op1_sel,       // ALU operand 1 source
    output reg         o_op2_sel,       // ALU operand 2 source
    output reg  [ 2:0] o_alu_opsel,     // ALU i_opsel
    output reg         o_alu_sub,       // ALU i_sub
    output reg         o_alu_arith,     // ALU i_arith (SRA/SRAI)
    output reg         o_alu_unsigned,  // ALU i_unsigned
    output reg         o_mem_ren,       // data memory read
    output reg         o_mem_wen,       // data memory write
    output reg  [ 1:0] o_wb_sel,        // writeback source
    output reg         o_is_branch,     // conditional branch
    output reg         o_is_jump,       // unconditional jump (jal/jalr)
    output reg         o_target_sel,    // which target adder feeds the PC mux
    output reg         o_uses_rs1,      // instruction actually reads rs1
    output reg         o_uses_rs2,      // instruction actually reads rs2
    output reg         o_illegal,       // undefined encoding -> trap
    output reg         o_halt           // ebreak
);

    wire [6:0] opcode = i_inst[6:0];
    wire [2:0] funct3 = i_inst[14:12];
    wire [6:0] funct7 = i_inst[31:25];

    // The two funct7 values the base ISA ever uses.
    wire f7_zero = (funct7 == 7'b0000000);
    wire f7_alt  = (funct7 == 7'b0100000);

    always @(*) begin
        // Defaults first. Every output is assigned on every path, so this
        // always block stays combinational and never infers a latch.
        o_reg_we       = 1'b0;
        o_op1_sel      = 2'd0;
        o_op2_sel      = 1'b0;
        o_alu_opsel    = 3'b000;
        o_alu_sub      = 1'b0;
        o_alu_arith    = 1'b0;
        o_alu_unsigned = 1'b0;
        o_mem_ren      = 1'b0;
        o_mem_wen      = 1'b0;
        o_wb_sel       = 2'd0;
        o_is_branch    = 1'b0;
        o_is_jump      = 1'b0;
        o_target_sel   = 1'b0;
        o_uses_rs1     = 1'b0;
        o_uses_rs2     = 1'b0;
        o_illegal      = 1'b0;
        o_halt         = 1'b0;

        case (opcode)

    
            7'b0110011: begin
                o_reg_we       = 1'b1;
                o_op1_sel      = 2'd0;              // rs1
                o_op2_sel      = 1'b0;              // rs2
                o_alu_opsel    = funct3;
                // inst[30] means SUB for funct3 000 and SRA for funct3 101.
                o_alu_sub      = (funct3 == 3'b000) ? i_inst[30] : 1'b0;
                o_alu_arith    = (funct3 == 3'b101) ? i_inst[30] : 1'b0;
                o_alu_unsigned = (funct3 == 3'b011);   // SLTU only
                o_wb_sel       = 2'd0;
                o_uses_rs1     = 1'b1;
                o_uses_rs2     = 1'b1;
                o_illegal      = !(f7_zero ||
                                   (f7_alt && (funct3 == 3'b000 ||
                                               funct3 == 3'b101)));
            end

            // OP-IMM : register-immediate arithmetic
            7'b0010011: begin
                o_reg_we       = 1'b1;
                o_op1_sel      = 2'd0;              // rs1
                o_op2_sel      = 1'b1;              // imm
                o_alu_opsel    = funct3;
                o_alu_sub      = 1'b0;              // there is no SUBI
                o_alu_arith    = (funct3 == 3'b101) ? i_inst[30] : 1'b0;
                o_alu_unsigned = (funct3 == 3'b011);   // SLTIU only
                o_wb_sel       = 2'd0;
                o_uses_rs1     = 1'b1;
                // Shift immediates reuse the funct7 field, so it is checked.
               
                case (funct3)
                    3'b001:  o_illegal = !f7_zero;               // SLLI
                    3'b101:  o_illegal = !(f7_zero || f7_alt);   // SRLI/SRAI
                    default: o_illegal = 1'b0;
                endcase
            end

            // LOAD 
            7'b0000011: begin
                o_reg_we    = 1'b1;
                o_op1_sel   = 2'd0;                 // rs1 (base)
                o_op2_sel   = 1'b1;                 // imm (offset)
                o_alu_opsel = 3'b000;               // forced add
                o_mem_ren   = 1'b1;
                o_wb_sel    = 2'd1;                 // memory
                o_uses_rs1  = 1'b1;
                o_illegal   = (funct3 == 3'b011) ||
                              (funct3 == 3'b110) ||
                              (funct3 == 3'b111);
            end

            // STORE 
            7'b0100011: begin
                o_reg_we    = 1'b0;                 // writes no register
                o_op1_sel   = 2'd0;                 // rs1 (base)
                o_op2_sel   = 1'b1;                 // imm (offset)
                o_alu_opsel = 3'b000;               // forced add
                o_mem_wen   = 1'b1;
                o_uses_rs1  = 1'b1;
                o_uses_rs2  = 1'b1;
                o_illegal   = (funct3 != 3'b000) &&
                              (funct3 != 3'b001) &&
                              (funct3 != 3'b010);
            end

            // BRANCH 
            7'b1100011: begin
                o_reg_we       = 1'b0;
                o_op1_sel      = 2'd0;              // rs1
                o_op2_sel      = 1'b0;              // rs2
                o_alu_opsel    = 3'b000;
                o_alu_sub      = 1'b1;              // produce o_eq / o_slt
                o_alu_unsigned = funct3[1];         // BLTU / BGEU
                o_is_branch    = 1'b1;
                o_target_sel   = 1'b0;              // pc + imm
                o_uses_rs1     = 1'b1;
                o_uses_rs2     = 1'b1;
                o_illegal      = (funct3 == 3'b010) || (funct3 == 3'b011);
            end

            // JAL 
            7'b1101111: begin
                o_reg_we     = 1'b1;
                o_wb_sel     = 2'd2;                // link value = pc + 4
                o_is_jump    = 1'b1;
                o_target_sel = 1'b0;                // pc + imm
            end

            //JALR
            7'b1100111: begin
                o_reg_we     = 1'b1;
                o_op1_sel    = 2'd0;                // rs1
                o_op2_sel    = 1'b1;                // imm
                o_alu_opsel  = 3'b000;              // forced add
                o_wb_sel     = 2'd2;                // link value = pc + 4
                o_is_jump    = 1'b1;
                o_target_sel = 1'b1;                // rs1 + imm, bit 0 cleared
                o_uses_rs1   = 1'b1;
                o_illegal    = (funct3 != 3'b000);
            end

            //LUI
            7'b0110111: begin
                o_reg_we    = 1'b1;
                o_op1_sel   = 2'd2;                 // zero
                o_op2_sel   = 1'b1;                 // imm
                o_alu_opsel = 3'b000;
                o_wb_sel    = 2'd0;
            end

            // AUIPC
            7'b0010111: begin
                o_reg_we    = 1'b1;
                o_op1_sel   = 2'd1;                 // pc
                o_op2_sel   = 1'b1;                 // imm
                o_alu_opsel = 3'b000;
                o_wb_sel    = 2'd0;
            end

            7'b0001111: begin
                o_reg_we = 1'b0;
            end

            // SYSTEM 
            7'b1110011: begin
                case (i_inst)
                    32'h00100073: o_halt    = 1'b1;   // ebreak
                    default:      o_illegal = 1'b1;   // ecall, CSR ops
                endcase
            end

            default: o_illegal = 1'b1;

        endcase
    end

endmodule

`default_nettype wire