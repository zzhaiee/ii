`timescale 1ns / 1ps
//*************************************************************************
//   > File: dcache.v
//   > Description: Data Cache module
//   > Features:
//   >   - Direct-mapped cache with write-back policy
//   >   - 4KB cache size (128 lines x 32 bytes/line)
//   >   - 32-byte cache line (8 words)
//   >   - Write-back with dirty bit tracking
//   >   - Byte/halfword/word access support
//*************************************************************************

module dcache(
    input         clk,
    input         resetn,
    
    // CPU interface
    input         cpu_req,       // CPU request
    input         cpu_wr,        // Write enable (0=read, 1=write)
    input  [ 3:0] cpu_wstrb,     // Write strobe (byte enables)
    input  [31:0] cpu_addr,      // CPU address (physical address)
    input  [31:0] cpu_wdata,     // Write data from CPU
    output [31:0] cpu_rdata,     // Read data to CPU
    output        cpu_addr_ok,   // Address handshake
    output        cpu_data_ok,   // Data valid / write complete
    
    // Memory interface (read)
    output        mem_rd_req,    // Memory read request
    output [31:0] mem_rd_addr,   // Memory read address
    input  [31:0] mem_rd_rdata,  // Memory read data
    input         mem_rd_addr_ok,// Memory read address acknowledge
    input         mem_rd_data_ok,// Memory read data valid
    
    // Memory interface (write-back)
    output        mem_wr_req,    // Memory write request
    output [31:0] mem_wr_addr,   // Memory write address
    output [31:0] mem_wr_wdata,  // Memory write data
    output [ 3:0] mem_wr_wstrb,  // Memory write strobe
    input         mem_wr_addr_ok,// Memory write address acknowledge
    input         mem_wr_data_ok,// Memory write complete
    
    // Cache control
    input         cache_flush,   // Flush and writeback all dirty lines
    input  [31:0] cache_inv_addr // Invalidate specific address (optional)
);

    // Cache parameters
    localparam CACHE_LINES = 128;       // Number of cache lines
    localparam LINE_SIZE   = 32;        // Bytes per line (8 words)
    localparam WORD_SIZE   = 4;         // Bytes per word
    localparam WORDS_PER_LINE = 8;      // Words per line
    
    // Address breakdown for 4KB cache with 32-byte lines:
    // [31:12] Tag (20 bits)
    // [11:5]  Index (7 bits, 128 lines)
    // [4:2]   Word offset (3 bits, 8 words)
    // [1:0]   Byte offset (2 bits)
    
    localparam TAG_WIDTH   = 20;
    localparam INDEX_WIDTH = 7;
    localparam OFFSET_WIDTH = 5;
    
    // Extract address fields
    wire [TAG_WIDTH-1:0]   addr_tag    = cpu_addr[31:12];
    wire [INDEX_WIDTH-1:0] addr_index  = cpu_addr[11:5];
    wire [2:0]             addr_word   = cpu_addr[4:2];
    
    // Cache storage
    reg [TAG_WIDTH-1:0]    tag_array   [CACHE_LINES-1:0];
    reg                    valid_array [CACHE_LINES-1:0];
    reg                    dirty_array [CACHE_LINES-1:0];
    reg [255:0]            data_array  [CACHE_LINES-1:0];  // 8 words = 256 bits
    
    // Initialize cache on reset
    integer i;
    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
            end
        end
    end
    
    // Cache lookup
    wire [TAG_WIDTH-1:0] stored_tag   = tag_array[addr_index];
    wire                 stored_valid = valid_array[addr_index];
    wire                 stored_dirty = dirty_array[addr_index];
    wire [255:0]         stored_data  = data_array[addr_index];
    
    wire cache_hit = stored_valid && (stored_tag == addr_tag);
    wire need_writeback = stored_valid && stored_dirty && !cache_hit && cpu_req;
    
    // State machine for cache miss/writeback handling
    localparam IDLE       = 4'd0;
    localparam WB_REQ     = 4'd1;    // Write-back request
    localparam WB_WAIT    = 4'd2;    // Write-back wait
    localparam FETCH_REQ  = 4'd3;    // Fetch request
    localparam FETCH_WAIT = 4'd4;    // Fetch wait
    localparam REFILL     = 4'd5;    // Refill cache line
    localparam COMPLETE   = 4'd6;    // Complete
    localparam WRITE_HIT  = 4'd7;    // Write hit handling
    
    reg [3:0] state;
    reg [2:0] refill_cnt;           // Count words being refilled/written back
    reg [255:0] refill_data;        // Buffer for refill data
    reg [31:0] miss_addr_r;         // Saved miss address
    reg [255:0] wb_data_r;          // Write-back data buffer
    reg [TAG_WIDTH-1:0] wb_tag_r;   // Write-back tag
    reg [INDEX_WIDTH-1:0] wb_index_r; // Write-back index
    reg        wr_pending;          // Write operation pending
    reg [31:0] wr_data_r;           // Saved write data
    reg [ 3:0] wr_strb_r;           // Saved write strobe
    
    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            refill_cnt <= 3'd0;
            refill_data <= 256'd0;
            miss_addr_r <= 32'd0;
            wb_data_r <= 256'd0;
            wb_tag_r <= {TAG_WIDTH{1'b0}};
            wb_index_r <= {INDEX_WIDTH{1'b0}};
            wr_pending <= 1'b0;
            wr_data_r <= 32'd0;
            wr_strb_r <= 4'd0;
        end
        else begin
            case (state)
                IDLE: begin
                    if (cpu_req && !cache_hit) begin
                        miss_addr_r <= cpu_addr;
                        refill_cnt <= 3'd0;
                        wr_pending <= cpu_wr;
                        wr_data_r <= cpu_wdata;
                        wr_strb_r <= cpu_wstrb;
                        
                        if (need_writeback) begin
                            // Need to write back dirty line first
                            state <= WB_REQ;
                            wb_data_r <= stored_data;
                            wb_tag_r <= stored_tag;
                            wb_index_r <= addr_index;
                        end
                        else begin
                            // No writeback needed, fetch directly
                            state <= FETCH_REQ;
                            refill_data <= 256'd0;
                        end
                    end
                    else if (cpu_req && cache_hit && cpu_wr) begin
                        // Write hit - update cache
                        state <= WRITE_HIT;
                        wr_data_r <= cpu_wdata;
                        wr_strb_r <= cpu_wstrb;
                    end
                end
                
                WB_REQ: begin
                    if (mem_wr_addr_ok) begin
                        state <= WB_WAIT;
                    end
                end
                
                WB_WAIT: begin
                    if (mem_wr_data_ok) begin
                        if (refill_cnt == 3'd7) begin
                            // Writeback complete, start fetch
                            state <= FETCH_REQ;
                            refill_cnt <= 3'd0;
                            refill_data <= 256'd0;
                        end
                        else begin
                            refill_cnt <= refill_cnt + 1'b1;
                            state <= WB_REQ;
                        end
                    end
                end
                
                FETCH_REQ: begin
                    if (mem_rd_addr_ok) begin
                        state <= FETCH_WAIT;
                    end
                end
                
                FETCH_WAIT: begin
                    if (mem_rd_data_ok) begin
                        refill_data[refill_cnt*32 +: 32] <= mem_rd_rdata;
                        if (refill_cnt == 3'd7) begin
                            state <= REFILL;
                        end
                        else begin
                            refill_cnt <= refill_cnt + 1'b1;
                            state <= FETCH_REQ;
                        end
                    end
                end
                
                REFILL: begin
                    state <= COMPLETE;
                end
                
                WRITE_HIT: begin
                    state <= COMPLETE;
                end
                
                COMPLETE: begin
                    state <= IDLE;
                    wr_pending <= 1'b0;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // Write refilled data to cache arrays
    wire [INDEX_WIDTH-1:0] refill_index = miss_addr_r[11:5];
    wire [TAG_WIDTH-1:0]   refill_tag   = miss_addr_r[31:12];
    wire [2:0]             refill_word  = miss_addr_r[4:2];
    
    // Merge write data into refill data if this was a write miss
    wire [255:0] merged_refill_data;
    wire [31:0] word_to_merge = refill_data[refill_word*32 +: 32];
    wire [31:0] merged_word;
    assign merged_word[7:0]   = wr_strb_r[0] ? wr_data_r[7:0]   : word_to_merge[7:0];
    assign merged_word[15:8]  = wr_strb_r[1] ? wr_data_r[15:8]  : word_to_merge[15:8];
    assign merged_word[23:16] = wr_strb_r[2] ? wr_data_r[23:16] : word_to_merge[23:16];
    assign merged_word[31:24] = wr_strb_r[3] ? wr_data_r[31:24] : word_to_merge[31:24];

    // Generate merged refill data
    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : merge_gen
            assign merged_refill_data[k*32 +: 32] = (k == refill_word && wr_pending) ? 
                                                    merged_word : refill_data[k*32 +: 32];
        end
    endgenerate
    
    // Update cache on refill
    always @(posedge clk) begin
        if (resetn && state == REFILL) begin
            tag_array[refill_index]   <= refill_tag;
            valid_array[refill_index] <= 1'b1;
            dirty_array[refill_index] <= wr_pending;  // Dirty if this was a write
            data_array[refill_index]  <= merged_refill_data;
        end
    end
    
    // Write hit handling
    wire [31:0] write_hit_word = stored_data[addr_word*32 +: 32];
    wire [31:0] new_write_word;
    assign new_write_word[7:0]   = wr_strb_r[0] ? wr_data_r[7:0]   : write_hit_word[7:0];
    assign new_write_word[15:8]  = wr_strb_r[1] ? wr_data_r[15:8]  : write_hit_word[15:8];
    assign new_write_word[23:16] = wr_strb_r[2] ? wr_data_r[23:16] : write_hit_word[23:16];
    assign new_write_word[31:24] = wr_strb_r[3] ? wr_data_r[31:24] : write_hit_word[31:24];
    
    // Generate new cache line data for write hit
    wire [255:0] new_line_data;
    generate
        for (k = 0; k < 8; k = k + 1) begin : write_hit_gen
            assign new_line_data[k*32 +: 32] = (k == addr_word) ? 
                                               new_write_word : stored_data[k*32 +: 32];
        end
    endgenerate
    
    // Update cache on write hit
    always @(posedge clk) begin
        if (resetn && state == WRITE_HIT) begin
            dirty_array[addr_index] <= 1'b1;
            data_array[addr_index]  <= new_line_data;
        end
    end
    
    // Select word from cache line
    wire [31:0] hit_data = stored_data[addr_word*32 +: 32];
    
    // Select word from refill data
    wire [31:0] refill_read_word = refill_data[refill_word*32 +: 32];
    
    // Output logic
    assign cpu_rdata   = cache_hit ? hit_data : refill_read_word;
    assign cpu_addr_ok = cpu_req && ((cache_hit && !cpu_wr) || 
                                     (cache_hit && cpu_wr && state == IDLE) ||
                                     (!cache_hit && state == IDLE));
    assign cpu_data_ok = (cpu_req && cache_hit && !cpu_wr) || 
                         (state == COMPLETE);
    
    // Memory read interface
    assign mem_rd_req  = (state == FETCH_REQ);
    assign mem_rd_addr = {miss_addr_r[31:5], refill_cnt, 2'b00};
    
    // Memory write interface (write-back)
    assign mem_wr_req   = (state == WB_REQ);
    assign mem_wr_addr  = {wb_tag_r, wb_index_r, refill_cnt, 2'b00};
    assign mem_wr_wdata = wb_data_r[refill_cnt*32 +: 32];
    assign mem_wr_wstrb = 4'b1111;  // Always write full word during writeback

endmodule
