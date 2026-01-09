`timescale 1ns / 1ps
//*************************************************************************
//   > File: cp0_regs.v
//   > Description: CP0 Coprocessor Registers module
//   > Features:
//   >   - TLB-related registers (Index, EntryLo0/1, EntryHi, PageMask, etc.)
//   >   - Exception handling registers (Status, Cause, EPC)
//   >   - Random register with pseudo-random generation
//*************************************************************************

module cp0_regs(
    input         clk,
    input         resetn,
    
    // Write interface
    input         wen,           // CP0 write enable
    input  [ 7:0] waddr,         // Write address {rd, sel}
    input  [31:0] wdata,         // Write data
    
    // Read interface
    input  [ 7:0] raddr,         // Read address {rd, sel}
    output [31:0] rdata,         // Read data
    
    // TLB operation interface
    input         tlbp,          // TLB Probe
    input         tlbr,          // TLB Read
    input         tlbwi,         // TLB Write Indexed
    input         tlbwr,         // TLB Write Random
    
    // TLB lookup results
    input         tlbp_found,    // TLBP found match
    input  [ 3:0] tlbp_index,    // TLBP found index
    input  [31:0] tlbr_entryhi,  // TLBR EntryHi result
    input  [31:0] tlbr_entrylo0, // TLBR EntryLo0 result
    input  [31:0] tlbr_entrylo1, // TLBR EntryLo1 result
    
    // Exception interface
    input         exc_valid,     // Exception occurred
    input  [ 4:0] exc_code,      // Exception code
    input  [31:0] exc_pc,        // Exception PC
    input  [31:0] exc_badvaddr,  // Bad virtual address
    input         exc_bd,        // Branch delay slot
    input         eret,          // Exception return
    
    // Output to other modules
    output [31:0] cp0_index,
    output [31:0] cp0_entryhi,
    output [31:0] cp0_entrylo0,
    output [31:0] cp0_entrylo1,
    output [31:0] cp0_status,
    output [31:0] cp0_cause,
    output [31:0] cp0_epc,
    output [31:0] cp0_random,
    output [31:0] cp0_wired,
    output [31:0] cp0_badvaddr,
    output [31:0] cp0_count,
    output [31:0] cp0_compare
);

    // CP0 register addresses
    localparam ADDR_INDEX    = {5'd0, 3'd0};   // Register 0, Select 0
    localparam ADDR_RANDOM   = {5'd1, 3'd0};   // Register 1, Select 0
    localparam ADDR_ENTRYLO0 = {5'd2, 3'd0};   // Register 2, Select 0
    localparam ADDR_ENTRYLO1 = {5'd3, 3'd0};   // Register 3, Select 0
    localparam ADDR_CONTEXT  = {5'd4, 3'd0};   // Register 4, Select 0
    localparam ADDR_PAGEMASK = {5'd5, 3'd0};   // Register 5, Select 0
    localparam ADDR_WIRED    = {5'd6, 3'd0};   // Register 6, Select 0
    localparam ADDR_BADVADDR = {5'd8, 3'd0};   // Register 8, Select 0
    localparam ADDR_COUNT    = {5'd9, 3'd0};   // Register 9, Select 0
    localparam ADDR_ENTRYHI  = {5'd10,3'd0};   // Register 10, Select 0
    localparam ADDR_COMPARE  = {5'd11,3'd0};   // Register 11, Select 0
    localparam ADDR_STATUS   = {5'd12,3'd0};   // Register 12, Select 0
    localparam ADDR_CAUSE    = {5'd13,3'd0};   // Register 13, Select 0
    localparam ADDR_EPC      = {5'd14,3'd0};   // Register 14, Select 0

    // CP0 Registers
    reg [31:0] index_r;      // TLB Index register
    reg [31:0] random_r;     // TLB Random register
    reg [31:0] entrylo0_r;   // TLB EntryLo0 register
    reg [31:0] entrylo1_r;   // TLB EntryLo1 register
    reg [31:0] context_r;    // Context register
    reg [31:0] pagemask_r;   // PageMask register
    reg [31:0] wired_r;      // Wired register
    reg [31:0] badvaddr_r;   // Bad Virtual Address register
    reg [31:0] count_r;      // Count register
    reg [31:0] entryhi_r;    // TLB EntryHi register
    reg [31:0] compare_r;    // Compare register
    reg [31:0] status_r;     // Status register
    reg [31:0] cause_r;      // Cause register
    reg [31:0] epc_r;        // Exception PC register

    // Index register
    // P bit indicates probe failure, Index field for TLB operations
    always @(posedge clk) begin
        if (!resetn) begin
            index_r <= 32'd0;
        end
        else if (tlbp) begin
            index_r <= tlbp_found ? {28'd0, tlbp_index} : {1'b1, 31'd0};
        end
        else if (wen && waddr == ADDR_INDEX) begin
            index_r <= {wdata[31], 27'd0, wdata[3:0]};
        end
    end
    
    // Random register - pseudo-random counter for TLBWR
    always @(posedge clk) begin
        if (!resetn) begin
            random_r <= 32'd15;  // Initialize to max TLB entry
        end
        else begin
            // Decrement, but not below Wired value
            if (random_r[3:0] == wired_r[3:0]) begin
                random_r <= 32'd15;
            end
            else begin
                random_r <= {28'd0, random_r[3:0] - 1'b1};
            end
        end
    end
    
    // EntryLo0 register
    always @(posedge clk) begin
        if (!resetn) begin
            entrylo0_r <= 32'd0;
        end
        else if (tlbr) begin
            entrylo0_r <= tlbr_entrylo0;
        end
        else if (wen && waddr == ADDR_ENTRYLO0) begin
            entrylo0_r <= {6'd0, wdata[25:0]};
        end
    end
    
    // EntryLo1 register
    always @(posedge clk) begin
        if (!resetn) begin
            entrylo1_r <= 32'd0;
        end
        else if (tlbr) begin
            entrylo1_r <= tlbr_entrylo1;
        end
        else if (wen && waddr == ADDR_ENTRYLO1) begin
            entrylo1_r <= {6'd0, wdata[25:0]};
        end
    end
    
    // Context register
    always @(posedge clk) begin
        if (!resetn) begin
            context_r <= 32'd0;
        end
        else if (exc_valid && (exc_code == 5'd2 || exc_code == 5'd3)) begin
            // TLB exception - update BadVPN2 field
            context_r <= {context_r[31:23], exc_badvaddr[31:13], 4'd0};
        end
        else if (wen && waddr == ADDR_CONTEXT) begin
            context_r <= {wdata[31:23], context_r[22:0]};
        end
    end
    
    // PageMask register (simplified - always 4KB pages)
    always @(posedge clk) begin
        if (!resetn) begin
            pagemask_r <= 32'd0;
        end
        else if (wen && waddr == ADDR_PAGEMASK) begin
            pagemask_r <= {3'd0, wdata[28:13], 13'd0};
        end
    end
    
    // Wired register
    always @(posedge clk) begin
        if (!resetn) begin
            wired_r <= 32'd0;
        end
        else if (wen && waddr == ADDR_WIRED) begin
            wired_r <= {28'd0, wdata[3:0]};
            // Reset Random when Wired is written
        end
    end
    
    // BadVAddr register
    always @(posedge clk) begin
        if (!resetn) begin
            badvaddr_r <= 32'd0;
        end
        else if (exc_valid && (exc_code == 5'd2 || exc_code == 5'd3 || 
                               exc_code == 5'd4 || exc_code == 5'd5)) begin
            badvaddr_r <= exc_badvaddr;
        end
    end
    
    // Count register - increments every other cycle
    reg count_tick;
    always @(posedge clk) begin
        if (!resetn) begin
            count_r <= 32'd0;
            count_tick <= 1'b0;
        end
        else if (wen && waddr == ADDR_COUNT) begin
            count_r <= wdata;
            count_tick <= 1'b0;
        end
        else begin
            count_tick <= ~count_tick;
            if (count_tick) begin
                count_r <= count_r + 1'b1;
            end
        end
    end
    
    // EntryHi register
    always @(posedge clk) begin
        if (!resetn) begin
            entryhi_r <= 32'd0;
        end
        else if (tlbr) begin
            entryhi_r <= tlbr_entryhi;
        end
        else if (exc_valid && (exc_code == 5'd2 || exc_code == 5'd3)) begin
            // TLB exception - update VPN2 field
            entryhi_r <= {exc_badvaddr[31:13], 5'd0, entryhi_r[7:0]};
        end
        else if (wen && waddr == ADDR_ENTRYHI) begin
            entryhi_r <= {wdata[31:13], 5'd0, wdata[7:0]};
        end
    end
    
    // Compare register
    always @(posedge clk) begin
        if (!resetn) begin
            compare_r <= 32'd0;
        end
        else if (wen && waddr == ADDR_COMPARE) begin
            compare_r <= wdata;
        end
    end
    
    // Status register
    always @(posedge clk) begin
        if (!resetn) begin
            status_r <= 32'h00400000;  // BEV=1 after reset
        end
        else if (exc_valid) begin
            status_r[1] <= 1'b1;  // EXL = 1
        end
        else if (eret) begin
            status_r[1] <= 1'b0;  // EXL = 0
        end
        else if (wen && waddr == ADDR_STATUS) begin
            status_r <= {9'd0, wdata[22], 6'd0, wdata[15:8], 6'd0, wdata[1:0]};
        end
    end
    
    // Cause register
    always @(posedge clk) begin
        if (!resetn) begin
            cause_r <= 32'd0;
        end
        else if (exc_valid) begin
            cause_r[6:2] <= exc_code;
            cause_r[31]  <= exc_bd;
        end
        else if (wen && waddr == ADDR_CAUSE) begin
            cause_r[9:8] <= wdata[9:8];  // Only IP[1:0] are writable
        end
    end
    
    // EPC register
    always @(posedge clk) begin
        if (!resetn) begin
            epc_r <= 32'd0;
        end
        else if (exc_valid && !status_r[1]) begin
            epc_r <= exc_pc;
        end
        else if (wen && waddr == ADDR_EPC) begin
            epc_r <= wdata;
        end
    end
    
    // Read mux
    assign rdata = (raddr == ADDR_INDEX)    ? index_r    :
                   (raddr == ADDR_RANDOM)   ? random_r   :
                   (raddr == ADDR_ENTRYLO0) ? entrylo0_r :
                   (raddr == ADDR_ENTRYLO1) ? entrylo1_r :
                   (raddr == ADDR_CONTEXT)  ? context_r  :
                   (raddr == ADDR_PAGEMASK) ? pagemask_r :
                   (raddr == ADDR_WIRED)    ? wired_r    :
                   (raddr == ADDR_BADVADDR) ? badvaddr_r :
                   (raddr == ADDR_COUNT)    ? count_r    :
                   (raddr == ADDR_ENTRYHI)  ? entryhi_r  :
                   (raddr == ADDR_COMPARE)  ? compare_r  :
                   (raddr == ADDR_STATUS)   ? status_r   :
                   (raddr == ADDR_CAUSE)    ? cause_r    :
                   (raddr == ADDR_EPC)      ? epc_r      :
                                              32'd0;
    
    // Output assignments
    assign cp0_index    = index_r;
    assign cp0_entryhi  = entryhi_r;
    assign cp0_entrylo0 = entrylo0_r;
    assign cp0_entrylo1 = entrylo1_r;
    assign cp0_status   = status_r;
    assign cp0_cause    = cause_r;
    assign cp0_epc      = epc_r;
    assign cp0_random   = random_r;
    assign cp0_wired    = wired_r;
    assign cp0_badvaddr = badvaddr_r;
    assign cp0_count    = count_r;
    assign cp0_compare  = compare_r;

endmodule
