// hart.v
// Single-cycle RV32I processor.

`default_nettype none

module hart #(
    parameter RESET_ADDR = 32'h00000000
) (
    input  wire        i_clk,
    input  wire        i_rst,

    // Instruction memory
    output wire [31:0] o_imem_raddr,
    input  wire [31:0] i_imem_rdata,

    // Data memory
    output wire [31:0] o_dmem_addr,
    output wire        o_dmem_ren,
    output wire        o_dmem_wen,
    output wire [31:0] o_dmem_wdata,
    output wire [ 3:0] o_dmem_mask,
    input  wire [31:0] i_dmem_rdata,

    // Retire interface
    output wire        o_retire_valid,
    output wire [31:0] o_retire_inst,
    output wire        o_retire_trap,
    output wire        o_retire_halt,
    output wire [ 4:0] o_retire_rs1_raddr,
    output wire [ 4:0] o_retire_rs2_raddr,
    output wire [31:0] o_retire_rs1_rdata,
    output wire [31:0] o_retire_rs2_rdata,
    output wire [ 4:0] o_retire_rd_waddr,
    output wire [31:0] o_retire_rd_wdata,
    output wire [31:0] o_retire_pc,
    output wire [31:0] o_retire_next_pc

`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS,
`endif
);

    
    // Fetch
    reg  [31:0] pc;
    wire [31:0] pc_plus_4 = pc + 32'd4;
    wire [31:0] next_pc;

    assign o_imem_raddr = pc;
    wire [31:0] inst = i_imem_rdata;

    always @(posedge i_clk) begin
        if (i_rst) pc <= RESET_ADDR;
        else       pc <= next_pc;
    end

    // Decode

    wire [4:0] rs1_addr = inst[19:15];
    wire [4:0] rs2_addr = inst[24:20];
    wire [4:0] rd_addr  = inst[11:7];
    wire [2:0] funct3   = inst[14:12];

    wire [31:0] imm;
    immgen u_immgen (
        .i_inst (inst),
        .o_imm  (imm)
    );

    wire       reg_we_raw;
    wire [1:0] op1_sel;
    wire       op2_sel;
    wire [2:0] alu_opsel;
    wire       alu_sub;
    wire       alu_arith;
    wire       alu_unsigned;
    wire       mem_ren_raw;
    wire       mem_wen_raw;
    wire [1:0] wb_sel;
    wire       is_branch;
    wire       is_jump;
    wire       target_sel;
    wire       uses_rs1;
    wire       uses_rs2;
    wire       illegal;
    wire       halt;

    ctrl_decode u_decode (
        .i_inst         (inst),
        .o_reg_we       (reg_we_raw),
        .o_op1_sel      (op1_sel),
        .o_op2_sel      (op2_sel),
        .o_alu_opsel    (alu_opsel),
        .o_alu_sub      (alu_sub),
        .o_alu_arith    (alu_arith),
        .o_alu_unsigned (alu_unsigned),
        .o_mem_ren      (mem_ren_raw),
        .o_mem_wen      (mem_wen_raw),
        .o_wb_sel       (wb_sel),
        .o_is_branch    (is_branch),
        .o_is_jump      (is_jump),
        .o_target_sel   (target_sel),
        .o_uses_rs1     (uses_rs1),
        .o_uses_rs2     (uses_rs2),
        .o_illegal      (illegal),
        .o_halt         (halt)
    );


    // Register file
 
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] rd_wdata;
    wire        reg_we;
    wire        rf_we = reg_we & (rd_addr != 5'd0);

    
    regfile #(
        .BYPASS_EN (0)
    ) u_regfile (
        .i_clk       (i_clk),
        .i_rst       (i_rst),
        .i_rs1_raddr (rs1_addr),
        .o_rs1_rdata (rs1_data),
        .i_rs2_raddr (rs2_addr),
        .o_rs2_rdata (rs2_data),
        .i_rd_waddr  (rd_addr),
        .i_rd_wdata  (rd_wdata),
        .i_rd_wen    (rf_we)
    );

  
    // Execute
   =
    reg [31:0] alu_op1;
    always @(*) begin
        case (op1_sel)
            2'd0:    alu_op1 = rs1_data;   // the usual case
            2'd1:    alu_op1 = pc;         // auipc
            default: alu_op1 = 32'd0;      // lui
        endcase
    end

    wire [31:0] alu_op2 = op2_sel ? imm : rs2_data;

    wire [31:0] alu_result;
    wire        alu_eq;
    wire        alu_slt;

   
    alu u_alu (
        .i_op1      (alu_op1),
        .i_op2      (alu_op2),
        .i_opsel    (alu_opsel),
        .i_sub      (alu_sub),
        .i_arith    (alu_arith),
        .i_unsigned (alu_unsigned),
        .o_result   (alu_result),
        .o_eq       (alu_eq),
        .o_slt      (alu_slt)
    );

    
    // Branch resolution and target selection
   
    wire cond  = funct3[2] ? alu_slt : alu_eq;
    wire taken = funct3[0] ? ~cond : cond;

    wire branch_taken = is_branch & taken;
    wire do_jump      = is_jump | branch_taken;

   
    wire [31:0] pc_target   = pc + imm;
    // jalr clears bit 0 of the computed address; bit 1 is a trap, not a mask.
    wire [31:0] jalr_target = {alu_result[31:1], 1'b0};
    wire [31:0] target      = target_sel ? jalr_target : pc_target;


    // Memory access
  
    wire [31:0] load_data;
    wire        mem_misaligned;
    wire [31:0] dmem_addr_aligned;
    wire [ 3:0] dmem_mask;
    wire [31:0] dmem_wdata;

    lsu_align u_lsu (
        .i_addr       (alu_result),
        .i_funct3     (funct3),
        .i_store_data (rs2_data),
        .i_mem_rdata  (i_dmem_rdata),
        .o_dmem_addr  (dmem_addr_aligned),
        .o_dmem_mask  (dmem_mask),
        .o_dmem_wdata (dmem_wdata),
        .o_load_data  (load_data),
        .o_misaligned (mem_misaligned)
    );

   
    // Traps
   
    wire mem_access = mem_ren_raw | mem_wen_raw;
    wire trap_mem   = mem_access & mem_misaligned;
    wire trap_pc    = do_jump & target[1];
    wire trap       = illegal | trap_mem | trap_pc;

  
    assign reg_we      = reg_we_raw  & ~trap;
    assign o_dmem_ren  = mem_ren_raw & ~trap;
    assign o_dmem_wen  = mem_wen_raw & ~trap;
    assign o_dmem_addr = dmem_addr_aligned;
    assign o_dmem_mask = dmem_mask;
    assign o_dmem_wdata = dmem_wdata;


    // Writeback
    
    reg [31:0] wb_data;
    always @(*) begin
        case (wb_sel)
            2'd0:    wb_data = alu_result;
            2'd1:    wb_data = load_data;
            default: wb_data = pc_plus_4;   // jal / jalr link value
        endcase
    end
    assign rd_wdata = wb_data;


    // Next PC
  
    assign next_pc = (do_jump & ~trap) ? target : pc_plus_4;

    // Retire interface
   
    // Single cycle: one instruction completes every cycle, unconditionally.
    assign o_retire_valid     = 1'b1;
    assign o_retire_inst      = inst;
    assign o_retire_trap      = trap;
    assign o_retire_halt      = halt;

    assign o_retire_rs1_raddr = uses_rs1 ? rs1_addr : 5'd0;
    assign o_retire_rs2_raddr = uses_rs2 ? rs2_addr : 5'd0;
    assign o_retire_rs1_rdata = uses_rs1 ? rs1_data : 32'd0;
    assign o_retire_rs2_rdata = uses_rs2 ? rs2_data : 32'd0;
  
    assign o_retire_rd_waddr  = reg_we ? rd_addr : 5'd0;
    assign o_retire_rd_wdata  = rd_wdata;
    assign o_retire_pc        = pc;
    assign o_retire_next_pc   = next_pc;

endmodule

`default_nettype wire
