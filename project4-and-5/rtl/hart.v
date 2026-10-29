// hart.v
// Pipelined RV32I processor.

`default_nettype none

module hart #(
    parameter RESET_ADDR = 32'h00000000
) (
    input  wire        i_clk,
    input  wire        i_rst,

    output wire [31:0] o_imem_raddr,
    input  wire [31:0] i_imem_rdata,

    output wire [31:0] o_dmem_addr,
    output wire        o_dmem_ren,
    output wire        o_dmem_wen,
    output wire [31:0] o_dmem_wdata,
    output wire [ 3:0] o_dmem_mask,
    input  wire [31:0] i_dmem_rdata,

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
    output wire [31:0] o_retire_dmem_addr,
    output wire [ 3:0] o_retire_dmem_mask,
    output wire        o_retire_dmem_ren,
    output wire        o_retire_dmem_wen,
    output wire [31:0] o_retire_dmem_rdata,
    output wire [31:0] o_retire_dmem_wdata,
    output wire [31:0] o_retire_pc,
    output wire [31:0] o_retire_next_pc

`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS,
`endif
);

    wire        stall;
    wire        redirect;
    wire [31:0] ex_target;

    // Fetch

    reg  [31:0] pc;
    assign o_imem_raddr = pc;
    wire [31:0] if_inst = i_imem_rdata;

    // IF/ID

    reg        ifid_valid;
    reg [31:0] ifid_pc;
    reg [31:0] ifid_inst;

    // Decode

    wire [31:0] id_inst   = ifid_inst;
    wire [ 4:0] id_rs1    = id_inst[19:15];
    wire [ 4:0] id_rs2    = id_inst[24:20];
    wire [ 4:0] id_rd     = id_inst[11:7];
    wire [ 2:0] id_funct3 = id_inst[14:12];

    wire [31:0] id_imm;
    immgen u_immgen (.i_inst(id_inst), .o_imm(id_imm));

    wire       id_reg_we;
    wire [1:0] id_op1_sel;
    wire       id_op2_sel;
    wire [2:0] id_alu_opsel;
    wire       id_alu_sub;
    wire       id_alu_arith;
    wire       id_alu_unsigned;
    wire       id_mem_ren;
    wire       id_mem_wen;
    wire [1:0] id_wb_sel;
    wire       id_is_branch;
    wire       id_is_jump;
    wire       id_target_sel;
    wire       id_uses_rs1;
    wire       id_uses_rs2;
    wire       id_illegal;
    wire       id_halt;

    ctrl_decode u_decode (
        .i_inst         (id_inst),
        .o_reg_we       (id_reg_we),
        .o_op1_sel      (id_op1_sel),
        .o_op2_sel      (id_op2_sel),
        .o_alu_opsel    (id_alu_opsel),
        .o_alu_sub      (id_alu_sub),
        .o_alu_arith    (id_alu_arith),
        .o_alu_unsigned (id_alu_unsigned),
        .o_mem_ren      (id_mem_ren),
        .o_mem_wen      (id_mem_wen),
        .o_wb_sel       (id_wb_sel),
        .o_is_branch    (id_is_branch),
        .o_is_jump      (id_is_jump),
        .o_target_sel   (id_target_sel),
        .o_uses_rs1     (id_uses_rs1),
        .o_uses_rs2     (id_uses_rs2),
        .o_illegal      (id_illegal),
        .o_halt         (id_halt)
    );

    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;
    wire [ 4:0] memwb_rd;
    wire [31:0] wb_data;
    wire        rf_wen;

    regfile #(
        .BYPASS_EN (1)
    ) u_regfile (
        .i_clk       (i_clk),
        .i_rst       (i_rst),
        .i_rs1_raddr (id_rs1),
        .o_rs1_rdata (id_rs1_data),
        .i_rs2_raddr (id_rs2),
        .o_rs2_rdata (id_rs2_data),
        .i_rd_waddr  (memwb_rd),
        .i_rd_wdata  (wb_data),
        .i_rd_wen    (rf_wen)
    );

    // ID/EX

    reg        idex_valid;
    reg [31:0] idex_pc;
    reg [31:0] idex_inst;
    reg [31:0] idex_rs1_data;
    reg [31:0] idex_rs2_data;
    reg [31:0] idex_imm;
    reg [ 4:0] idex_rs1;
    reg [ 4:0] idex_rs2;
    reg [ 4:0] idex_rd;
    reg [ 2:0] idex_funct3;
    reg        idex_reg_we;
    reg [ 1:0] idex_op1_sel;
    reg        idex_op2_sel;
    reg [ 2:0] idex_alu_opsel;
    reg        idex_alu_sub;
    reg        idex_alu_arith;
    reg        idex_alu_unsigned;
    reg        idex_mem_ren;
    reg        idex_mem_wen;
    reg [ 1:0] idex_wb_sel;
    reg        idex_is_branch;
    reg        idex_is_jump;
    reg        idex_target_sel;
    reg        idex_uses_rs1;
    reg        idex_uses_rs2;
    reg        idex_illegal;
    reg        idex_halt;

    // Execute

    reg  [31:0] ex_alu_op1;
    always @(*) begin
        case (idex_op1_sel)
            2'd0:    ex_alu_op1 = idex_rs1_data;   // rs1
            2'd1:    ex_alu_op1 = idex_pc;         // auipc
            default: ex_alu_op1 = 32'd0;           // lui
        endcase
    end

    wire [31:0] ex_alu_op2 = idex_op2_sel ? idex_imm : idex_rs2_data;

    wire [31:0] ex_alu_result;
    wire        ex_alu_eq;
    wire        ex_alu_slt;

    alu u_alu (
        .i_op1      (ex_alu_op1),
        .i_op2      (ex_alu_op2),
        .i_opsel    (idex_alu_opsel),
        .i_sub      (idex_alu_sub),
        .i_arith    (idex_alu_arith),
        .i_unsigned (idex_alu_unsigned),
        .o_result   (ex_alu_result),
        .o_eq       (ex_alu_eq),
        .o_slt      (ex_alu_slt)
    );

    wire ex_cond        = idex_funct3[2] ? ex_alu_slt : ex_alu_eq;
    wire ex_taken       = idex_funct3[0] ? ~ex_cond   : ex_cond;
    wire ex_branch_take = idex_is_branch & ex_taken;
    wire ex_do_jump     = idex_is_jump | ex_branch_take;

    wire [31:0] ex_pc_target   = idex_pc + idex_imm;
    wire [31:0] ex_jalr_target = {ex_alu_result[31:1], 1'b0};
    assign      ex_target      = idex_target_sel ? ex_jalr_target : ex_pc_target;

    wire ex_trap_pc = ex_do_jump & ex_target[1];
    wire ex_trap    = idex_illegal | ex_trap_pc;

    assign redirect = idex_valid & ex_do_jump & ~ex_trap;

    wire [31:0] ex_next_pc = redirect ? ex_target : (idex_pc + 32'd4);

    // EX/MEM

    reg        exmem_valid;
    reg [31:0] exmem_pc;
    reg [31:0] exmem_inst;
    reg [31:0] exmem_alu_result;
    reg [31:0] exmem_rs1_data;
    reg [31:0] exmem_rs2_data;
    reg [31:0] exmem_next_pc;
    reg [ 4:0] exmem_rs1;
    reg [ 4:0] exmem_rs2;
    reg [ 4:0] exmem_rd;
    reg [ 2:0] exmem_funct3;
    reg        exmem_reg_we;
    reg        exmem_mem_ren;
    reg        exmem_mem_wen;
    reg [ 1:0] exmem_wb_sel;
    reg        exmem_uses_rs1;
    reg        exmem_uses_rs2;
    reg        exmem_halt;
    reg        exmem_trap;

    // Memory

    wire [31:0] mem_dmem_addr;
    wire [ 3:0] mem_dmem_mask;
    wire [31:0] mem_dmem_wdata;
    wire [31:0] mem_load_data;
    wire        mem_misaligned;

    lsu_align u_lsu (
        .i_addr       (exmem_alu_result),
        .i_funct3     (exmem_funct3),
        .i_store_data (exmem_rs2_data),
        .i_mem_rdata  (i_dmem_rdata),
        .o_dmem_addr  (mem_dmem_addr),
        .o_dmem_mask  (mem_dmem_mask),
        .o_dmem_wdata (mem_dmem_wdata),
        .o_load_data  (mem_load_data),
        .o_misaligned (mem_misaligned)
    );

    wire mem_ren_act = exmem_valid & exmem_mem_ren & ~exmem_trap & ~mem_misaligned;
    wire mem_wen_act = exmem_valid & exmem_mem_wen & ~exmem_trap & ~mem_misaligned;
    wire trap_mem    = exmem_valid & (exmem_mem_ren | exmem_mem_wen) & mem_misaligned;
    wire mem_trap    = exmem_trap | trap_mem;

    assign o_dmem_addr  = mem_dmem_addr;
    assign o_dmem_mask  = mem_dmem_mask;
    assign o_dmem_wdata = mem_dmem_wdata;
    assign o_dmem_ren   = mem_ren_act;
    assign o_dmem_wen   = mem_wen_act;

    // MEM/WB

    reg        memwb_valid;
    reg [31:0] memwb_pc;
    reg [31:0] memwb_inst;
    reg [31:0] memwb_next_pc;
    reg [31:0] memwb_alu_result;
    reg [31:0] memwb_load_data;
    reg [31:0] memwb_rs1_data;
    reg [31:0] memwb_rs2_data;
    reg [ 4:0] memwb_rs1;
    reg [ 4:0] memwb_rs2;
    reg [ 4:0] memwb_rd_r;
    reg        memwb_reg_we;
    reg [ 1:0] memwb_wb_sel;
    reg        memwb_uses_rs1;
    reg        memwb_uses_rs2;
    reg        memwb_halt;
    reg        memwb_trap;
    reg [31:0] memwb_dmem_addr;
    reg [ 3:0] memwb_dmem_mask;
    reg        memwb_dmem_ren;
    reg        memwb_dmem_wen;
    reg [31:0] memwb_dmem_rdata;
    reg [31:0] memwb_dmem_wdata;

    assign memwb_rd = memwb_rd_r;

    // Writeback

    reg [31:0] wb_data_r;
    always @(*) begin
        case (memwb_wb_sel)
            2'd0:    wb_data_r = memwb_alu_result;
            2'd1:    wb_data_r = memwb_load_data;
            default: wb_data_r = memwb_pc + 32'd4;   // link
        endcase
    end
    assign wb_data = wb_data_r;
    assign rf_wen  = memwb_valid & memwb_reg_we & ~memwb_trap & (memwb_rd_r != 5'd0);

    // Hazard detection

    hazard_unit u_hazard (
        .i_id_valid    (ifid_valid),
        .i_id_uses_rs1 (id_uses_rs1),
        .i_id_uses_rs2 (id_uses_rs2),
        .i_id_rs1      (id_rs1),
        .i_id_rs2      (id_rs2),
        .i_ex_valid    (idex_valid),
        .i_ex_reg_we   (idex_reg_we),
        .i_ex_rd       (idex_rd),
        .i_mem_valid   (exmem_valid),
        .i_mem_reg_we  (exmem_reg_we),
        .i_mem_rd      (exmem_rd),
        .o_stall       (stall)
    );

    // Pipeline registers

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc          <= RESET_ADDR;
            ifid_valid  <= 1'b0;
            idex_valid  <= 1'b0;
            exmem_valid <= 1'b0;
            memwb_valid <= 1'b0;
        end else begin
            if (redirect)   pc <= ex_target;
            else if (stall) pc <= pc;
            else            pc <= pc + 32'd4;

            if (redirect) begin
                ifid_valid <= 1'b0;
            end else if (stall) begin
                // hold
            end else begin
                ifid_valid <= 1'b1;
                ifid_pc    <= pc;
                ifid_inst  <= if_inst;
            end

            if (redirect | stall) begin
                idex_valid <= 1'b0;
            end else begin
                idex_valid        <= ifid_valid;
                idex_pc           <= ifid_pc;
                idex_inst         <= ifid_inst;
                idex_rs1_data     <= id_rs1_data;
                idex_rs2_data     <= id_rs2_data;
                idex_imm          <= id_imm;
                idex_rs1          <= id_rs1;
                idex_rs2          <= id_rs2;
                idex_rd           <= id_rd;
                idex_funct3       <= id_funct3;
                idex_reg_we       <= id_reg_we;
                idex_op1_sel      <= id_op1_sel;
                idex_op2_sel      <= id_op2_sel;
                idex_alu_opsel    <= id_alu_opsel;
                idex_alu_sub      <= id_alu_sub;
                idex_alu_arith    <= id_alu_arith;
                idex_alu_unsigned <= id_alu_unsigned;
                idex_mem_ren      <= id_mem_ren;
                idex_mem_wen      <= id_mem_wen;
                idex_wb_sel       <= id_wb_sel;
                idex_is_branch    <= id_is_branch;
                idex_is_jump      <= id_is_jump;
                idex_target_sel   <= id_target_sel;
                idex_uses_rs1     <= id_uses_rs1;
                idex_uses_rs2     <= id_uses_rs2;
                idex_illegal      <= id_illegal;
                idex_halt         <= id_halt;
            end

            exmem_valid      <= idex_valid;
            exmem_pc         <= idex_pc;
            exmem_inst       <= idex_inst;
            exmem_alu_result <= ex_alu_result;
            exmem_rs1_data   <= idex_rs1_data;
            exmem_rs2_data   <= idex_rs2_data;
            exmem_next_pc    <= ex_next_pc;
            exmem_rs1        <= idex_rs1;
            exmem_rs2        <= idex_rs2;
            exmem_rd         <= idex_rd;
            exmem_funct3     <= idex_funct3;
            exmem_reg_we     <= idex_reg_we;
            exmem_mem_ren    <= idex_mem_ren;
            exmem_mem_wen    <= idex_mem_wen;
            exmem_wb_sel     <= idex_wb_sel;
            exmem_uses_rs1   <= idex_uses_rs1;
            exmem_uses_rs2   <= idex_uses_rs2;
            exmem_halt       <= idex_halt;
            exmem_trap       <= idex_valid & (idex_illegal | ex_trap_pc);

            memwb_valid      <= exmem_valid;
            memwb_pc         <= exmem_pc;
            memwb_inst       <= exmem_inst;
            memwb_next_pc    <= exmem_next_pc;
            memwb_alu_result <= exmem_alu_result;
            memwb_load_data  <= mem_load_data;
            memwb_rs1_data   <= exmem_rs1_data;
            memwb_rs2_data   <= exmem_rs2_data;
            memwb_rs1        <= exmem_rs1;
            memwb_rs2        <= exmem_rs2;
            memwb_rd_r       <= exmem_rd;
            memwb_reg_we     <= exmem_reg_we;
            memwb_wb_sel     <= exmem_wb_sel;
            memwb_uses_rs1   <= exmem_uses_rs1;
            memwb_uses_rs2   <= exmem_uses_rs2;
            memwb_halt       <= exmem_halt;
            memwb_trap       <= mem_trap;
            memwb_dmem_addr  <= mem_dmem_addr;
            memwb_dmem_mask  <= mem_dmem_mask;
            memwb_dmem_ren   <= mem_ren_act;
            memwb_dmem_wen   <= mem_wen_act;
            memwb_dmem_rdata <= i_dmem_rdata;
            memwb_dmem_wdata <= mem_dmem_wdata;
        end
    end

    // Retire

    assign o_retire_valid     = memwb_valid;
    assign o_retire_inst      = memwb_inst;
    assign o_retire_trap      = memwb_valid & memwb_trap;
    assign o_retire_halt      = memwb_valid & memwb_halt;

    assign o_retire_rs1_raddr = memwb_uses_rs1 ? memwb_rs1 : 5'd0;
    assign o_retire_rs2_raddr = memwb_uses_rs2 ? memwb_rs2 : 5'd0;
    assign o_retire_rs1_rdata = memwb_uses_rs1 ? memwb_rs1_data : 32'd0;
    assign o_retire_rs2_rdata = memwb_uses_rs2 ? memwb_rs2_data : 32'd0;

    assign o_retire_rd_waddr  = (memwb_reg_we & ~memwb_trap) ? memwb_rd_r : 5'd0;
    assign o_retire_rd_wdata  = wb_data;

    assign o_retire_dmem_addr  = memwb_dmem_addr;
    assign o_retire_dmem_mask  = memwb_dmem_mask;
    assign o_retire_dmem_ren   = memwb_dmem_ren;
    assign o_retire_dmem_wen   = memwb_dmem_wen;
    assign o_retire_dmem_rdata = memwb_dmem_rdata;
    assign o_retire_dmem_wdata = memwb_dmem_wdata;

    assign o_retire_pc        = memwb_pc;
    assign o_retire_next_pc   = memwb_next_pc;

endmodule

`default_nettype wire
