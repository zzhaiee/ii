`timescale 1ns / 1ps
//*************************************************************************
//   > File: mem_tlb.v
//   > Description: Memory stage module with TLB instruction support
//*************************************************************************
module mem_tlb(
    input              clk,
    input              MEM_valid,
    input      [165:0] EXE_MEM_bus_r,
    input      [ 31:0] dm_rdata,
    output     [ 31:0] dm_addr,
    output reg [  3:0] dm_wen,
    output reg [ 31:0] dm_wdata,
    output             MEM_over,
    output     [129:0] MEM_WB_bus,
    
    input              MEM_allow_in,
    output     [  4:0] MEM_wdest,
    
    // Memory operation type for DCache control
    output             mem_load,     // Load operation flag
    output             mem_store,    // Store operation flag
     
    output     [ 31:0] MEM_pc
);

    // Extract signals from EXE->MEM bus
    wire tlbr_op, tlbwi_op, tlbwr_op, tlbp_op;
    wire [3:0] mem_control;
    wire [31:0] store_data;
    wire [31:0] exe_result;
    wire [31:0] lo_result;
    wire        hi_write;
    wire        lo_write;
    wire mfhi;
    wire mflo;
    wire mtc0;
    wire mfc0;
    wire [7:0] cp0r_addr;
    wire syscall;
    wire eret;
    wire rf_wen;
    wire [4:0] rf_wdest;
    wire [31:0] pc;
    
    assign {tlbr_op,
            tlbwi_op,
            tlbwr_op,
            tlbp_op,
            mem_control,
            store_data,
            exe_result,
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
            rf_wen,
            rf_wdest,
            pc} = EXE_MEM_bus_r;

    // Memory control
    wire inst_load;
    wire inst_store;
    wire ls_word;
    wire lb_sign;
    assign {inst_load, inst_store, ls_word, lb_sign} = mem_control;
    
    // Output load/store signals for DCache control
    assign mem_load  = inst_load & MEM_valid;
    assign mem_store = inst_store & MEM_valid;

    // Memory address
    assign dm_addr = exe_result;
    
    // Store write enable
    always @(*) begin
        if (MEM_valid && inst_store) begin
            if (ls_word) begin
                dm_wen <= 4'b1111;
            end
            else begin
                case (dm_addr[1:0])
                    2'b00   : dm_wen <= 4'b0001;
                    2'b01   : dm_wen <= 4'b0010;
                    2'b10   : dm_wen <= 4'b0100;
                    2'b11   : dm_wen <= 4'b1000;
                    default : dm_wen <= 4'b0000;
                endcase
            end
        end
        else begin
            dm_wen <= 4'b0000;
        end
    end 
    
    // Store write data
    always @(*) begin
        case (dm_addr[1:0])
            2'b00   : dm_wdata <= store_data;
            2'b01   : dm_wdata <= {16'd0, store_data[7:0], 8'd0};
            2'b10   : dm_wdata <= {8'd0, store_data[7:0], 16'd0};
            2'b11   : dm_wdata <= {store_data[7:0], 24'd0};
            default : dm_wdata <= store_data;
        endcase
    end
    
    // Load result processing
    wire        load_sign;
    wire [31:0] load_result;
    assign load_sign = (dm_addr[1:0]==2'd0) ? dm_rdata[ 7] :
                       (dm_addr[1:0]==2'd1) ? dm_rdata[15] :
                       (dm_addr[1:0]==2'd2) ? dm_rdata[23] : dm_rdata[31];
    assign load_result[7:0] = (dm_addr[1:0]==2'd0) ? dm_rdata[ 7:0 ] :
                              (dm_addr[1:0]==2'd1) ? dm_rdata[15:8 ] :
                              (dm_addr[1:0]==2'd2) ? dm_rdata[23:16] :
                                                     dm_rdata[31:24];
    assign load_result[31:8] = ls_word ? dm_rdata[31:8] : {24{lb_sign & load_sign}};

    // MEM completion
    reg MEM_valid_r;
    always @(posedge clk) begin
        if (MEM_allow_in) begin
            MEM_valid_r <= 1'b0;
        end
        else begin
            MEM_valid_r <= MEM_valid;
        end
    end
    assign MEM_over = inst_load ? MEM_valid_r : MEM_valid;

    // MEM dest register
    assign MEM_wdest = rf_wdest & {5{MEM_valid}};

    // MEM->WB bus
    wire [31:0] mem_result;
    assign mem_result = inst_load ? load_result : exe_result;
    
    assign MEM_WB_bus = {tlbr_op, tlbwi_op, tlbwr_op, tlbp_op,  // TLB ops
                         rf_wen, rf_wdest,                      // WB signals
                         mem_result,                            // result
                         lo_result,                             // LO result
                         hi_write, lo_write,                    // HI/LO write enable
                         mfhi, mflo,                            // WB signals
                         mtc0, mfc0, cp0r_addr, syscall, eret,  // WB signals
                         pc};                                   // PC

    assign MEM_pc = pc;
endmodule
