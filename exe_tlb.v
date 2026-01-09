`timescale 1ns / 1ps
//*************************************************************************
//   > File: exe_tlb.v
//   > Description: Execute module with TLB instruction support
//*************************************************************************
module exe_tlb(
    input              EXE_valid,
    input      [178:0] ID_EXE_bus_r,
    output             EXE_over,
    output     [165:0] EXE_MEM_bus,
    
    input              clk,
    output     [  4:0] EXE_wdest,
    output     [ 31:0] EXE_pc
);

    // Extract signals from ID->EXE bus
    wire tlbr_op, tlbwi_op, tlbwr_op, tlbp_op;
    wire multiply;
    wire mthi;
    wire mtlo;
    wire [11:0] alu_control;
    wire [31:0] alu_operand1;
    wire [31:0] alu_operand2;
    wire [3:0] mem_control;
    wire [31:0] store_data;
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
            multiply,
            mthi,
            mtlo,
            alu_control,
            alu_operand1,
            alu_operand2,
            mem_control,
            store_data,
            mfhi,
            mflo,
            mtc0,
            mfc0,
            cp0r_addr,
            syscall,
            eret,
            rf_wen,
            rf_wdest,
            pc} = ID_EXE_bus_r;

    // ALU
    wire [31:0] alu_result;
    alu alu_module(
        .alu_control  (alu_control ),
        .alu_src1     (alu_operand1),
        .alu_src2     (alu_operand2),
        .alu_result   (alu_result  )
    );

    // Multiplier
    wire        mult_begin; 
    wire [63:0] product; 
    wire        mult_end;
    
    assign mult_begin = multiply & EXE_valid;
    multiply multiply_module (
        .clk       (clk       ),
        .mult_begin(mult_begin),
        .mult_op1  (alu_operand1), 
        .mult_op2  (alu_operand2),
        .product   (product   ),
        .mult_end  (mult_end  )
    );

    // EXE completion
    assign EXE_over = EXE_valid & (~multiply | mult_end);

    // EXE dest register
    assign EXE_wdest = rf_wdest & {5{EXE_valid}};

    // EXE->MEM bus
    wire [31:0] exe_result;
    wire [31:0] lo_result;
    wire        hi_write;
    wire        lo_write;
    
    assign exe_result = mthi     ? alu_operand1 :
                        mtc0     ? alu_operand2 : 
                        multiply ? product[63:32] : alu_result;
    assign lo_result  = mtlo ? alu_operand1 : product[31:0];
    assign hi_write   = multiply | mthi;
    assign lo_write   = multiply | mtlo;
    
    assign EXE_MEM_bus = {tlbr_op, tlbwi_op, tlbwr_op, tlbp_op,  // TLB ops
                          mem_control, store_data,               // load/store info
                          exe_result,                            // exe result
                          lo_result,                             // LO result
                          hi_write, lo_write,                    // HI/LO write enable
                          mfhi, mflo,                            // WB signals
                          mtc0, mfc0, cp0r_addr, syscall, eret,  // WB signals
                          rf_wen, rf_wdest,                      // WB signals
                          pc};                                   // PC

    assign EXE_pc = pc;
endmodule
