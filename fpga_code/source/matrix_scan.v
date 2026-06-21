// ==============================================================================
// 模块：matrix_scan (核心重构：共阴极行扫描映射)
// ==============================================================================
module matrix_scan (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [255:0] pixel_data,

    output reg  [7:0]   mat1_anode,
    output reg  [7:0]   mat1_cath,
    output reg  [7:0]   mat2_anode,
    output reg  [7:0]   mat2_cath,
    output reg  [7:0]   mat3_anode,
    output reg  [7:0]   mat3_cath,
    output reg  [7:0]   mat4_anode,
    output reg  [7:0]   mat4_cath
);
    // 扫描时钟分频 (50MHz -> 约 1kHz 扫描频率，确保视觉暂留且无闪烁)
    reg [15:0] scan_cnt;
    reg [3:0]  row_idx; // 0-15行扫描索引

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 16'd0;
            row_idx  <= 4'd0;
        end else begin
            if (scan_cnt == 16'd49_999) begin
                scan_cnt <= 16'd0;
                row_idx  <= row_idx + 1'b1;
            end else begin
                scan_cnt <= scan_cnt + 1'b1;
            end
        end
    end

    // 取出全局二维图像在当前正在扫描的“行”的16位一维数据
    wire [15:0] current_row_data;
    assign current_row_data = pixel_data >> (row_idx * 16);

    // 引脚拆分与驱动映射 (适配阴极行、阳极列)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mat1_anode <= 8'h00; mat1_cath <= 8'hFF;
            mat2_anode <= 8'h00; mat2_cath <= 8'hFF;
            mat3_anode <= 8'h00; mat3_cath <= 8'hFF;
            mat4_anode <= 8'h00; mat4_cath <= 8'hFF;
        end else begin
            // 默认全部关闭：阳极全灭(0)，阴极全失能(1)
            mat1_anode <= 8'h00; mat1_cath <= 8'hFF;
            mat2_anode <= 8'h00; mat2_cath <= 8'hFF;
            mat3_anode <= 8'h00; mat3_cath <= 8'hFF;
            mat4_anode <= 8'h00; mat4_cath <= 8'hFF;

            if (row_idx < 4'd8) begin
                // 当前正在扫描上半屏：激活 Matrix 1 & Matrix 2 的阴极行
                mat1_cath  <= ~(8'h01 << row_idx);       // 阴极低电平选中当前行
                mat2_cath  <= ~(8'h01 << row_idx);
                mat1_anode <= current_row_data[7:0];     // 左半边阳极列对应数据 0~7
                mat2_anode <= current_row_data[15:8];    // 右半边阳极列对应数据 8~15
            end else begin
                // 当前正在扫描下半屏：激活 Matrix 3 & Matrix 4 的阴极行
                mat3_cath  <= ~(8'h01 << (row_idx - 4'd8));
                mat4_cath  <= ~(8'h01 << (row_idx - 4'd8));
                mat3_anode <= current_row_data[7:0];     
                mat4_anode <= current_row_data[15:8];    
            end
        end
    end
endmodule