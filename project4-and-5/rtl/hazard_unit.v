// hazard_unit.v

`default_nettype none

module hazard_unit (
    input  wire        i_id_valid,
    input  wire        i_id_uses_rs1,
    input  wire        i_id_uses_rs2,
    input  wire [ 4:0] i_id_rs1,
    input  wire [ 4:0] i_id_rs2,

    input  wire        i_ex_valid,
    input  wire        i_ex_reg_we,
    input  wire [ 4:0] i_ex_rd,

    input  wire        i_mem_valid,
    input  wire        i_mem_reg_we,
    input  wire [ 4:0] i_mem_rd,

    output wire        o_stall
);

    wire ex_hit_rs1  = i_ex_valid  & i_ex_reg_we  & (i_ex_rd  == i_id_rs1);
    wire mem_hit_rs1 = i_mem_valid & i_mem_reg_we & (i_mem_rd == i_id_rs1);
    wire ex_hit_rs2  = i_ex_valid  & i_ex_reg_we  & (i_ex_rd  == i_id_rs2);
    wire mem_hit_rs2 = i_mem_valid & i_mem_reg_we & (i_mem_rd == i_id_rs2);

    wire stall_rs1 = i_id_uses_rs1 & (i_id_rs1 != 5'd0) & (ex_hit_rs1 | mem_hit_rs1);
    wire stall_rs2 = i_id_uses_rs2 & (i_id_rs2 != 5'd0) & (ex_hit_rs2 | mem_hit_rs2);

    assign o_stall = i_id_valid & (stall_rs1 | stall_rs2);

endmodule

`default_nettype wire
