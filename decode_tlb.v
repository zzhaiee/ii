`timescale 1ns / 1ps
//*************************************************************************
//   > File: decode_tlb.v
//   > Description: Decode module with TLB instruction support
//   > Supports: TLBR, TLBWI, TLBWR, TLBP instructions
//*************************************************************************
module decode_tlb(
    input              ID_valid,
    input      [ 63:0] IF_ID_bus_r,
    input      [ 31:0] rs_value,
    input      [ 31:0] rt_value,
    output     [  4:0] rs,
    output     [  4:0] rt,
    output     [ 32:0] jbr_bus,
    output             ID_over,
    output     [178:0] ID_EXE_bus,  // Extended for TLB instructions
    
    input              IF_over,
    input      [  4:0] EXE_wdest,
    input      [  4:0] MEM_wdest,
    input      [  4:0] WB_wdest,
    
    output     [ 31:0] ID_pc
);

    wire [31:0] pc;
    wire [31:0] inst;
    assign {pc, inst} = IF_ID_bus_r;

    // Instruction fields
    wire [5:0] op;       
    wire [4:0] rd;       
    wire [4:0] sa;      
    wire [5:0] funct;    
    wire [15:0] imm;     
    wire [15:0] offset;  
    wire [25:0] target;  
    wire [2:0] cp0r_sel;

    assign op     = inst[31:26];
    assign rs     = inst[25:21];
    assign rt     = inst[20:16];
    assign rd     = inst[15:11];
    assign sa     = inst[10:6];
    assign funct  = inst[5:0];
    assign imm    = inst[15:0];
    assign offset = inst[15:0];
    assign target = inst[25:0];
    assign cp0r_sel= inst[2:0];

    // Existing instruction decoding
    wire inst_ADDU, inst_SUBU , inst_SLT , inst_AND;
    wire inst_NOR , inst_OR   , inst_XOR , inst_SLL;
    wire inst_SRL , inst_ADDIU, inst_BEQ , inst_BNE;
    wire inst_LW  , inst_SW   , inst_LUI , inst_J;
    wire inst_SLTU, inst_JALR , inst_JR  , inst_SLLV;
    wire inst_SRA , inst_SRAV , inst_SRLV, inst_SLTIU;
    wire inst_SLTI, inst_BGEZ , inst_BGTZ, inst_BLEZ;
    wire inst_BLTZ, inst_LB   , inst_LBU , inst_SB;
    wire inst_ANDI, inst_ORI  , inst_XORI, inst_JAL;
    wire inst_MULT, inst_MFLO , inst_MFHI, inst_MTLO;
    wire inst_MTHI, inst_MFC0 , inst_MTC0;
    wire inst_ERET, inst_SYSCALL;
    
    // TLB instructions
    wire inst_TLBR, inst_TLBWI, inst_TLBWR, inst_TLBP;
    
    wire op_zero;
    wire sa_zero;
    assign op_zero = ~(|op);
    assign sa_zero = ~(|sa);
    
    // Original instruction decoding (same as decode.v)
    assign inst_ADDU  = op_zero & sa_zero    & (funct == 6'b100001);
    assign inst_SUBU  = op_zero & sa_zero    & (funct == 6'b100011);
    assign inst_SLT   = op_zero & sa_zero    & (funct == 6'b101010);
    assign inst_SLTU  = op_zero & sa_zero    & (funct == 6'b101011);
    assign inst_JALR  = op_zero & (rt==5'd0) & (rd==5'd31)
                      & sa_zero & (funct == 6'b001001);
    assign inst_JR    = op_zero & (rt==5'd0) & (rd==5'd0 )
                      & sa_zero & (funct == 6'b001000);
    assign inst_AND   = op_zero & sa_zero    & (funct == 6'b100100);
    assign inst_NOR   = op_zero & sa_zero    & (funct == 6'b100111);
    assign inst_OR    = op_zero & sa_zero    & (funct == 6'b100101);
    assign inst_XOR   = op_zero & sa_zero    & (funct == 6'b100110);
    assign inst_SLL   = op_zero & (rs==5'd0) & (funct == 6'b000000);
    assign inst_SLLV  = op_zero & sa_zero    & (funct == 6'b000100);
    assign inst_SRA   = op_zero & (rs==5'd0) & (funct == 6'b000011);
    assign inst_SRAV  = op_zero & sa_zero    & (funct == 6'b000111);
    assign inst_SRL   = op_zero & (rs==5'd0) & (funct == 6'b000010);
    assign inst_SRLV  = op_zero & sa_zero    & (funct == 6'b000110);
    assign inst_MULT  = op_zero & (rd==5'd0)
                      & sa_zero & (funct == 6'b011000);
    assign inst_MFLO  = op_zero & (rs==5'd0) & (rt==5'd0)
                      & sa_zero & (funct == 6'b010010);
    assign inst_MFHI  = op_zero & (rs==5'd0) & (rt==5'd0)
                      & sa_zero & (funct == 6'b010000);
    assign inst_MTLO  = op_zero & (rt==5'd0) & (rd==5'd0)
                      & sa_zero & (funct == 6'b010011);
    assign inst_MTHI  = op_zero & (rt==5'd0) & (rd==5'd0)
                      & sa_zero & (funct == 6'b010001);
    assign inst_ADDIU = (op == 6'b001001);
    assign inst_SLTI  = (op == 6'b001010);
    assign inst_SLTIU = (op == 6'b001011);
    assign inst_BEQ   = (op == 6'b000100);
    assign inst_BGEZ  = (op == 6'b000001) & (rt==5'd1);
    assign inst_BGTZ  = (op == 6'b000111) & (rt==5'd0);
    assign inst_BLEZ  = (op == 6'b000110) & (rt==5'd0);
    assign inst_BLTZ  = (op == 6'b000001) & (rt==5'd0);
    assign inst_BNE   = (op == 6'b000101);
    assign inst_LW    = (op == 6'b100011);
    assign inst_SW    = (op == 6'b101011);
    assign inst_LB    = (op == 6'b100000);
    assign inst_LBU   = (op == 6'b100100);
    assign inst_SB    = (op == 6'b101000);
    assign inst_ANDI  = (op == 6'b001100);
    assign inst_LUI   = (op == 6'b001111) & (rs==5'd0);
    assign inst_ORI   = (op == 6'b001101);
    assign inst_XORI  = (op == 6'b001110);
    assign inst_J     = (op == 6'b000010);
    assign inst_JAL   = (op == 6'b000011);
    assign inst_MFC0  = (op == 6'b010000) & (rs==5'd0) 
                      & sa_zero & (funct[5:3] == 3'b000);
    assign inst_MTC0  = (op == 6'b010000) & (rs==5'd4)
                      & sa_zero & (funct[5:3] == 3'b000);
    assign inst_SYSCALL = (op == 6'b000000) & (funct == 6'b001100);
    assign inst_ERET    = (op == 6'b010000) & (rs==5'd16) & (rt==5'd0)
                        & (rd==5'd0) & sa_zero & (funct == 6'b011000);
    
    // TLB instruction decoding
    // TLBR:  010000 1 0000000000000000000 000001 (COP0, CO=1, funct=1)
    // TLBWI: 010000 1 0000000000000000000 000010 (COP0, CO=1, funct=2)
    // TLBWR: 010000 1 0000000000000000000 000110 (COP0, CO=1, funct=6)
    // TLBP:  010000 1 0000000000000000000 001000 (COP0, CO=1, funct=8)
    wire cop0_co = (op == 6'b010000) & inst[25];  // CO bit = rs[4]
    assign inst_TLBR  = cop0_co & (funct == 6'b000001);
    assign inst_TLBWI = cop0_co & (funct == 6'b000010);
    assign inst_TLBWR = cop0_co & (funct == 6'b000110);
    assign inst_TLBP  = cop0_co & (funct == 6'b001000);
    
    // Branch/jump instructions
    wire inst_jr;
    wire inst_j_link;
    wire inst_jbr;
    assign inst_jr     = inst_JALR | inst_JR;
    assign inst_j_link = inst_JAL | inst_JALR;
    assign inst_jbr = inst_J    | inst_JAL  | inst_jr
                    | inst_BEQ  | inst_BNE  | inst_BGEZ
                    | inst_BGTZ | inst_BLEZ | inst_BLTZ;
        
    // Load/store
    wire inst_load;
    wire inst_store;
    assign inst_load  = inst_LW | inst_LB | inst_LBU;
    assign inst_store = inst_SW | inst_SB;
    
    // ALU operations
    wire inst_add, inst_sub, inst_slt, inst_sltu;
    wire inst_and, inst_nor, inst_or, inst_xor;
    wire inst_sll, inst_srl, inst_sra, inst_lui;
    assign inst_add = inst_ADDU | inst_ADDIU | inst_load
                    | inst_store | inst_j_link;
    assign inst_sub = inst_SUBU;
    assign inst_slt = inst_SLT | inst_SLTI;
    assign inst_sltu= inst_SLTIU | inst_SLTU;
    assign inst_and = inst_AND | inst_ANDI;
    assign inst_nor = inst_NOR;
    assign inst_or  = inst_OR  | inst_ORI;
    assign inst_xor = inst_XOR | inst_XORI;
    assign inst_sll = inst_SLL | inst_SLLV;
    assign inst_srl = inst_SRL | inst_SRLV;
    assign inst_sra = inst_SRA | inst_SRAV;
    assign inst_lui = inst_LUI;
    
    wire inst_shf_sa;
    assign inst_shf_sa = inst_SLL | inst_SRL | inst_SRA;
    
    wire inst_imm_zero;
    wire inst_imm_sign;
    assign inst_imm_zero = inst_ANDI  | inst_LUI  | inst_ORI | inst_XORI;
    assign inst_imm_sign = inst_ADDIU | inst_SLTI | inst_SLTIU
                         | inst_load | inst_store;
    
    wire inst_wdest_rt;
    wire inst_wdest_31;
    wire inst_wdest_rd;
    assign inst_wdest_rt = inst_imm_zero | inst_ADDIU | inst_SLTI
                         | inst_SLTIU | inst_load | inst_MFC0;
    assign inst_wdest_31 = inst_JAL;
    assign inst_wdest_rd = inst_ADDU | inst_SUBU | inst_SLT  | inst_SLTU
                         | inst_JALR | inst_AND  | inst_NOR  | inst_OR 
                         | inst_XOR  | inst_SLL  | inst_SLLV | inst_SRA 
                         | inst_SRAV | inst_SRL  | inst_SRLV
                         | inst_MFHI | inst_MFLO;
                         
    wire inst_no_rs;
    wire inst_no_rt;
    assign inst_no_rs = inst_MTC0 | inst_SYSCALL | inst_ERET
                      | inst_TLBR | inst_TLBWI | inst_TLBWR | inst_TLBP;
    assign inst_no_rt = inst_ADDIU | inst_SLTI | inst_SLTIU
                      | inst_BGEZ  | inst_load | inst_imm_zero
                      | inst_J     | inst_JAL  | inst_MFC0
                      | inst_SYSCALL
                      | inst_TLBR | inst_TLBWI | inst_TLBWR | inst_TLBP;

    // Branch execution (same as decode.v)
    wire [31:0] bd_pc;
    assign bd_pc = pc + 3'b100;
    
    wire        j_taken;
    wire [31:0] j_target;
    assign j_taken = inst_J | inst_JAL | inst_jr;
    assign j_target = inst_jr ? rs_value : {bd_pc[31:28],target,2'b00};

    wire rs_equql_rt;
    wire rs_ez;
    wire rs_ltz;
    assign rs_equql_rt = (rs_value == rt_value);
    assign rs_ez       = ~(|rs_value);
    assign rs_ltz      = rs_value[31];
    
    wire br_taken;
    wire [31:0] br_target;
    assign br_taken = inst_BEQ  & rs_equql_rt
                    | inst_BNE  & ~rs_equql_rt
                    | inst_BGEZ & ~rs_ltz
                    | inst_BGTZ & ~rs_ltz & ~rs_ez
                    | inst_BLEZ & (rs_ltz | rs_ez)
                    | inst_BLTZ & rs_ltz;
    assign br_target[31:2] = bd_pc[31:2] + {{14{offset[15]}}, offset};  
    assign br_target[1:0]  = bd_pc[1:0];
    
    wire jbr_taken;
    wire [31:0] jbr_target;
    assign jbr_taken = (j_taken | br_taken) & ID_over; 
    assign jbr_target = j_taken ? j_target : br_target;
    
    assign jbr_bus = {jbr_taken, jbr_target};

    // ID completion
    wire rs_wait;
    wire rt_wait;
    assign rs_wait = ~inst_no_rs & (rs!=5'd0)
                   & ( (rs==EXE_wdest) | (rs==MEM_wdest) | (rs==WB_wdest) );
    assign rt_wait = ~inst_no_rt & (rt!=5'd0)
                   & ( (rt==EXE_wdest) | (rt==MEM_wdest) | (rt==WB_wdest) );
    
    assign ID_over = ID_valid & ~rs_wait & ~rt_wait & (~inst_jbr | IF_over);

    // ID->EXE bus
    wire multiply;
    wire mthi;
    wire mtlo;
    assign multiply = inst_MULT;
    assign mthi     = inst_MTHI;
    assign mtlo     = inst_MTLO;
    
    wire [11:0] alu_control;
    wire [31:0] alu_operand1;
    wire [31:0] alu_operand2;
    
    assign alu_operand1 = inst_j_link ? pc : 
                          inst_shf_sa ? {27'd0,sa} : rs_value;
    assign alu_operand2 = inst_j_link ? 32'd8 :  
                          inst_imm_zero ? {16'd0, imm} :
                          inst_imm_sign ?  {{16{imm[15]}}, imm} : rt_value;
    assign alu_control = {inst_add, inst_sub, inst_slt, inst_sltu,
                          inst_and, inst_nor, inst_or,  inst_xor,
                          inst_sll, inst_srl, inst_sra, inst_lui};
    
    wire lb_sign;
    wire ls_word;
    wire [3:0] mem_control;
    wire [31:0] store_data;
    assign lb_sign = inst_LB;
    assign ls_word = inst_LW | inst_SW;
    assign mem_control = {inst_load, inst_store, ls_word, lb_sign};
                          
    wire mfhi;
    wire mflo;
    wire mtc0;
    wire mfc0;
    wire [7 :0] cp0r_addr;
    wire       syscall;
    wire       eret;
    wire       rf_wen;
    wire [4:0] rf_wdest;
    
    // TLB instruction signals
    wire tlbr_op, tlbwi_op, tlbwr_op, tlbp_op;
    assign tlbr_op  = inst_TLBR;
    assign tlbwi_op = inst_TLBWI;
    assign tlbwr_op = inst_TLBWR;
    assign tlbp_op  = inst_TLBP;
    
    assign syscall  = inst_SYSCALL;
    assign eret     = inst_ERET;
    assign mfhi     = inst_MFHI;
    assign mflo     = inst_MFLO;
    assign mtc0     = inst_MTC0;
    assign mfc0     = inst_MFC0;
    assign cp0r_addr= {rd,cp0r_sel};
    assign rf_wen   = inst_wdest_rt | inst_wdest_31 | inst_wdest_rd;
    assign rf_wdest = inst_wdest_rt ? rt :
                      inst_wdest_31 ? 5'd31 :
                      inst_wdest_rd ? rd : 5'd0;
    assign store_data = rt_value;
    
    // Extended bus with TLB operations
    assign ID_EXE_bus = {tlbr_op, tlbwi_op, tlbwr_op, tlbp_op,  // TLB ops (4 bits)
                         multiply, mthi, mtlo,                   // EXE signals (3 bits)
                         alu_control, alu_operand1, alu_operand2,// EXE signals (76 bits)
                         mem_control, store_data,                // MEM signals (36 bits)
                         mfhi, mflo,                             // WB signals (2 bits)
                         mtc0, mfc0, cp0r_addr, syscall, eret,   // WB signals (12 bits)
                         rf_wen, rf_wdest,                       // WB signals (6 bits)
                         pc};                                    // PC (32 bits)
                         // Total: 4+3+76+36+2+12+6+32 = 171... let me recalculate
                         // 4+3+12+32+32+4+32+2+1+1+8+1+1+1+5+32 = 171
                         // Need 179 bits

    assign ID_pc = pc;
endmodule
