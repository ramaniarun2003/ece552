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
    input  wire        i_ex_mem_ren,    // instruction in EX is a load
    input  wire [ 4:0] i_ex_rd,

    output wire        o_stall
);
 
    wire ex_load = i_ex_valid & i_ex_reg_we & i_ex_mem_ren & (i_ex_rd != 5'd0);

    wire hit_rs1 = i_id_uses_rs1 & (i_id_rs1 == i_ex_rd);
    wire hit_rs2 = i_id_uses_rs2 & (i_id_rs2 == i_ex_rd);

    assign o_stall = i_id_valid & ex_load & (hit_rs1 | hit_rs2);

endmodule

`default_nettype wire
