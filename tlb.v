`timescale 1ns / 1ps
//*************************************************************************
//   > File: tlb.v
//   > Description: TLB (Translation Lookaside Buffer) module
//   > Features:
//   >   - 16 entries TLB
//   >   - Supports TLBR, TLBWI, TLBWR, TLBP instructions
//   >   - Dual port lookup (instruction and data)
//*************************************************************************

module tlb(
    input         clk,
    input         resetn,
    
    // TLB operation interface
    input         tlbp,        // TLB Probe
    input         tlbr,        // TLB Read
    input         tlbwi,       // TLB Write Indexed
    input         tlbwr,       // TLB Write Random
    
    // CP0 register interface
    input  [31:0] cp0_index,   // Index register
    input  [31:0] cp0_entryhi, // EntryHi register (VPN2 and ASID)
    input  [31:0] cp0_entrylo0,// EntryLo0 register (even page)
    input  [31:0] cp0_entrylo1,// EntryLo1 register (odd page)
    input  [31:0] cp0_random,  // Random register
    
    // TLB lookup results to CP0
    output        tlbp_found,      // TLBP found match
    output [ 3:0] tlbp_index,      // TLBP found index
    output [31:0] tlbr_entryhi,    // TLBR EntryHi result
    output [31:0] tlbr_entrylo0,   // TLBR EntryLo0 result
    output [31:0] tlbr_entrylo1,   // TLBR EntryLo1 result
    
    // Instruction address translation
    input  [31:0] inst_vaddr,      // Virtual address for instruction
    output        inst_tlb_hit,    // Instruction TLB hit
    output [31:0] inst_paddr,      // Physical address for instruction
    output        inst_tlb_v,      // Valid bit
    output        inst_tlb_d,      // Dirty bit
    output [ 2:0] inst_tlb_c,      // Cache attribute
    
    // Data address translation
    input  [31:0] data_vaddr,      // Virtual address for data
    output        data_tlb_hit,    // Data TLB hit
    output [31:0] data_paddr,      // Physical address for data
    output        data_tlb_v,      // Valid bit
    output        data_tlb_d,      // Dirty bit
    output [ 2:0] data_tlb_c       // Cache attribute
);

    // TLB entry format (each entry is 89 bits):
    // [88:70] VPN2 (19 bits)
    // [69:62] ASID (8 bits)
    // [61]    G (Global bit)
    // [60:41] PFN0 (20 bits)
    // [40:38] C0 (Cache attribute, 3 bits)
    // [37]    D0 (Dirty bit)
    // [36]    V0 (Valid bit)
    // [35:16] PFN1 (20 bits)
    // [15:13] C1 (Cache attribute, 3 bits)
    // [12]    D1 (Dirty bit)
    // [11]    V1 (Valid bit)
    // [10:0]  Reserved
    
    localparam TLB_ENTRIES = 16;
    localparam TLB_WIDTH = 89;
    
    // TLB storage
    reg [TLB_WIDTH-1:0] tlb_entries [TLB_ENTRIES-1:0];
    
    // Initialize TLB on reset
    integer i;
    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
                tlb_entries[i] <= {TLB_WIDTH{1'b0}};
            end
        end
    end
    
    // Extract fields from CP0 registers
    wire [18:0] entryhi_vpn2 = cp0_entryhi[31:13];
    wire [ 7:0] entryhi_asid = cp0_entryhi[7:0];
    wire [19:0] entrylo0_pfn = cp0_entrylo0[25:6];
    wire [ 2:0] entrylo0_c   = cp0_entrylo0[5:3];
    wire        entrylo0_d   = cp0_entrylo0[2];
    wire        entrylo0_v   = cp0_entrylo0[1];
    wire        entrylo0_g   = cp0_entrylo0[0];
    wire [19:0] entrylo1_pfn = cp0_entrylo1[25:6];
    wire [ 2:0] entrylo1_c   = cp0_entrylo1[5:3];
    wire        entrylo1_d   = cp0_entrylo1[2];
    wire        entrylo1_v   = cp0_entrylo1[1];
    wire        entrylo1_g   = cp0_entrylo1[0];
    
    wire [ 3:0] index_idx    = cp0_index[3:0];
    wire [ 3:0] random_idx   = cp0_random[3:0];
    
    // Construct TLB entry for write
    wire [TLB_WIDTH-1:0] tlb_write_entry = {
        entryhi_vpn2,           // [88:70] VPN2
        entryhi_asid,           // [69:62] ASID
        entrylo0_g & entrylo1_g,// [61]    G
        entrylo0_pfn,           // [60:41] PFN0
        entrylo0_c,             // [40:38] C0
        entrylo0_d,             // [37]    D0
        entrylo0_v,             // [36]    V0
        entrylo1_pfn,           // [35:16] PFN1
        entrylo1_c,             // [15:13] C1
        entrylo1_d,             // [12]    D1
        entrylo1_v,             // [11]    V1
        11'b0                   // [10:0]  Reserved
    };
    
    // TLB Write operations
    always @(posedge clk) begin
        if (resetn) begin
            if (tlbwi) begin
                tlb_entries[index_idx] <= tlb_write_entry;
            end
            else if (tlbwr) begin
                tlb_entries[random_idx] <= tlb_write_entry;
            end
        end
    end
    
    // TLB Read (TLBR)
    wire [TLB_WIDTH-1:0] tlbr_entry = tlb_entries[index_idx];
    wire [18:0] tlbr_vpn2 = tlbr_entry[88:70];
    wire [ 7:0] tlbr_asid = tlbr_entry[69:62];
    wire        tlbr_g    = tlbr_entry[61];
    wire [19:0] tlbr_pfn0 = tlbr_entry[60:41];
    wire [ 2:0] tlbr_c0   = tlbr_entry[40:38];
    wire        tlbr_d0   = tlbr_entry[37];
    wire        tlbr_v0   = tlbr_entry[36];
    wire [19:0] tlbr_pfn1 = tlbr_entry[35:16];
    wire [ 2:0] tlbr_c1   = tlbr_entry[15:13];
    wire        tlbr_d1   = tlbr_entry[12];
    wire        tlbr_v1   = tlbr_entry[11];
    
    assign tlbr_entryhi  = {tlbr_vpn2, 5'b0, tlbr_asid};
    assign tlbr_entrylo0 = {6'b0, tlbr_pfn0, tlbr_c0, tlbr_d0, tlbr_v0, tlbr_g};
    assign tlbr_entrylo1 = {6'b0, tlbr_pfn1, tlbr_c1, tlbr_d1, tlbr_v1, tlbr_g};
    
    // TLB Probe (TLBP) - search for matching entry
    wire [TLB_ENTRIES-1:0] tlbp_match;
    genvar j;
    generate
        for (j = 0; j < TLB_ENTRIES; j = j + 1) begin : tlbp_gen
            wire [18:0] entry_vpn2 = tlb_entries[j][88:70];
            wire [ 7:0] entry_asid = tlb_entries[j][69:62];
            wire        entry_g    = tlb_entries[j][61];
            
            assign tlbp_match[j] = (entry_vpn2 == entryhi_vpn2) && 
                                   (entry_g || (entry_asid == entryhi_asid));
        end
    endgenerate
    
    // Priority encoder for TLBP index
    assign tlbp_found = |tlbp_match;
    assign tlbp_index = tlbp_match[0]  ? 4'd0  :
                        tlbp_match[1]  ? 4'd1  :
                        tlbp_match[2]  ? 4'd2  :
                        tlbp_match[3]  ? 4'd3  :
                        tlbp_match[4]  ? 4'd4  :
                        tlbp_match[5]  ? 4'd5  :
                        tlbp_match[6]  ? 4'd6  :
                        tlbp_match[7]  ? 4'd7  :
                        tlbp_match[8]  ? 4'd8  :
                        tlbp_match[9]  ? 4'd9  :
                        tlbp_match[10] ? 4'd10 :
                        tlbp_match[11] ? 4'd11 :
                        tlbp_match[12] ? 4'd12 :
                        tlbp_match[13] ? 4'd13 :
                        tlbp_match[14] ? 4'd14 :
                                         4'd15;
    
    // Instruction address translation
    wire [18:0] inst_vpn2 = inst_vaddr[31:13];
    wire        inst_odd  = inst_vaddr[12];
    
    wire [TLB_ENTRIES-1:0] inst_match;
    generate
        for (j = 0; j < TLB_ENTRIES; j = j + 1) begin : inst_tlb_gen
            wire [18:0] entry_vpn2 = tlb_entries[j][88:70];
            wire [ 7:0] entry_asid = tlb_entries[j][69:62];
            wire        entry_g    = tlb_entries[j][61];
            
            assign inst_match[j] = (entry_vpn2 == inst_vpn2) && 
                                   (entry_g || (entry_asid == entryhi_asid));
        end
    endgenerate
    
    wire [ 3:0] inst_match_idx = inst_match[0]  ? 4'd0  :
                                 inst_match[1]  ? 4'd1  :
                                 inst_match[2]  ? 4'd2  :
                                 inst_match[3]  ? 4'd3  :
                                 inst_match[4]  ? 4'd4  :
                                 inst_match[5]  ? 4'd5  :
                                 inst_match[6]  ? 4'd6  :
                                 inst_match[7]  ? 4'd7  :
                                 inst_match[8]  ? 4'd8  :
                                 inst_match[9]  ? 4'd9  :
                                 inst_match[10] ? 4'd10 :
                                 inst_match[11] ? 4'd11 :
                                 inst_match[12] ? 4'd12 :
                                 inst_match[13] ? 4'd13 :
                                 inst_match[14] ? 4'd14 :
                                                  4'd15;
    
    wire [TLB_WIDTH-1:0] inst_tlb_entry = tlb_entries[inst_match_idx];
    wire [19:0] inst_pfn = inst_odd ? inst_tlb_entry[35:16] : inst_tlb_entry[60:41];
    
    assign inst_tlb_hit = |inst_match;
    assign inst_paddr   = {inst_pfn, inst_vaddr[11:0]};
    assign inst_tlb_v   = inst_odd ? inst_tlb_entry[11] : inst_tlb_entry[36];
    assign inst_tlb_d   = inst_odd ? inst_tlb_entry[12] : inst_tlb_entry[37];
    assign inst_tlb_c   = inst_odd ? inst_tlb_entry[15:13] : inst_tlb_entry[40:38];
    
    // Data address translation
    wire [18:0] data_vpn2 = data_vaddr[31:13];
    wire        data_odd  = data_vaddr[12];
    
    wire [TLB_ENTRIES-1:0] data_match;
    generate
        for (j = 0; j < TLB_ENTRIES; j = j + 1) begin : data_tlb_gen
            wire [18:0] entry_vpn2 = tlb_entries[j][88:70];
            wire [ 7:0] entry_asid = tlb_entries[j][69:62];
            wire        entry_g    = tlb_entries[j][61];
            
            assign data_match[j] = (entry_vpn2 == data_vpn2) && 
                                   (entry_g || (entry_asid == entryhi_asid));
        end
    endgenerate
    
    wire [ 3:0] data_match_idx = data_match[0]  ? 4'd0  :
                                 data_match[1]  ? 4'd1  :
                                 data_match[2]  ? 4'd2  :
                                 data_match[3]  ? 4'd3  :
                                 data_match[4]  ? 4'd4  :
                                 data_match[5]  ? 4'd5  :
                                 data_match[6]  ? 4'd6  :
                                 data_match[7]  ? 4'd7  :
                                 data_match[8]  ? 4'd8  :
                                 data_match[9]  ? 4'd9  :
                                 data_match[10] ? 4'd10 :
                                 data_match[11] ? 4'd11 :
                                 data_match[12] ? 4'd12 :
                                 data_match[13] ? 4'd13 :
                                 data_match[14] ? 4'd14 :
                                                  4'd15;
    
    wire [TLB_WIDTH-1:0] data_tlb_entry = tlb_entries[data_match_idx];
    wire [19:0] data_pfn = data_odd ? data_tlb_entry[35:16] : data_tlb_entry[60:41];
    
    assign data_tlb_hit = |data_match;
    assign data_paddr   = {data_pfn, data_vaddr[11:0]};
    assign data_tlb_v   = data_odd ? data_tlb_entry[11] : data_tlb_entry[36];
    assign data_tlb_d   = data_odd ? data_tlb_entry[12] : data_tlb_entry[37];
    assign data_tlb_c   = data_odd ? data_tlb_entry[15:13] : data_tlb_entry[40:38];

endmodule
