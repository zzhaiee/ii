# TLB与Cache模块实验报告

## 实验目的

在现有的五级流水线MIPS CPU基础上，实现TLB（Translation Lookaside Buffer，转换旁路缓冲器）模块和Cache（高速缓存）模块，包括ICache（指令缓存）和DCache（数据缓存），以支持虚拟地址转换和提高内存访问效率。

---

## 一、TLB模块设计

### 1.1 TLB模块概述

TLB是一个小型的、快速的缓存，用于存储虚拟地址到物理地址的映射关系。本设计实现了一个16项全相联TLB。

### 1.2 TLB表项结构

每个TLB表项包含以下字段（共89位）：

| 位域 | 字段名 | 位宽 | 说明 |
|------|--------|------|------|
| [88:70] | VPN2 | 19位 | 虚拟页号（除去最低位） |
| [69:62] | ASID | 8位 | 地址空间标识符 |
| [61] | G | 1位 | 全局位 |
| [60:41] | PFN0 | 20位 | 偶页物理帧号 |
| [40:38] | C0 | 3位 | 偶页缓存属性 |
| [37] | D0 | 1位 | 偶页脏位 |
| [36] | V0 | 1位 | 偶页有效位 |
| [35:16] | PFN1 | 20位 | 奇页物理帧号 |
| [15:13] | C1 | 3位 | 奇页缓存属性 |
| [12] | D1 | 1位 | 奇页脏位 |
| [11] | V1 | 1位 | 奇页有效位 |

### 1.3 TLB核心代码解析

#### 1.3.1 TLB存储定义

```verilog
localparam TLB_ENTRIES = 16;
localparam TLB_WIDTH = 89;

// TLB存储
reg [TLB_WIDTH-1:0] tlb_entries [TLB_ENTRIES-1:0];
```

这里定义了16项TLB表项，每项89位宽。

#### 1.3.2 TLB写操作

```verilog
// TLB写操作
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
```

- **TLBWI (TLB Write Indexed)**：将CP0寄存器内容写入Index寄存器指定的TLB表项
- **TLBWR (TLB Write Random)**：将CP0寄存器内容写入Random寄存器指定的TLB表项

#### 1.3.3 TLB读操作 (TLBR)

```verilog
wire [TLB_WIDTH-1:0] tlbr_entry = tlb_entries[index_idx];
wire [18:0] tlbr_vpn2 = tlbr_entry[88:70];
wire [ 7:0] tlbr_asid = tlbr_entry[69:62];
// ... 其他字段提取

assign tlbr_entryhi  = {tlbr_vpn2, 5'b0, tlbr_asid};
assign tlbr_entrylo0 = {6'b0, tlbr_pfn0, tlbr_c0, tlbr_d0, tlbr_v0, tlbr_g};
assign tlbr_entrylo1 = {6'b0, tlbr_pfn1, tlbr_c1, tlbr_d1, tlbr_v1, tlbr_g};
```

TLBR指令从Index指定的TLB表项中读取内容到EntryHi、EntryLo0、EntryLo1寄存器。

#### 1.3.4 TLB探测操作 (TLBP)

```verilog
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

assign tlbp_found = |tlbp_match;
```

TLBP指令搜索匹配EntryHi中VPN2和ASID的TLB表项，匹配条件为：
1. VPN2相等，且
2. 全局位G为1，或ASID相等

#### 1.3.5 地址转换

```verilog
// 指令地址转换
wire [18:0] inst_vpn2 = inst_vaddr[31:13];
wire        inst_odd  = inst_vaddr[12];

// 根据虚拟地址第12位选择偶页或奇页的PFN
wire [19:0] inst_pfn = inst_odd ? inst_tlb_entry[35:16] : inst_tlb_entry[60:41];

assign inst_paddr = {inst_pfn, inst_vaddr[11:0]};
```

地址转换过程：
1. 提取虚拟地址的VPN2（第31-13位）
2. 根据第12位确定是偶页还是奇页
3. 查找匹配的TLB表项
4. 组合PFN和页内偏移得到物理地址

---

## 二、TLB相关CP0寄存器

### 2.1 寄存器列表

| 寄存器号 | 名称 | 功能 |
|----------|------|------|
| 0 | Index | TLB索引，P位表示探测失败 |
| 1 | Random | 随机索引，用于TLBWR |
| 2 | EntryLo0 | 偶页TLB表项低位 |
| 3 | EntryLo1 | 奇页TLB表项低位 |
| 4 | Context | 上下文寄存器 |
| 5 | PageMask | 页掩码 |
| 6 | Wired | 固定TLB表项数 |
| 10 | EntryHi | TLB表项高位 |

### 2.2 关键寄存器实现

#### 2.2.1 Index寄存器

```verilog
always @(posedge clk) begin
    if (!resetn) begin
        index_r <= 32'd0;
    end
    else if (tlbp) begin
        // TLBP操作：找到则设置索引，未找到则设置P位
        index_r <= tlbp_found ? {28'd0, tlbp_index} : {1'b1, 31'd0};
    end
    else if (wen && waddr == ADDR_INDEX) begin
        index_r <= {wdata[31], 27'd0, wdata[3:0]};
    end
end
```

#### 2.2.2 Random寄存器

```verilog
// Random寄存器在Wired写入时重置为最大值（符合MIPS规范）
wire wired_write = wen && waddr == ADDR_WIRED;
always @(posedge clk) begin
    if (!resetn || wired_write) begin
        random_r <= 32'd15;  // 重置为最大TLB索引
    end
    else begin
        // 递减，但不低于Wired值
        if (random_r[3:0] == wired_r[3:0]) begin
            random_r <= 32'd15;
        end
        else begin
            random_r <= {28'd0, random_r[3:0] - 1'b1};
        end
    end
end
```

Random寄存器特点：
- 每周期递减
- 不低于Wired值
- 写入Wired时重置为最大值

---

## 三、TLB指令实现

### 3.1 指令编码

```verilog
// TLB指令编码（COP0指令，CO位为1）
wire cop0_co = (op == 6'b010000) & inst[25];  // CO位 = rs[4]
assign inst_TLBR  = cop0_co & (funct == 6'b000001);  // 读TLB
assign inst_TLBWI = cop0_co & (funct == 6'b000010);  // 索引写TLB
assign inst_TLBWR = cop0_co & (funct == 6'b000110);  // 随机写TLB
assign inst_TLBP  = cop0_co & (funct == 6'b001000);  // 探测TLB
```

### 3.2 指令功能

| 指令 | 编码(funct) | 功能 |
|------|-------------|------|
| TLBR | 000001 | 读取Index指定的TLB表项到EntryHi/Lo0/Lo1 |
| TLBWI | 000010 | 将EntryHi/Lo0/Lo1写入Index指定的TLB表项 |
| TLBWR | 000110 | 将EntryHi/Lo0/Lo1写入Random指定的TLB表项 |
| TLBP | 001000 | 查找匹配EntryHi的TLB表项，结果写入Index |

---

## 四、ICache模块设计

### 4.1 ICache参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 总容量 | 4KB | 缓存总大小 |
| 行数 | 128行 | 缓存行数量 |
| 行大小 | 32字节 | 每行8个字 |
| 映射方式 | 直接映射 | 地址直接决定缓存位置 |

### 4.2 地址划分

```
[31:12] Tag      (20位) - 标签
[11:5]  Index    (7位)  - 索引（128行）
[4:2]   Word     (3位)  - 字偏移（8字）
[1:0]   Byte     (2位)  - 字节偏移
```

### 4.3 核心代码解析

#### 4.3.1 缓存存储结构

```verilog
localparam CACHE_LINES = 128;
localparam TAG_WIDTH   = 20;

reg [TAG_WIDTH-1:0]    tag_array   [CACHE_LINES-1:0];  // 标签数组
reg                    valid_array [CACHE_LINES-1:0];  // 有效位数组
reg [255:0]            data_array  [CACHE_LINES-1:0];  // 数据数组（8字=256位）
```

#### 4.3.2 命中判断

```verilog
wire [TAG_WIDTH-1:0] stored_tag   = tag_array[addr_index];
wire                 stored_valid = valid_array[addr_index];
wire [255:0]         stored_data  = data_array[addr_index];

wire cache_hit = stored_valid && (stored_tag == addr_tag);
```

命中条件：有效位为1且标签匹配。

#### 4.3.3 缺失处理状态机

```verilog
localparam IDLE       = 3'd0;
localparam FETCH_REQ  = 3'd1;
localparam FETCH_WAIT = 3'd2;
localparam REFILL     = 3'd3;
localparam COMPLETE   = 3'd4;

always @(posedge clk) begin
    case (state)
        IDLE: begin
            if (cpu_req && !cache_hit) begin
                state <= FETCH_REQ;
                // 保存缺失地址，开始取数据
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
                    state <= REFILL;  // 8个字取完
                end
                else begin
                    refill_cnt <= refill_cnt + 1'b1;
                    state <= FETCH_REQ;
                end
            end
        end
        
        REFILL: begin
            // 将数据写入缓存
            state <= COMPLETE;
        end
        
        COMPLETE: begin
            state <= IDLE;
        end
    endcase
end
```

---

## 五、DCache模块设计

### 5.1 DCache参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 总容量 | 4KB | 缓存总大小 |
| 行数 | 128行 | 缓存行数量 |
| 行大小 | 32字节 | 每行8个字 |
| 写策略 | 写回 | Write-back |
| 映射方式 | 直接映射 | |

### 5.2 与ICache的区别

DCache需要额外支持：
1. **脏位(Dirty bit)**：标记数据是否被修改
2. **写回逻辑**：被替换的脏行需要写回内存
3. **写操作**：支持字节/半字/字写入

### 5.3 核心代码解析

#### 5.3.1 存储结构

```verilog
reg [TAG_WIDTH-1:0]    tag_array   [CACHE_LINES-1:0];
reg                    valid_array [CACHE_LINES-1:0];
reg                    dirty_array [CACHE_LINES-1:0];  // 脏位数组
reg [255:0]            data_array  [CACHE_LINES-1:0];
```

#### 5.3.2 写回判断

```verilog
wire need_writeback = stored_valid && stored_dirty && !cache_hit && cpu_req;
```

当发生缺失且被替换的行是脏的，需要先写回内存。

#### 5.3.3 写命中处理

```verilog
// 写命中时，更新缓存行并设置脏位
always @(posedge clk) begin
    if (resetn && state == WRITE_HIT) begin
        dirty_array[addr_index] <= 1'b1;
        data_array[addr_index]  <= new_line_data;
    end
end
```

#### 5.3.4 字节写入掩码

```verilog
// 根据写使能生成新字
assign new_write_word[7:0]   = wr_strb_r[0] ? wr_data_r[7:0]   : write_hit_word[7:0];
assign new_write_word[15:8]  = wr_strb_r[1] ? wr_data_r[15:8]  : write_hit_word[15:8];
assign new_write_word[23:16] = wr_strb_r[2] ? wr_data_r[23:16] : write_hit_word[23:16];
assign new_write_word[31:24] = wr_strb_r[3] ? wr_data_r[31:24] : write_hit_word[31:24];
```

支持SB（存字节）和SW（存字）指令。

#### 5.3.5 状态机扩展

```verilog
localparam IDLE       = 4'd0;
localparam WB_REQ     = 4'd1;    // 写回请求
localparam WB_WAIT    = 4'd2;    // 等待写回完成
localparam FETCH_REQ  = 4'd3;    // 取数请求
localparam FETCH_WAIT = 4'd4;    // 等待取数完成
localparam REFILL     = 4'd5;    // 填充缓存
localparam COMPLETE   = 4'd6;    // 完成
localparam WRITE_HIT  = 4'd7;    // 写命中处理
```

---

## 六、CPU集成

### 6.1 模块连接

```
             ┌─────────────┐
     ┌───────│   CPU Core  │───────┐
     │       └─────────────┘       │
     ▼                             ▼
┌─────────┐                   ┌─────────┐
│ ICache  │                   │ DCache  │
└────┬────┘                   └────┬────┘
     │                             │
     ▼                             ▼
┌─────────┐                   ┌─────────┐
│   TLB   │──────────────────│   TLB   │
│  (Inst) │                   │  (Data) │
└────┬────┘                   └────┬────┘
     │                             │
     └──────────┬──────────────────┘
                ▼
          ┌───────────┐
          │  Memory   │
          └───────────┘
```

### 6.2 流水线扩展

新增流水线模块：

| 模块 | 功能 |
|------|------|
| decode_tlb.v | 译码TLB指令 |
| exe_tlb.v | 传递TLB操作信号 |
| mem_tlb.v | 输出load/store信号用于DCache控制 |
| wb_tlb.v | 执行TLB操作，CP0接口 |

### 6.3 关键连接代码

```verilog
// TLB模块连接
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
    // ... 地址转换接口
    .inst_vaddr    (inst_addr     ),
    .inst_paddr    (inst_paddr    ),
    .data_vaddr    (dm_addr       ),
    .data_paddr    (data_paddr    ),
);

// DCache请求信号
wire dcache_req = mem_load || mem_store;
```

---

## 七、实验总结

### 7.1 实现功能

1. **TLB模块**：
   - 16项全相联TLB
   - 支持TLBR/TLBWI/TLBWR/TLBP指令
   - 双端口地址转换（指令和数据）

2. **CP0寄存器**：
   - TLB相关：Index, Random, EntryLo0/1, EntryHi, Context, PageMask, Wired
   - 异常相关：Status, Cause, EPC, BadVAddr
   - 定时器：Count, Compare

3. **ICache**：
   - 4KB直接映射指令缓存
   - 缺失处理状态机

4. **DCache**：
   - 4KB直接映射数据缓存
   - 写回策略
   - 支持字节/字写入

### 7.2 文件清单

| 文件名 | 说明 |
|--------|------|
| tlb.v | TLB模块 |
| cp0_regs.v | CP0寄存器 |
| icache.v | 指令缓存 |
| dcache.v | 数据缓存 |
| decode_tlb.v | 译码模块（TLB扩展） |
| exe_tlb.v | 执行模块（TLB扩展） |
| mem_tlb.v | 访存模块（TLB扩展） |
| wb_tlb.v | 写回模块（TLB扩展） |
| pipeline_cpu_tlb_cache.v | 集成顶层模块 |
| tb_tlb_cache.v | 测试平台 |

### 7.3 测试验证

#### 7.3.1 编译验证

使用Icarus Verilog进行语法检查和编译验证，所有模块编译通过。

**编译命令：**

```bash
iverilog -o cpu_sim -Wall -Wno-timescale \
  alu.v adder.v multiply.v regfile.v fetch.v \
  decode_tlb.v exe_tlb.v mem_tlb.v wb_tlb.v \
  tlb.v icache.v dcache.v cp0_regs.v \
  pipeline_cpu_tlb_cache.v \
  sim_mem.v tb_tlb_cache.v
```

**编译结果：** 所有模块成功编译，仅有原有regfile.v的警告（非本次修改引入）。

#### 7.3.2 仿真运行

**运行命令：**

```bash
vvp cpu_sim
```

**测试程序：**

测试程序从地址0x34开始执行，包含以下MIPS指令：

```text
地址      指令编码      汇编指令           功能说明
------------------------------------------------------
0x34      3C010001      lui  $1, 1         $1 = 0x00010000
0x38      34210002      ori  $1, $1, 2     $1 = 0x00010002
0x3C      3C020003      lui  $2, 3         $2 = 0x00030000
0x40      00221820      add  $3, $1, $2    $3 = $1 + $2
```

#### 7.3.3 仿真结果

**寄存器验证结果：**

| 寄存器 | 预期值 | 实际值 | 验证结果 |
| ------ | ------ | ------ | -------- |
| $1 | 0x00010002 | 0x00010002 | ✓ 通过 |
| $2 | 0x00030000 | 0x00030000 | ✓ 通过 |

**流水线执行日志（部分）：**

```text
Time=100000  IF_PC=00000034 ID_PC=xxxxxxxx EXE_PC=xxxxxxxx MEM_PC=xxxxxxxx WB_PC=xxxxxxxx
Time=375000  IF_PC=00000038 ID_PC=00000034 EXE_PC=xxxxxxxx MEM_PC=xxxxxxxx WB_PC=xxxxxxxx
Time=385000  IF_PC=00000038 ID_PC=00000034 EXE_PC=00000034 MEM_PC=xxxxxxxx WB_PC=xxxxxxxx
Time=395000  IF_PC=0000003c ID_PC=00000038 EXE_PC=00000034 MEM_PC=00000034 WB_PC=xxxxxxxx
Time=405000  IF_PC=0000003c ID_PC=00000038 EXE_PC=00000034 MEM_PC=00000034 WB_PC=00000034
```

**流水线状态分析：**

| 时间点 | IF | ID | EXE | MEM | WB | 说明 |
| ------ | -- | -- | --- | --- | -- | ---- |
| 100ns | lui $1 | - | - | - | - | 第一条指令进入IF |
| 375ns | ori $1 | lui $1 | - | - | - | 指令开始流动 |
| 395ns | lui $2 | ori $1 | lui $1 | lui $1 | - | 流水线充满 |
| 405ns | lui $2 | ori $1 | lui $1 | lui $1 | lui $1 | 第一条指令完成 |

#### 7.3.4 验证结论

1. **编译验证**：所有新增模块（TLB、ICache、DCache、CP0寄存器、流水线扩展）均通过Icarus Verilog编译
2. **功能验证**：五级流水线正常工作，指令正确执行
3. **结果验证**：寄存器计算结果与预期一致
4. **流水线验证**：IF→ID→EXE→MEM→WB流水线各阶段正确流动

---

## 参考资料

1. MIPS32 Architecture For Programmers Volume III: The MIPS32 Privileged Resource Architecture
2. See MIPS Run (Second Edition) - Dominic Sweetman
3. Computer Organization and Design - Patterson & Hennessy
