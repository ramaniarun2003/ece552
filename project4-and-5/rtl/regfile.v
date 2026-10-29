// regfile.v


`default_nettype none
 
module regfile #(
    parameter BYPASS_EN = 0
) (
    input  wire        i_clk,
    input  wire        i_rst,
 
    input  wire [ 4:0] i_rs1_raddr,
    output wire [31:0] o_rs1_rdata,
 
    input  wire [ 4:0] i_rs2_raddr,
    output wire [31:0] o_rs2_rdata,
 
    input  wire [ 4:0] i_rd_waddr,
    input  wire [31:0] i_rd_wdata,
    input  wire        i_rd_wen
);
 
    reg [31:0] regs [1:31];
 
    // x0 is not storage, so the bank starts at 1.
    genvar g;
    generate
        for (g = 1; g <= 31; g = g + 1) begin : rf_bank
            always @(posedge i_clk) begin
                if (i_rst)
                    regs[g] <= 32'd0;
                else if (i_rd_wen && (i_rd_waddr == g[4:0]))
                    regs[g] <= i_rd_wdata;
            end
        end
    endgenerate
 
    wire [31:0] rs1_raw = (i_rs1_raddr == 5'd0) ? 32'd0 : regs[i_rs1_raddr];
    wire [31:0] rs2_raw = (i_rs2_raddr == 5'd0) ? 32'd0 : regs[i_rs2_raddr];
 
    wire write_live = i_rd_wen && (i_rd_waddr != 5'd0);
    wire bypass_1   = (BYPASS_EN != 0) && write_live &&
                      (i_rd_waddr == i_rs1_raddr);
    wire bypass_2   = (BYPASS_EN != 0) && write_live &&
                      (i_rd_waddr == i_rs2_raddr);
 
    assign o_rs1_rdata = bypass_1 ? i_rd_wdata : rs1_raw;
    assign o_rs2_rdata = bypass_2 ? i_rd_wdata : rs2_raw;
 
endmodule
 
`default_nettype wire