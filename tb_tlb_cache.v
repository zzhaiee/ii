`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   
// Design Name:   pipeline_cpu_tlb_cache
// Module Name:   tb_tlb_cache.v
// Project Name:  pipeline_cpu
// Target Device:  
// Tool versions:  
// Description: 
//   Testbench for pipeline CPU with TLB and Cache support
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module tb_tlb_cache;

    // Inputs
    reg clk;
    reg resetn;
    reg [4:0] rf_addr;
    reg [31:0] mem_addr;

    // Outputs
    wire [31:0] rf_data;
    wire [31:0] mem_data;
    wire [31:0] IF_pc;
    wire [31:0] IF_inst;
    wire [31:0] ID_pc;
    wire [31:0] EXE_pc;
    wire [31:0] MEM_pc;
    wire [31:0] WB_pc;
    wire [31:0] cpu_5_valid;
    wire [31:0] HI_data;
    wire [31:0] LO_data;

    // Memory interface signals for ICache
    wire        icache_mem_req;
    wire [31:0] icache_mem_addr;
    reg  [31:0] icache_mem_rdata;
    reg         icache_mem_addr_ok;
    reg         icache_mem_data_ok;

    // Memory interface signals for DCache read
    wire        dcache_mem_rd_req;
    wire [31:0] dcache_mem_rd_addr;
    reg  [31:0] dcache_mem_rd_rdata;
    reg         dcache_mem_rd_addr_ok;
    reg         dcache_mem_rd_data_ok;

    // Memory interface signals for DCache write
    wire        dcache_mem_wr_req;
    wire [31:0] dcache_mem_wr_addr;
    wire [31:0] dcache_mem_wr_wdata;
    wire [ 3:0] dcache_mem_wr_wstrb;
    reg         dcache_mem_wr_addr_ok;
    reg         dcache_mem_wr_data_ok;

    // Instantiate the Unit Under Test (UUT)
    pipeline_cpu_tlb_cache uut (
        .clk                   (clk),
        .resetn                (resetn),
        .rf_addr               (rf_addr),
        .mem_addr              (mem_addr),
        .rf_data               (rf_data),
        .mem_data              (mem_data),
        .IF_pc                 (IF_pc),
        .IF_inst               (IF_inst),
        .ID_pc                 (ID_pc),
        .EXE_pc                (EXE_pc),
        .MEM_pc                (MEM_pc),
        .WB_pc                 (WB_pc),
        .cpu_5_valid           (cpu_5_valid),
        .HI_data               (HI_data),
        .LO_data               (LO_data),
        .icache_mem_req        (icache_mem_req),
        .icache_mem_addr       (icache_mem_addr),
        .icache_mem_rdata      (icache_mem_rdata),
        .icache_mem_addr_ok    (icache_mem_addr_ok),
        .icache_mem_data_ok    (icache_mem_data_ok),
        .dcache_mem_rd_req     (dcache_mem_rd_req),
        .dcache_mem_rd_addr    (dcache_mem_rd_addr),
        .dcache_mem_rd_rdata   (dcache_mem_rd_rdata),
        .dcache_mem_rd_addr_ok (dcache_mem_rd_addr_ok),
        .dcache_mem_rd_data_ok (dcache_mem_rd_data_ok),
        .dcache_mem_wr_req     (dcache_mem_wr_req),
        .dcache_mem_wr_addr    (dcache_mem_wr_addr),
        .dcache_mem_wr_wdata   (dcache_mem_wr_wdata),
        .dcache_mem_wr_wstrb   (dcache_mem_wr_wstrb),
        .dcache_mem_wr_addr_ok (dcache_mem_wr_addr_ok),
        .dcache_mem_wr_data_ok (dcache_mem_wr_data_ok)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Memory response simulation
    always @(posedge clk) begin
        // Simple memory response: acknowledge immediately
        icache_mem_addr_ok <= icache_mem_req;
        icache_mem_data_ok <= icache_mem_req;
        icache_mem_rdata   <= 32'h00000000;  // NOP instruction
        
        dcache_mem_rd_addr_ok <= dcache_mem_rd_req;
        dcache_mem_rd_data_ok <= dcache_mem_rd_req;
        dcache_mem_rd_rdata   <= 32'h12345678;  // Test data
        
        dcache_mem_wr_addr_ok <= dcache_mem_wr_req;
        dcache_mem_wr_data_ok <= dcache_mem_wr_req;
    end

    // Test stimulus
    initial begin
        // Initialize Inputs
        resetn = 0;
        rf_addr = 0;
        mem_addr = 0;
        icache_mem_rdata = 0;
        icache_mem_addr_ok = 0;
        icache_mem_data_ok = 0;
        dcache_mem_rd_rdata = 0;
        dcache_mem_rd_addr_ok = 0;
        dcache_mem_rd_data_ok = 0;
        dcache_mem_wr_addr_ok = 0;
        dcache_mem_wr_data_ok = 0;

        // Wait 100 ns for global reset to finish
        #100;
        resetn = 1;

        // Monitor pipeline stages
        $monitor("Time=%t IF_PC=%h ID_PC=%h EXE_PC=%h MEM_PC=%h WB_PC=%h Valid=%b",
                 $time, IF_pc, ID_pc, EXE_pc, MEM_pc, WB_pc, cpu_5_valid[19:0]);

        // Run for a while
        #2000;

        // Check some register values
        rf_addr = 5'd1;
        #10;
        $display("Register 1 = %h", rf_data);
        
        rf_addr = 5'd2;
        #10;
        $display("Register 2 = %h", rf_data);

        // Test TLB operations (via program in inst_rom)
        $display("TLB and Cache test completed");
        
        #1000;
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_tlb_cache.vcd");
        $dumpvars(0, tb_tlb_cache);
    end

endmodule
