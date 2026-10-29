// lsu_align.v
//

`default_nettype none

module lsu_align (
    input  wire [31:0] i_addr,        // byte address from the ALU
    input  wire [ 2:0] i_funct3,      // access size / signedness
    input  wire [31:0] i_store_data,  // rs2 data, unshifted
    input  wire [31:0] i_mem_rdata,   // raw word from dmem

    output wire [31:0] o_dmem_addr,   // word-aligned address
    output wire [ 3:0] o_dmem_mask,   // byte enables
    output wire [31:0] o_dmem_wdata,  // store data, shifted into lane
    output reg  [31:0] o_load_data,   // extracted + extended load result
    output wire        o_misaligned   // alignment trap condition
);

    wire [1:0] off  = i_addr[1:0];
    wire [1:0] size = i_funct3[1:0];   // 00 = byte, 01 = half, 10 = word

    assign o_dmem_addr = {i_addr[31:2], 2'b00};

    // ------------------------------------------------------------------
    // Byte enables: width of the access, shifted into position by off.
    // ------------------------------------------------------------------
    reg [3:0] size_mask;
    always @(*) begin
        case (size)
            2'b00:   size_mask = 4'b0001;
            2'b01:   size_mask = 4'b0011;
            default: size_mask = 4'b1111;
        endcase
    end

    reg [3:0] mask_shifted;
    always @(*) begin
        case (off)
            2'd0:    mask_shifted = size_mask;
            2'd1:    mask_shifted = {size_mask[2:0], 1'b0};
            2'd2:    mask_shifted = {size_mask[1:0], 2'b00};
            default: mask_shifted = {size_mask[0],   3'b000};
        endcase
    end
    assign o_dmem_mask = mask_shifted;

    // Store data: shift up into the addressed byte lane.
    
    reg [31:0] wdata_shifted;
    always @(*) begin
        case (off)
            2'd0:    wdata_shifted = i_store_data;
            2'd1:    wdata_shifted = {i_store_data[23:0],  8'd0};
            2'd2:    wdata_shifted = {i_store_data[15:0], 16'd0};
            default: wdata_shifted = {i_store_data[ 7:0], 24'd0};
        endcase
    end
    assign o_dmem_wdata = wdata_shifted;

    
    // Load data: shift the addressed bytes down to bit 0, then extend.
   
    reg [31:0] rdata_shifted;
    always @(*) begin
        case (off)
            2'd0:    rdata_shifted = i_mem_rdata;
            2'd1:    rdata_shifted = { 8'd0, i_mem_rdata[31: 8]};
            2'd2:    rdata_shifted = {16'd0, i_mem_rdata[31:16]};
            default: rdata_shifted = {24'd0, i_mem_rdata[31:24]};
        endcase
    end

    always @(*) begin
        case (i_funct3)
            3'b000:  o_load_data = {{24{rdata_shifted[ 7]}},
                                      rdata_shifted[ 7:0]};   // lb
            3'b001:  o_load_data = {{16{rdata_shifted[15]}},
                                      rdata_shifted[15:0]};   // lh
            3'b010:  o_load_data = rdata_shifted;             // lw
            3'b100:  o_load_data = {24'd0, rdata_shifted[ 7:0]};  // lbu
            3'b101:  o_load_data = {16'd0, rdata_shifted[15:0]};  // lhu
            default: o_load_data = rdata_shifted;
        endcase
    end

    // Byte accesses can never be misaligned.
    assign o_misaligned = ((size == 2'b01) && off[0]) ||
                          ((size == 2'b10) && (off != 2'b00));

endmodule

`default_nettype wire