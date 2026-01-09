`timescale 1ns / 1ps
//*************************************************************************
//   > File: icache.v
//   > Description: Instruction Cache module
//   > Features:
//   >   - Direct-mapped cache
//   >   - 4KB cache size (128 lines x 32 bytes/line)
//   >   - 32-byte cache line (8 words)
//   >   - Read-only cache for instructions
//*************************************************************************

module icache(
    input         clk,
    input         resetn,
    
    // CPU interface
    input         cpu_req,       // CPU request
    input  [31:0] cpu_addr,      // CPU address (physical address)
    output [31:0] cpu_rdata,     // Read data to CPU
    output        cpu_addr_ok,   // Address handshake
    output        cpu_data_ok,   // Data valid
    
    // Memory interface
    output        mem_req,       // Memory request
    output [31:0] mem_addr,      // Memory address
    input  [31:0] mem_rdata,     // Memory read data
    input         mem_addr_ok,   // Memory address acknowledge
    input         mem_data_ok,   // Memory data valid
    
    // Cache control
    input         cache_flush,   // Invalidate all cache lines
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
    // [1:0]   Byte offset (2 bits, ignored for word access)
    
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
    reg [255:0]            data_array  [CACHE_LINES-1:0];  // 8 words = 256 bits
    
    // Initialize cache on reset
    integer i;
    always @(posedge clk) begin
        if (!resetn || cache_flush) begin
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                valid_array[i] <= 1'b0;
            end
        end
    end
    
    // Cache lookup
    wire [TAG_WIDTH-1:0] stored_tag   = tag_array[addr_index];
    wire                 stored_valid = valid_array[addr_index];
    wire [255:0]         stored_data  = data_array[addr_index];
    
    wire cache_hit = stored_valid && (stored_tag == addr_tag);
    
    // State machine for cache miss handling
    localparam IDLE       = 3'd0;
    localparam FETCH_REQ  = 3'd1;
    localparam FETCH_WAIT = 3'd2;
    localparam REFILL     = 3'd3;
    localparam COMPLETE   = 3'd4;
    
    reg [2:0] state;
    reg [2:0] refill_cnt;           // Count words being refilled (0-7)
    reg [255:0] refill_data;        // Buffer for refill data
    reg [31:0] miss_addr_r;         // Saved miss address
    
    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            refill_cnt <= 3'd0;
            refill_data <= 256'd0;
            miss_addr_r <= 32'd0;
        end
        else begin
            case (state)
                IDLE: begin
                    if (cpu_req && !cache_hit) begin
                        state <= FETCH_REQ;
                        miss_addr_r <= cpu_addr;
                        refill_cnt <= 3'd0;
                        refill_data <= 256'd0;
                    end
                end
                
                FETCH_REQ: begin
                    if (mem_addr_ok) begin
                        state <= FETCH_WAIT;
                    end
                end
                
                FETCH_WAIT: begin
                    if (mem_data_ok) begin
                        refill_data[refill_cnt*32 +: 32] <= mem_rdata;
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
                    // Write refilled data to cache
                    state <= COMPLETE;
                end
                
                COMPLETE: begin
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // Write refilled data to cache arrays
    wire [INDEX_WIDTH-1:0] refill_index = miss_addr_r[11:5];
    wire [TAG_WIDTH-1:0]   refill_tag   = miss_addr_r[31:12];
    
    always @(posedge clk) begin
        if (resetn && state == REFILL) begin
            tag_array[refill_index]   <= refill_tag;
            valid_array[refill_index] <= 1'b1;
            data_array[refill_index]  <= refill_data;
        end
    end
    
    // Select word from cache line
    wire [31:0] hit_data;
    assign hit_data = stored_data[addr_word*32 +: 32];
    
    // Select word from refill data (for immediate return)
    wire [2:0] miss_word = miss_addr_r[4:2];
    wire [31:0] refill_word = refill_data[miss_word*32 +: 32];
    
    // Output logic
    assign cpu_rdata   = cache_hit ? hit_data : refill_word;
    assign cpu_addr_ok = cpu_req && (cache_hit || state == IDLE);
    assign cpu_data_ok = (cpu_req && cache_hit) || (state == COMPLETE);
    
    // Memory interface
    assign mem_req  = (state == FETCH_REQ);
    assign mem_addr = {miss_addr_r[31:5], refill_cnt, 2'b00};  // Aligned to word

endmodule
