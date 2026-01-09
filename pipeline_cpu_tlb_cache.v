`timescale 1ns / 1ps
//*************************************************************************
//   > File: pipeline_cpu_tlb_cache.v
//   > Description: 5-stage pipeline CPU with TLB and Cache support
//   > Features:
//   >   - TLB module for address translation
//   >   - ICache for instruction fetch
//   >   - DCache for data access
//   >   - TLB instructions (TLBR, TLBWI, TLBWR, TLBP)
//*************************************************************************
`define STARTADDR 32'H00000034   // Program start address

module pipeline_cpu_tlb_cache(
    input clk,
    input resetn,
    
    // Display data interface
    input  [ 4:0] rf_addr,
    input  [31:0] mem_addr,
    output [31:0] rf_data,
    output [31:0] mem_data,
    output [31:0] IF_pc,
    output [31:0] IF_inst,
    output [31:0] ID_pc,
    output [31:0] EXE_pc,
    output [31:0] MEM_pc,
    output [31:0] WB_pc,
    
    // Pipeline valid signals
    output [31:0] cpu_5_valid,
    output [31:0] HI_data,
    output [31:0] LO_data,
    
    // Memory interface for ICache miss
    output        icache_mem_req,
    output [31:0] icache_mem_addr,
    input  [31:0] icache_mem_rdata,
    input         icache_mem_addr_ok,
    input         icache_mem_data_ok,
    
    // Memory interface for DCache read
    output        dcache_mem_rd_req,
    output [31:0] dcache_mem_rd_addr,
    input  [31:0] dcache_mem_rd_rdata,
    input         dcache_mem_rd_addr_ok,
    input         dcache_mem_rd_data_ok,
    
    // Memory interface for DCache write-back
    output        dcache_mem_wr_req,
    output [31:0] dcache_mem_wr_addr,
    output [31:0] dcache_mem_wr_wdata,
    output [ 3:0] dcache_mem_wr_wstrb,
    input         dcache_mem_wr_addr_ok,
    input         dcache_mem_wr_data_ok
);

    //------------------------{Pipeline control signals}begin-------------------------//
    reg IF_valid;
    reg ID_valid;
    reg EXE_valid;
    reg MEM_valid;
    reg WB_valid;
    
    wire IF_over;
    wire ID_over;
    wire EXE_over;
    wire MEM_over;
    wire WB_over;
    
    wire IF_allow_in;
    wire ID_allow_in;
    wire EXE_allow_in;
    wire MEM_allow_in;
    wire WB_allow_in;
    
    wire cancel;
    
    // Stall signals for cache miss
    wire icache_stall;
    wire dcache_stall;
    
    assign IF_allow_in  = (IF_over & ID_allow_in) | cancel;
    assign ID_allow_in  = ~ID_valid  | (ID_over  & EXE_allow_in);
    assign EXE_allow_in = ~EXE_valid | (EXE_over & MEM_allow_in);
    assign MEM_allow_in = ~MEM_valid | (MEM_over & WB_allow_in & ~dcache_stall);
    assign WB_allow_in  = ~WB_valid  | WB_over;
    
    always @(posedge clk) begin
        if (!resetn) begin
            IF_valid <= 1'b0;
        end
        else if (!icache_stall) begin
            IF_valid <= 1'b1;
        end
    end
    
    always @(posedge clk) begin
        if (!resetn || cancel) begin
            ID_valid <= 1'b0;
        end
        else if (ID_allow_in && !icache_stall) begin
            ID_valid <= IF_over;
        end
    end
    
    always @(posedge clk) begin
        if (!resetn || cancel) begin
            EXE_valid <= 1'b0;
        end
        else if (EXE_allow_in) begin
            EXE_valid <= ID_over;
        end
    end
    
    always @(posedge clk) begin
        if (!resetn || cancel) begin
            MEM_valid <= 1'b0;
        end
        else if (MEM_allow_in) begin
            MEM_valid <= EXE_over;
        end
    end
    
    always @(posedge clk) begin
        if (!resetn || cancel) begin
            WB_valid <= 1'b0;
        end
        else if (WB_allow_in) begin
            WB_valid <= MEM_over;
        end
    end
    
    assign cpu_5_valid = {12'd0, {4{IF_valid}}, {4{ID_valid}},
                          {4{EXE_valid}}, {4{MEM_valid}}, {4{WB_valid}}};
    //-------------------------{Pipeline control signals}end--------------------------//

    //--------------------------{Pipeline buses}begin---------------------------//
    wire [ 63:0] IF_ID_bus;
    wire [178:0] ID_EXE_bus;    // Extended for TLB instructions
    wire [165:0] EXE_MEM_bus;   // Extended
    wire [129:0] MEM_WB_bus;    // Extended
    
    reg [ 63:0] IF_ID_bus_r;
    reg [178:0] ID_EXE_bus_r;
    reg [165:0] EXE_MEM_bus_r;
    reg [129:0] MEM_WB_bus_r;
    
    always @(posedge clk) begin
        if (IF_over && ID_allow_in && !icache_stall) begin
            IF_ID_bus_r <= IF_ID_bus;
        end
    end
    
    always @(posedge clk) begin
        if (ID_over && EXE_allow_in) begin
            ID_EXE_bus_r <= ID_EXE_bus;
        end
    end
    
    always @(posedge clk) begin
        if (EXE_over && MEM_allow_in) begin
            EXE_MEM_bus_r <= EXE_MEM_bus;
        end
    end    
    
    always @(posedge clk) begin
        if (MEM_over && WB_allow_in) begin
            MEM_WB_bus_r <= MEM_WB_bus;
        end
    end
    //---------------------------{Pipeline buses}end----------------------------//

    //--------------------------{Inter-module signals}begin--------------------------//
    wire [32:0] jbr_bus;    
    wire [31:0] inst_addr;
    wire [31:0] inst;
    wire [ 4:0] EXE_wdest;
    wire [ 4:0] MEM_wdest;
    wire [ 4:0] WB_wdest;
    wire [ 3:0] dm_wen;
    wire [31:0] dm_addr;
    wire [31:0] dm_wdata;
    wire [31:0] dm_rdata;
    wire [ 4:0] rs;
    wire [ 4:0] rt;   
    wire [31:0] rs_value;
    wire [31:0] rt_value;
    wire        rf_wen;
    wire [ 4:0] rf_wdest;
    wire [31:0] rf_wdata;    
    wire [32:0] exc_bus;
    
    // TLB related signals
    wire        tlbp, tlbr, tlbwi, tlbwr;
    wire        tlbp_found;
    wire [ 3:0] tlbp_index;
    wire [31:0] tlbr_entryhi;
    wire [31:0] tlbr_entrylo0;
    wire [31:0] tlbr_entrylo1;
    
    // CP0 register values
    wire [31:0] cp0_index;
    wire [31:0] cp0_entryhi;
    wire [31:0] cp0_entrylo0;
    wire [31:0] cp0_entrylo1;
    wire [31:0] cp0_status;
    wire [31:0] cp0_cause;
    wire [31:0] cp0_epc;
    wire [31:0] cp0_random;
    wire [31:0] cp0_wired;
    wire [31:0] cp0_badvaddr;
    wire [31:0] cp0_count;
    wire [31:0] cp0_compare;
    
    // CP0 write interface
    wire        cp0_wen;
    wire [ 7:0] cp0_waddr;
    wire [31:0] cp0_wdata;
    wire [ 7:0] cp0_raddr;
    wire [31:0] cp0_rdata;
    
    // TLB lookup results
    wire        inst_tlb_hit;
    wire [31:0] inst_paddr;
    wire        inst_tlb_v;
    wire        inst_tlb_d;
    wire [ 2:0] inst_tlb_c;
    wire        data_tlb_hit;
    wire [31:0] data_paddr;
    wire        data_tlb_v;
    wire        data_tlb_d;
    wire [ 2:0] data_tlb_c;
    //---------------------------{Inter-module signals}end---------------------------//

    //-------------------------{Module instantiation}begin---------------------------//
    wire next_fetch;
    assign next_fetch = IF_allow_in && !icache_stall;
    
    // Internal instruction ROM for basic operation
    wire [31:0] inst_from_rom;
    
    fetch IF_module(
        .clk       (clk       ),
        .resetn    (resetn    ),
        .IF_valid  (IF_valid  ),
        .next_fetch(next_fetch),
        .inst      (inst      ),
        .jbr_bus   (jbr_bus   ),
        .inst_addr (inst_addr ),
        .IF_over   (IF_over   ),
        .IF_ID_bus (IF_ID_bus ),
        .exc_bus   (exc_bus   ),
        .IF_pc     (IF_pc     ),
        .IF_inst   (IF_inst   )
    );

    // Decode module with TLB instruction support
    decode_tlb ID_module(
        .ID_valid   (ID_valid   ),
        .IF_ID_bus_r(IF_ID_bus_r),
        .rs_value   (rs_value   ),
        .rt_value   (rt_value   ),
        .rs         (rs         ),
        .rt         (rt         ),
        .jbr_bus    (jbr_bus    ),
        .ID_over    (ID_over    ),
        .ID_EXE_bus (ID_EXE_bus ),
        .IF_over    (IF_over    ),
        .EXE_wdest  (EXE_wdest  ),
        .MEM_wdest  (MEM_wdest  ),
        .WB_wdest   (WB_wdest   ),
        .ID_pc      (ID_pc      )
    ); 

    exe_tlb EXE_module(
        .EXE_valid   (EXE_valid   ),
        .ID_EXE_bus_r(ID_EXE_bus_r),
        .EXE_over    (EXE_over    ), 
        .EXE_MEM_bus (EXE_MEM_bus ),
        .clk         (clk         ),
        .EXE_wdest   (EXE_wdest   ),
        .EXE_pc      (EXE_pc      )
    );

    // Memory operation type signals for DCache control
    wire mem_load;
    wire mem_store;
    
    mem_tlb MEM_module(
        .clk          (clk          ),
        .MEM_valid    (MEM_valid    ),
        .EXE_MEM_bus_r(EXE_MEM_bus_r),
        .dm_rdata     (dm_rdata     ),
        .dm_addr      (dm_addr      ),
        .dm_wen       (dm_wen       ),
        .dm_wdata     (dm_wdata     ),
        .MEM_over     (MEM_over     ),
        .MEM_WB_bus   (MEM_WB_bus   ),
        .MEM_allow_in (MEM_allow_in ),
        .MEM_wdest    (MEM_wdest    ),
        .mem_load     (mem_load     ),
        .mem_store    (mem_store    ),
        .MEM_pc       (MEM_pc       )
    );          
 
    wb_tlb WB_module(
        .WB_valid     (WB_valid    ),
        .MEM_WB_bus_r (MEM_WB_bus_r),
        .rf_wen       (rf_wen      ),
        .rf_wdest     (rf_wdest    ),
        .rf_wdata     (rf_wdata    ),
        .WB_over      (WB_over     ),
        .clk          (clk         ),
        .resetn       (resetn      ),
        .exc_bus      (exc_bus     ),
        .WB_wdest     (WB_wdest    ),
        .cancel       (cancel      ),
        .WB_pc        (WB_pc       ),
        .HI_data      (HI_data     ),
        .LO_data      (LO_data     ),
        // TLB operations
        .tlbp         (tlbp        ),
        .tlbr         (tlbr        ),
        .tlbwi        (tlbwi       ),
        .tlbwr        (tlbwr       ),
        // CP0 interface
        .cp0_wen      (cp0_wen     ),
        .cp0_waddr    (cp0_waddr   ),
        .cp0_wdata    (cp0_wdata   ),
        .cp0_raddr    (cp0_raddr   ),
        .cp0_rdata    (cp0_rdata   )
    );

    // TLB Module
    tlb tlb_module(
        .clk           (clk           ),
        .resetn        (resetn        ),
        .tlbp          (tlbp          ),
        .tlbr          (tlbr          ),
        .tlbwi         (tlbwi         ),
        .tlbwr         (tlbwr         ),
        .cp0_index     (cp0_index     ),
        .cp0_entryhi   (cp0_entryhi   ),
        .cp0_entrylo0  (cp0_entrylo0  ),
        .cp0_entrylo1  (cp0_entrylo1  ),
        .cp0_random    (cp0_random    ),
        .tlbp_found    (tlbp_found    ),
        .tlbp_index    (tlbp_index    ),
        .tlbr_entryhi  (tlbr_entryhi  ),
        .tlbr_entrylo0 (tlbr_entrylo0 ),
        .tlbr_entrylo1 (tlbr_entrylo1 ),
        .inst_vaddr    (inst_addr     ),
        .inst_tlb_hit  (inst_tlb_hit  ),
        .inst_paddr    (inst_paddr    ),
        .inst_tlb_v    (inst_tlb_v    ),
        .inst_tlb_d    (inst_tlb_d    ),
        .inst_tlb_c    (inst_tlb_c    ),
        .data_vaddr    (dm_addr       ),
        .data_tlb_hit  (data_tlb_hit  ),
        .data_paddr    (data_paddr    ),
        .data_tlb_v    (data_tlb_v    ),
        .data_tlb_d    (data_tlb_d    ),
        .data_tlb_c    (data_tlb_c    )
    );
    
    // CP0 Registers Module
    cp0_regs cp0_module(
        .clk            (clk            ),
        .resetn         (resetn         ),
        .wen            (cp0_wen        ),
        .waddr          (cp0_waddr      ),
        .wdata          (cp0_wdata      ),
        .raddr          (cp0_raddr      ),
        .rdata          (cp0_rdata      ),
        .tlbp           (tlbp           ),
        .tlbr           (tlbr           ),
        .tlbwi          (tlbwi          ),
        .tlbwr          (tlbwr          ),
        .tlbp_found     (tlbp_found     ),
        .tlbp_index     (tlbp_index     ),
        .tlbr_entryhi   (tlbr_entryhi   ),
        .tlbr_entrylo0  (tlbr_entrylo0  ),
        .tlbr_entrylo1  (tlbr_entrylo1  ),
        .exc_valid      (1'b0           ),  // Simplified: no exception for now
        .exc_code       (5'd0           ),
        .exc_pc         (32'd0          ),
        .exc_badvaddr   (32'd0          ),
        .exc_bd         (1'b0           ),
        .eret           (1'b0           ),
        .cp0_index      (cp0_index      ),
        .cp0_entryhi    (cp0_entryhi    ),
        .cp0_entrylo0   (cp0_entrylo0   ),
        .cp0_entrylo1   (cp0_entrylo1   ),
        .cp0_status     (cp0_status     ),
        .cp0_cause      (cp0_cause      ),
        .cp0_epc        (cp0_epc        ),
        .cp0_random     (cp0_random     ),
        .cp0_wired      (cp0_wired      ),
        .cp0_badvaddr   (cp0_badvaddr   ),
        .cp0_count      (cp0_count      ),
        .cp0_compare    (cp0_compare    )
    );

    // ICache Module
    wire [31:0] icache_cpu_rdata;
    wire        icache_cpu_addr_ok;
    wire        icache_cpu_data_ok;
    
    icache icache_module(
        .clk           (clk           ),
        .resetn        (resetn        ),
        .cpu_req       (IF_valid      ),
        .cpu_addr      (inst_addr     ),
        .cpu_rdata     (icache_cpu_rdata),
        .cpu_addr_ok   (icache_cpu_addr_ok),
        .cpu_data_ok   (icache_cpu_data_ok),
        .mem_req       (icache_mem_req    ),
        .mem_addr      (icache_mem_addr   ),
        .mem_rdata     (icache_mem_rdata  ),
        .mem_addr_ok   (icache_mem_addr_ok),
        .mem_data_ok   (icache_mem_data_ok),
        .cache_flush   (1'b0          ),
        .cache_inv_addr(32'd0         )
    );
    
    assign icache_stall = IF_valid && !icache_cpu_data_ok;

    // DCache Module
    wire [31:0] dcache_cpu_rdata;
    wire        dcache_cpu_addr_ok;
    wire        dcache_cpu_data_ok;
    // DCache request for both load and store operations
    wire        dcache_req = mem_load || mem_store;
    
    dcache dcache_module(
        .clk           (clk              ),
        .resetn        (resetn           ),
        .cpu_req       (dcache_req       ),
        .cpu_wr        (|dm_wen          ),
        .cpu_wstrb     (dm_wen           ),
        .cpu_addr      (dm_addr          ),
        .cpu_wdata     (dm_wdata         ),
        .cpu_rdata     (dcache_cpu_rdata ),
        .cpu_addr_ok   (dcache_cpu_addr_ok),
        .cpu_data_ok   (dcache_cpu_data_ok),
        .mem_rd_req    (dcache_mem_rd_req    ),
        .mem_rd_addr   (dcache_mem_rd_addr   ),
        .mem_rd_rdata  (dcache_mem_rd_rdata  ),
        .mem_rd_addr_ok(dcache_mem_rd_addr_ok),
        .mem_rd_data_ok(dcache_mem_rd_data_ok),
        .mem_wr_req    (dcache_mem_wr_req    ),
        .mem_wr_addr   (dcache_mem_wr_addr   ),
        .mem_wr_wdata  (dcache_mem_wr_wdata  ),
        .mem_wr_wstrb  (dcache_mem_wr_wstrb  ),
        .mem_wr_addr_ok(dcache_mem_wr_addr_ok),
        .mem_wr_data_ok(dcache_mem_wr_data_ok),
        .cache_flush   (1'b0             ),
        .cache_inv_addr(32'd0            )
    );
    
    assign dcache_stall = dcache_req && !dcache_cpu_data_ok;

    // For basic testing, use inst_rom directly (without ICache for simplicity)
    inst_rom inst_rom_module(
        .clka       (clk           ),
        .addra      (inst_addr[9:2]),
        .douta      (inst_from_rom )
    );
    
    // Select instruction source: from ICache or ROM
    assign inst = inst_from_rom;  // For basic testing, use ROM directly

    regfile rf_module(
        .clk    (clk      ),
        .wen    (rf_wen   ),
        .raddr1 (rs       ),
        .raddr2 (rt       ),
        .waddr  (rf_wdest ),
        .wdata  (rf_wdata ),
        .rdata1 (rs_value ),
        .rdata2 (rt_value ),
        .test_addr(rf_addr),
        .test_data(rf_data)
    );
    
    // For basic testing, use data_ram directly (DCache for later integration)
    data_ram data_ram_module(
        .clka   (clk         ),
        .wea    (dm_wen      ),
        .addra  (dm_addr[9:2]),
        .dina   (dm_wdata    ),
        .douta  (dm_rdata    ),
        .clkb   (clk         ),
        .web    (4'd0        ),
        .addrb  (mem_addr[9:2]),
        .doutb  (mem_data    ),
        .dinb   (32'd0       )
    );
    //--------------------------{Module instantiation}end----------------------------//
endmodule
