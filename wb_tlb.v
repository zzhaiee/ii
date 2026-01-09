`timescale 1ns / 1ps
//*************************************************************************
//   > File: wb_tlb.v
//   > Description: Write-back module with TLB instruction support
//*************************************************************************
`define EXC_ENTER_ADDR 32'd0

module wb_tlb(
    input          WB_valid,
    input  [129:0] MEM_WB_bus_r,
    output         rf_wen,
    output [  4:0] rf_wdest,
    output [ 31:0] rf_wdata,
    output         WB_over,

    input             clk,
    input             resetn,
    output [ 32:0] exc_bus,
    output [  4:0] WB_wdest,
    output         cancel,
 
    output [ 31:0] WB_pc,
    output [ 31:0] HI_data,
    output [ 31:0] LO_data,
    
    // TLB operations
    output         tlbp,
    output         tlbr,
    output         tlbwi,
    output         tlbwr,
    
    // CP0 interface
    output         cp0_wen,
    output [  7:0] cp0_waddr,
    output [ 31:0] cp0_wdata,
    output [  7:0] cp0_raddr,
    input  [ 31:0] cp0_rdata
);

    // Extract signals from MEM->WB bus
    wire tlbr_op, tlbwi_op, tlbwr_op, tlbp_op;
    wire [31:0] mem_result;
    wire [31:0] lo_result;
    wire        hi_write;
    wire        lo_write;
    wire wen;
    wire [4:0] wdest;
    wire mfhi;
    wire mflo;
    wire mtc0;
    wire mfc0;
    wire [7:0] cp0r_addr;
    wire syscall;
    wire eret;
    wire [31:0] pc;
    
    assign {tlbr_op,
            tlbwi_op,
            tlbwr_op,
            tlbp_op,
            wen,
            wdest,
            mem_result,
            lo_result,
            hi_write,
            lo_write,
            mfhi,
            mflo,
            mtc0,
            mfc0,
            cp0r_addr,
            syscall,
            eret,
            pc} = MEM_WB_bus_r;

    // TLB operation outputs
    assign tlbp  = tlbp_op  & WB_valid;
    assign tlbr  = tlbr_op  & WB_valid;
    assign tlbwi = tlbwi_op & WB_valid;
    assign tlbwr = tlbwr_op & WB_valid;

    // HI/LO registers
    reg [31:0] hi;
    reg [31:0] lo;
    
    always @(posedge clk) begin
        if (hi_write && WB_valid) begin
            hi <= mem_result;
        end
    end
    
    always @(posedge clk) begin
        if (lo_write && WB_valid) begin
            lo <= lo_result;
        end
    end

    // CP0 interface
    assign cp0_wen   = mtc0 & WB_valid;
    assign cp0_waddr = cp0r_addr;
    assign cp0_wdata = mem_result;
    assign cp0_raddr = cp0r_addr;

    // Status register (simplified, using internal copy for syscall/eret handling)
    reg status_exl_r;
    always @(posedge clk) begin
        if (!resetn || eret) begin
            status_exl_r <= 1'b0;
        end
        else if (syscall && WB_valid) begin
            status_exl_r <= 1'b1;
        end
    end
    
    // EPC register (simplified)
    reg [31:0] epc_r;
    always @(posedge clk) begin
        if (syscall && WB_valid) begin
            epc_r <= pc;
        end
        else if (mtc0 && WB_valid && cp0r_addr == {5'd14, 3'd0}) begin
            epc_r <= mem_result;
        end
    end
    
    // Cancel signal
    assign cancel = (syscall | eret) & WB_over;

    // WB completion
    assign WB_over = WB_valid;

    // Register file write
    assign rf_wen   = wen & WB_over;
    assign rf_wdest = wdest;
    assign rf_wdata = mfhi ? hi :
                      mflo ? lo :
                      mfc0 ? cp0_rdata : mem_result;

    // Exception PC signal
    wire        exc_valid;
    wire [31:0] exc_pc;
    assign exc_valid = (syscall | eret) & WB_valid;
    assign exc_pc = syscall ? `EXC_ENTER_ADDR : epc_r;
    
    assign exc_bus = {exc_valid, exc_pc};

    // WB dest register
    assign WB_wdest = rf_wdest & {5{WB_valid}};

    // Display outputs
    assign WB_pc = pc;
    assign HI_data = hi;
    assign LO_data = lo;
endmodule
