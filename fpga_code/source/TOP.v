// ==============================================================================
// 模块：TOP
// 描述：顶层模块，处理64个引脚的点阵拆分映射与模块互联
// ==============================================================================
module TOP (
    input  wire       clk,        // 系统时钟 (假定 50MHz)
    input  wire       rst_n,      // 异步复位，低电平有效
    input  wire [3:0] key,        // 4个独立按键输入 (按下为低电平)

    // 左上角点阵 (Matrix 1)
    output wire [7:0] mat1_anode, // 阳极 (列，高电平点亮)
    output wire [7:0] mat1_cath,  // 阴极 (行，低电平使能)
    // 右上角点阵 (Matrix 2)
    output wire [7:0] mat2_anode, 
    output wire [7:0] mat2_cath,  
    // 左下角点阵 (Matrix 3)
    output wire [7:0] mat3_anode, 
    output wire [7:0] mat3_cath,  
    // 右下角点阵 (Matrix 4)
    output wire [7:0] mat4_anode, 
    output wire [7:0] mat4_cath   
);

    wire [3:0] key_pulse; 
    wire [255:0] global_matrix_data; 

    wire CLK_100M;

    CLK_50M u_clk_0 (
    .clkin1(clk),        // input
    .pll_lock(),            // output
    .clkout0(CLK_100M)       // output
    );


    key_debounce u_key (
        .clk        (CLK_100M),
        .rst_n      (rst_n),
        .key_in     (key),
        .key_pulse  (key_pulse)
    );

    matrix_ctrl u_ctrl (
        .clk        (CLK_100M),
        .rst_n      (rst_n),
        .key_pulse  (key_pulse),
        .pixel_data (global_matrix_data)
    );

    matrix_scan u_scan (
        .clk        (CLK_100M),
        .rst_n      (rst_n),
        .pixel_data (global_matrix_data),
        
        .mat1_anode (mat1_anode), .mat1_cath (mat1_cath),
        .mat2_anode (mat2_anode), .mat2_cath (mat2_cath),
        .mat3_anode (mat3_anode), .mat3_cath (mat3_cath),
        .mat4_anode (mat4_anode), .mat4_cath (mat4_cath)
    );

endmodule
