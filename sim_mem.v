`timescale 1ns / 1ps
// Simple inst_rom for simulation (replaces Xilinx IP)
module inst_rom(
    input         clka,
    input  [7:0]  addra,
    output reg [31:0] douta
);
    reg [31:0] mem [0:255];
    integer i;
    
    initial begin
        // Initialize with NOP instructions
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 32'h00000000;  // NOP
        end
        // Sample test instructions at start address 0x34/4 = 13
        mem[13] = 32'h3C010001;  // lui $1, 1
        mem[14] = 32'h34210002;  // ori $1, $1, 2
        mem[15] = 32'h3C020003;  // lui $2, 3
        mem[16] = 32'h00221820;  // add $3, $1, $2
    end
    
    always @(posedge clka) begin
        douta <= mem[addra];
    end
endmodule

// Simple data_ram for simulation (replaces Xilinx IP)
module data_ram(
    input         clka,
    input  [3:0]  wea,
    input  [7:0]  addra,
    input  [31:0] dina,
    output reg [31:0] douta,
    input         clkb,
    input  [3:0]  web,
    input  [7:0]  addrb,
    input  [31:0] dinb,
    output reg [31:0] doutb
);
    reg [31:0] mem [0:255];
    
    // Port A
    always @(posedge clka) begin
        if (wea[0]) mem[addra][7:0]   <= dina[7:0];
        if (wea[1]) mem[addra][15:8]  <= dina[15:8];
        if (wea[2]) mem[addra][23:16] <= dina[23:16];
        if (wea[3]) mem[addra][31:24] <= dina[31:24];
        douta <= mem[addra];
    end
    
    // Port B
    always @(posedge clkb) begin
        if (web[0]) mem[addrb][7:0]   <= dinb[7:0];
        if (web[1]) mem[addrb][15:8]  <= dinb[15:8];
        if (web[2]) mem[addrb][23:16] <= dinb[23:16];
        if (web[3]) mem[addrb][31:24] <= dinb[31:24];
        doutb <= mem[addrb];
    end
endmodule
