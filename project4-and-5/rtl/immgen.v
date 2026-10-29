// immgen.v
// RV32I immediate generator. Selects one of five immediate formats based on
// the opcode and produces a 32-bit sign/zero-extended constant.
//

`default_nettype none

module immgen (
    input  wire [31:0] i_inst,
    output reg  [31:0] o_imm
);

    wire [6:0] opcode = i_inst[6:0];

    always @(*) begin
        case (opcode)
            // I-type: OP-IMM, LOAD, JALR
            7'b0010011,
            7'b0000011,
            7'b1100111:
                o_imm = {{20{i_inst[31]}}, i_inst[31:20]};

            // S-type: STORE. Split so rs1/rs2 keep their usual bit positions.
            7'b0100011:
                o_imm = {{20{i_inst[31]}}, i_inst[31:25], i_inst[11:7]};

            // B-type: BRANCH. Bit 0 is an implicit zero (4-byte aligned
            // targets), so there is no shift-left-2 anywhere in the datapath.
            7'b1100011:
                o_imm = {{19{i_inst[31]}}, i_inst[31], i_inst[7],
                         i_inst[30:25], i_inst[11:8], 1'b0};

            // U-type: LUI, AUIPC. Already occupies the top 20 bits.
            7'b0110111,
            7'b0010111:
                o_imm = {i_inst[31:12], 12'b0};

            // J-type: JAL. Same implicit zero in bit 0.
            7'b1101111:
                o_imm = {{11{i_inst[31]}}, i_inst[31], i_inst[19:12],
                         i_inst[20], i_inst[30:21], 1'b0};

            default:
                o_imm = 32'd0;
        endcase
    end

endmodule

`default_nettype wire
