// alu.v
//

 
`default_nettype none
 
module alu (
    input  wire [31:0] i_op1,
    input  wire [31:0] i_op2,
    input  wire [ 2:0] i_opsel,
    input  wire        i_sub,       // ADD vs SUB on opsel 000
    input  wire        i_arith,     // SRL vs SRA on opsel 101
    input  wire        i_unsigned,  // signed vs unsigned comparison
    output reg  [31:0] o_result,
    output wire        o_eq,
    output wire        o_slt
);
 
    // RV32I shifts use only the low five bits of the second operand.
    wire [ 4:0] shamt = i_op2[4:0];
 
    wire [31:0] diff = i_op1 - i_op2;
    wire [31:0] sum  = i_sub ? diff : (i_op1 + i_op2);
 
    // ------------------------------------------------------------------
    // Comparison flags. Both the branch unit and the SLT family read these.
    // When the signs differ the negative operand is the smaller one; when
    // they match the subtraction's sign bit answers it.
    // ------------------------------------------------------------------
    wire slt_signed   = (i_op1[31] ^ i_op2[31]) ? i_op1[31] : diff[31];
    wire slt_unsigned = (i_op1 < i_op2);
 
    assign o_eq  = (i_op1 == i_op2);
    assign o_slt = i_unsigned ? slt_unsigned : slt_signed;
 
    // ------------------------------------------------------------------
    // Left barrel shifter, five constant-shift stages.
    // ------------------------------------------------------------------
    wire [31:0] sl0 = shamt[0] ? {i_op1[30:0],  1'd0} : i_op1;
    wire [31:0] sl1 = shamt[1] ? {sl0[29:0],    2'd0} : sl0;
    wire [31:0] sl2 = shamt[2] ? {sl1[27:0],    4'd0} : sl1;
    wire [31:0] sl3 = shamt[3] ? {sl2[23:0],    8'd0} : sl2;
    wire [31:0] sl4 = shamt[4] ? {sl3[15:0],   16'd0} : sl3;
 
    // ------------------------------------------------------------------
    // Right barrel shifter. The fill bit makes one shifter serve both SRL
    // and SRA: arithmetic shifts preserve the sign, so i_op1[31] is still
    // the correct fill at every stage.
    // ------------------------------------------------------------------
    wire fill = i_arith & i_op1[31];
 
    wire [31:0] sr0 = shamt[0] ? {{ 1{fill}}, i_op1[31: 1]} : i_op1;
    wire [31:0] sr1 = shamt[1] ? {{ 2{fill}}, sr0  [31: 2]} : sr0;
    wire [31:0] sr2 = shamt[2] ? {{ 4{fill}}, sr1  [31: 4]} : sr1;
    wire [31:0] sr3 = shamt[3] ? {{ 8{fill}}, sr2  [31: 8]} : sr2;
    wire [31:0] sr4 = shamt[4] ? {{16{fill}}, sr3  [31:16]} : sr3;
 
    always @(*) begin
        case (i_opsel)
            3'b000:  o_result = sum;                // ADD / SUB
            3'b001:  o_result = sl4;                // SLL
            3'b010,                                 // SLT
            3'b011:  o_result = {31'd0, o_slt};     // SLTU
            3'b100:  o_result = i_op1 ^ i_op2;      // XOR
            3'b101:  o_result = sr4;                // SRL / SRA
            3'b110:  o_result = i_op1 | i_op2;      // OR
            default: o_result = i_op1 & i_op2;      // AND
        endcase
    end
 
endmodule
 
`default_nettype wire