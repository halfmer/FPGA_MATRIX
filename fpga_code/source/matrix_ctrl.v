// ==============================================================================
// 模块：matrix_ctrl (图形生成器 - PDS综合极速优化版)
// ==============================================================================
module matrix_ctrl (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [3:0]   key_pulse,
    output reg  [255:0] pixel_data
);
    // 状态定义
    reg [1:0] shape_mode; 
    reg [2:0] arrow_dir;  
    reg [1:0] anim_mode;  

// ==========================================================================
    // 精准动画定时器 (适配 100MHz 系统时钟)
    // 目标：圆形2秒画完，箭头3秒画完
    // 100MHz 下，1秒 = 100,000,000 个时钟周期
    // - 圆形需 36 步(1秒)画完：100,000,000 / 36 ≈ 2,777,778 个周期/步
    // - 箭头需 16 步(2秒)画完：200,000,000 / 16 = 12,500,000 个周期/步
    // - 圆形 (36步/2秒) ：200,000,000 / 36 ≈ 5,555,556 周期/步
    // - 箭头 (16步/3秒) ：300,000,000 / 16 = 18,750,000 周期/步
    // [致命Bug修正]：18,750,000 超过了原来22位的极限，必须扩宽为25位！
    // ==========================================================================
    wire [27:0] anim_max_cnt = (shape_mode == 2'd1) ? 28'd5_555_556 : 28'd12_500_000;
    
    // 计数器必须同步扩宽至28位，否则高位永远无法到达
    reg [27:0] anim_timer;
    wire anim_tick = (anim_timer >= anim_max_cnt);
    reg [5:0] anim_step;

    // 1. 按键逻辑与状态转移
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shape_mode <= 2'd0;
            arrow_dir  <= 3'd0;
            anim_mode  <= 2'd0;
            anim_step  <= 6'd0;
        end else begin
            // [模式切换逻辑]：静态与动态状态锁定，直到被新按键打破
            if (key_pulse[0]) begin
                shape_mode <= 2'd0; 
                anim_mode  <= 2'd0; 
            end 
            else if (key_pulse[1]) begin
                shape_mode <= 2'd1; 
                anim_mode  <= 2'd0; 
                anim_step  <= 6'd0;
            end
            else if (key_pulse[2]) begin
                if (shape_mode == 2'd2) begin
                    arrow_dir <= arrow_dir + 1'b1; 
                end else begin
                    shape_mode <= 2'd2; 
                    arrow_dir  <= 3'd0;
                end
                anim_mode <= 2'd0; 
                anim_step <= 6'd0;
            end
            else if (key_pulse[3]) begin
                anim_step <= 6'd0; 
                if (shape_mode == 2'd1) begin
                    anim_mode <= (anim_mode == 2'd2) ? 2'd0 : anim_mode + 1'b1;
                end else if (shape_mode == 2'd2) begin
                    anim_mode <= (anim_mode == 2'd1) ? 2'd0 : 2'd1;
                end
            end

            // [动态无限循环逻辑]：当处于动态模式且计时到达时，更新步数
            if (anim_mode != 2'd0 && anim_tick) begin
                if (shape_mode == 2'd1) begin
                    // 圆形：0~35 循环播放，>= 35时直接归零，不再锁死
                    if (anim_step >= 6'd35) 
                        anim_step <= 6'd0; 
                    else 
                        anim_step <= anim_step + 1'b1;
                end else if (shape_mode == 2'd2) begin
                    // 箭头：0~15 循环播放，>= 15时直接归零，不再锁死
                    if (anim_step >= 6'd15) 
                        anim_step <= 6'd0; 
                    else 
                        anim_step <= anim_step + 1'b1;
                end
            end
        end
    end

    // 动画定时计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            anim_timer <= 28'd0;
        // 任意按键按下，或者单次动画步长结束时，计数器清零重新开始
        else if (anim_tick || key_pulse[0] || key_pulse[1] || key_pulse[2] || key_pulse[3]) 
            anim_timer <= 28'd0;
        // 只有在动态模式下才启动计时，节能且防越界
        else if (anim_mode != 2'd0) 
            anim_timer <= anim_timer + 1'b1;
    end

// ---------------------------------------------------------
    // 2. 高效二维渲染引擎 (所见即所得 ROM 字库重构版)
    // ---------------------------------------------------------
    // 架构说明：直接采用常量数组(LUT)定义图形，彻底消除加减乘除组合逻辑。
    // 视觉映射：以下 16'b 二进制字符串中，左侧(最高位)对应物理屏幕的最左侧列(x=0)。
    // 1 代表 LED 亮，0 代表 LED 灭。可以直接在代码里“画图”。

    reg [4:0] x, y;
    reg show_mask;

    // 图层缓存
    reg [255:0] f_img;
    reg [255:0] circle_img;
    reg [255:0] arrow_img;
    reg [255:0] next_pixel;

    // ==================== 字库定义区 ====================
    wire [15:0] ROM_F [0:15];
    assign ROM_F[ 0] = 16'b0000_0000_0000_0000;
    assign ROM_F[ 1] = 16'b0001_1111_1111_1000;
    assign ROM_F[ 2] = 16'b0001_1111_1111_1000;
    assign ROM_F[ 3] = 16'b0001_1100_0000_0000;
    assign ROM_F[ 4] = 16'b0001_1100_0000_0000;
    assign ROM_F[ 5] = 16'b0001_1100_0000_0000;
    assign ROM_F[ 6] = 16'b0001_1111_1100_0000;
    assign ROM_F[ 7] = 16'b0001_1111_1100_0000;
    assign ROM_F[ 8] = 16'b0001_1100_0000_0000;
    assign ROM_F[ 9] = 16'b0001_1100_0000_0000;
    assign ROM_F[10] = 16'b0001_1100_0000_0000;
    assign ROM_F[11] = 16'b0001_1100_0000_0000;
    assign ROM_F[12] = 16'b0001_1100_0000_0000;
    assign ROM_F[13] = 16'b0001_1100_0000_0000;
    assign ROM_F[14] = 16'b0000_0000_0000_0000;
    assign ROM_F[15] = 16'b0000_0000_0000_0000;

    wire [15:0] ROM_CIRCLE [0:15];
    assign ROM_CIRCLE[ 0] = 16'b0000_0000_0000_0000;
    assign ROM_CIRCLE[ 1] = 16'b0000_0011_1100_0000;
    assign ROM_CIRCLE[ 2] = 16'b0001_1100_0011_1000;
    assign ROM_CIRCLE[ 3] = 16'b0011_0000_0000_1100;
    assign ROM_CIRCLE[ 4] = 16'b0010_0000_0000_0100;
    assign ROM_CIRCLE[ 5] = 16'b0010_0000_0000_0100;
    assign ROM_CIRCLE[ 6] = 16'b0100_0000_0000_0010;
    assign ROM_CIRCLE[ 7] = 16'b0100_0000_0000_0010;
    assign ROM_CIRCLE[ 8] = 16'b0100_0000_0000_0010;
    assign ROM_CIRCLE[ 9] = 16'b0100_0000_0000_0010;
    assign ROM_CIRCLE[10] = 16'b0010_0000_0000_0100;
    assign ROM_CIRCLE[11] = 16'b0010_0000_0000_0100;
    assign ROM_CIRCLE[12] = 16'b0011_0000_0000_1100;
    assign ROM_CIRCLE[13] = 16'b0001_1100_0011_1000;
    assign ROM_CIRCLE[14] = 16'b0000_0011_1100_0000;
    assign ROM_CIRCLE[15] = 16'b0000_0000_0000_0000;

    wire [15:0] ROM_ARROW [0:7][0:15];
    // 0: 向上 (UP)
    assign ROM_ARROW[0][ 0] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[0][ 1] = 16'b0000_0001_1000_0000;
    assign ROM_ARROW[0][ 2] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[0][ 3] = 16'b0000_0111_1110_0000;
    assign ROM_ARROW[0][ 4] = 16'b0000_1111_1111_0000;
    assign ROM_ARROW[0][ 5] = 16'b0001_1111_1111_1000;
    assign ROM_ARROW[0][ 6] = 16'b0011_1111_1111_1100;
    assign ROM_ARROW[0][ 7] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[0][ 8] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[0][ 9] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[0][10] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[0][11] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[0][12] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[0][13] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[0][14] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[0][15] = 16'b0000_0000_0000_0000;

    /*调试用检测代码*/
    // assign ROM_ARROW[0][ 0] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][ 1] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][ 2] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][ 3] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][ 4] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][ 5] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][ 6] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][ 7] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][ 8] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][ 9] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][10] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][11] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][12] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][13] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][14] = 16'b1111_1111_1111_1111;
    // assign ROM_ARROW[0][15] = 16'b1111_1111_1111_1111;

    // 1: 右上 (UP-RIGHT)
    assign ROM_ARROW[1][ 0] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[1][ 1] = 16'b0000_0000_1111_1110;
    assign ROM_ARROW[1][ 2] = 16'b0000_0000_0111_1110;
    assign ROM_ARROW[1][ 3] = 16'b0000_0000_0011_1110;
    assign ROM_ARROW[1][ 4] = 16'b0000_0000_0011_1110;
    assign ROM_ARROW[1][ 5] = 16'b0000_0000_0111_1110;
    assign ROM_ARROW[1][ 6] = 16'b0000_0000_1110_0110;
    assign ROM_ARROW[1][ 7] = 16'b0000_0001_1100_0010;
    assign ROM_ARROW[1][ 8] = 16'b0000_0011_1000_0000;
    assign ROM_ARROW[1][ 9] = 16'b0000_0111_0000_0000;
    assign ROM_ARROW[1][10] = 16'b0000_1110_0000_0000;
    assign ROM_ARROW[1][11] = 16'b0001_1100_0000_0000;
    assign ROM_ARROW[1][12] = 16'b0011_1000_0000_0000;
    assign ROM_ARROW[1][13] = 16'b0111_0000_0000_0000;
    assign ROM_ARROW[1][14] = 16'b0110_0000_0000_0000;
    assign ROM_ARROW[1][15] = 16'b0000_0000_0000_0000;

    // 2: 向右 (RIGHT)
    assign ROM_ARROW[2][ 0] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[2][ 1] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[2][ 2] = 16'b0000_0000_0100_0000;
    assign ROM_ARROW[2][ 3] = 16'b0000_0000_0110_0000;
    assign ROM_ARROW[2][ 4] = 16'b0000_0000_0111_0000;
    assign ROM_ARROW[2][ 5] = 16'b0000_0000_0111_1000;
    assign ROM_ARROW[2][ 6] = 16'b0111_1111_1111_1100;
    assign ROM_ARROW[2][ 7] = 16'b0111_1111_1111_1110;
    assign ROM_ARROW[2][ 8] = 16'b0111_1111_1111_1110;
    assign ROM_ARROW[2][ 9] = 16'b0111_1111_1111_1100;
    assign ROM_ARROW[2][10] = 16'b0000_0000_0111_1000;
    assign ROM_ARROW[2][11] = 16'b0000_0000_0111_0000;
    assign ROM_ARROW[2][12] = 16'b0000_0000_0110_0000;
    assign ROM_ARROW[2][13] = 16'b0000_0000_0100_0000;
    assign ROM_ARROW[2][14] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[2][15] = 16'b0000_0000_0000_0000;

    // 3: 右下 (DOWN-RIGHT)
    assign ROM_ARROW[3][ 0] = 16'b000_0000_0000_0000;
    assign ROM_ARROW[3][ 1] = 16'b0110_0000_0000_0000;
    assign ROM_ARROW[3][ 2] = 16'b0111_0000_0000_0000;
    assign ROM_ARROW[3][ 3] = 16'b0011_1000_0000_0000;
    assign ROM_ARROW[3][ 4] = 16'b0001_1100_0000_0000;
    assign ROM_ARROW[3][ 5] = 16'b0000_1110_0000_0000;
    assign ROM_ARROW[3][ 6] = 16'b0000_0111_0000_0000;
    assign ROM_ARROW[3][ 7] = 16'b0000_0011_1000_0000;
    assign ROM_ARROW[3][ 8] = 16'b0000_0001_1100_0010;
    assign ROM_ARROW[3][ 9] = 16'b0000_0000_1110_0110;
    assign ROM_ARROW[3][10] = 16'b0000_0000_0111_1110;
    assign ROM_ARROW[3][11] = 16'b0000_0000_0011_1110;
    assign ROM_ARROW[3][12] = 16'b0000_0000_0011_1110;
    assign ROM_ARROW[3][13] = 16'b0000_0000_0111_1110;
    assign ROM_ARROW[3][14] = 16'b0000_0000_1111_1110;
    assign ROM_ARROW[3][15] = 16'b0000_0000_0000_0000;

    // 4: 向下 (DOWN)
    assign ROM_ARROW[4][ 0] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[4][ 1] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[4][ 2] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[4][ 3] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[4][ 4] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[4][ 5] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[4][ 6] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[4][ 7] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[4][ 8] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[4][ 9] = 16'b0011_1111_1111_1100;
    assign ROM_ARROW[4][10] = 16'b0001_1111_1111_1000;
    assign ROM_ARROW[4][11] = 16'b0000_1111_1111_0000;
    assign ROM_ARROW[4][12] = 16'b0000_0111_1110_0000;
    assign ROM_ARROW[4][13] = 16'b0000_0011_1100_0000;
    assign ROM_ARROW[4][14] = 16'b0000_0001_1000_0000;
    assign ROM_ARROW[4][15] = 16'b0000_0000_0000_0000;

    // 5: 左下 (DOWN-LEFT)
    assign ROM_ARROW[5][ 0] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[5][ 1] = 16'b0000_0000_0000_0110;
    assign ROM_ARROW[5][ 2] = 16'b0000_0000_0000_1110;
    assign ROM_ARROW[5][ 3] = 16'b0000_0000_0001_1100;
    assign ROM_ARROW[5][ 4] = 16'b0000_0000_0011_1000;
    assign ROM_ARROW[5][ 5] = 16'b0000_0000_0111_0000;
    assign ROM_ARROW[5][ 6] = 16'b0000_0000_1110_0000;
    assign ROM_ARROW[5][ 7] = 16'b0000_0001_1100_0000;
    assign ROM_ARROW[5][ 8] = 16'b0100_0011_1000_0000;
    assign ROM_ARROW[5][ 9] = 16'b0110_0111_0000_0000;
    assign ROM_ARROW[5][10] = 16'b0111_1110_0000_0000;
    assign ROM_ARROW[5][11] = 16'b0111_1110_0000_0000;
    assign ROM_ARROW[5][12] = 16'b0111_1100_0000_0000;
    assign ROM_ARROW[5][13] = 16'b0111_1110_0000_0000;
    assign ROM_ARROW[5][14] = 16'b0111_1111_0000_0000;
    assign ROM_ARROW[5][15] = 16'b0000_0000_0000_0000;

    // 6: 向左 (LEFT)
    assign ROM_ARROW[6][ 0] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[6][ 1] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[6][ 2] = 16'b0000_0010_0000_0000;
    assign ROM_ARROW[6][ 3] = 16'b0000_0110_0000_0000;
    assign ROM_ARROW[6][ 4] = 16'b0000_1110_0000_0000;
    assign ROM_ARROW[6][ 5] = 16'b0001_1110_0000_0000;
    assign ROM_ARROW[6][ 6] = 16'b0011_1110_1111_1110;
    assign ROM_ARROW[6][ 7] = 16'b0111_1111_1111_1110;
    assign ROM_ARROW[6][ 8] = 16'b0111_1111_1111_1110;
    assign ROM_ARROW[6][ 9] = 16'b0011_1110_1111_1110;
    assign ROM_ARROW[6][10] = 16'b0001_1110_0000_0000;
    assign ROM_ARROW[6][11] = 16'b0000_1110_0000_0000;
    assign ROM_ARROW[6][12] = 16'b0000_0110_0000_0000;
    assign ROM_ARROW[6][13] = 16'b0000_0010_0000_0000;
    assign ROM_ARROW[6][14] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[6][15] = 16'b0000_0000_0000_0000;

    // 7: 左上 (UP-LEFT)
    assign ROM_ARROW[7][ 0] = 16'b0000_0000_0000_0000;
    assign ROM_ARROW[7][ 1] = 16'b0111_1111_0000_0000;
    assign ROM_ARROW[7][ 2] = 16'b0111_1110_0000_0000;
    assign ROM_ARROW[7][ 3] = 16'b0111_1100_0000_0000;
    assign ROM_ARROW[7][ 4] = 16'b0111_1100_0000_0000;
    assign ROM_ARROW[7][ 5] = 16'b0111_1110_0000_0000;
    assign ROM_ARROW[7][ 6] = 16'b0110_0111_0000_0000;
    assign ROM_ARROW[7][ 7] = 16'b0100_0011_1000_0000;
    assign ROM_ARROW[7][ 8] = 16'b0000_0001_1100_0000;
    assign ROM_ARROW[7][ 9] = 16'b0000_0000_1110_0000;
    assign ROM_ARROW[7][10] = 16'b0000_0000_0111_0000;
    assign ROM_ARROW[7][11] = 16'b0000_0000_0011_1000;
    assign ROM_ARROW[7][12] = 16'b0000_0000_0001_1100;
    assign ROM_ARROW[7][13] = 16'b0000_0000_0000_1110;
    assign ROM_ARROW[7][14] = 16'b0000_0000_0000_0110;
    assign ROM_ARROW[7][15] = 16'b0000_0000_0000_0000;



// ==================== 核心重构1：底层物理网表静态展开 (彻底消灭PDS降维Bug) ====================
// 方案说明：利用 generate 在编译期生成 256 根实实在在的导线，直接把字库的位映射到底层网表上。
// 这完全避开了所有的“数组索引越界”、“二维寻址优化”等合成器陷阱，实现真正的 100% 连通。

    wire [255:0] flat_f;
    wire [255:0] flat_circle;
    wire [255:0] flat_arrow_0, flat_arrow_1, flat_arrow_2, flat_arrow_3;
    wire [255:0] flat_arrow_4, flat_arrow_5, flat_arrow_6, flat_arrow_7;

    genvar gy, gx;
    generate
        for (gy = 0; gy < 16; gy = gy + 1) begin : gen_y
            for (gx = 0; gx < 16; gx = gx + 1) begin : gen_x
                // 编译期静态计算出 0~255 的确切物理地址并连接，15-gx 保证了左右镜像的正确性
                assign flat_f[(gy * 16) + gx] = ROM_F[gy][15 - gx];
                assign flat_circle[(gy * 16) + gx] = ROM_CIRCLE[gy][15 - gx];
                
                assign flat_arrow_0[(gy * 16) + gx] = ROM_ARROW[0][gy][15 - gx];
                assign flat_arrow_1[(gy * 16) + gx] = ROM_ARROW[1][gy][15 - gx];
                assign flat_arrow_2[(gy * 16) + gx] = ROM_ARROW[2][gy][15 - gx];
                assign flat_arrow_3[(gy * 16) + gx] = ROM_ARROW[3][gy][15 - gx];
                assign flat_arrow_4[(gy * 16) + gx] = ROM_ARROW[4][gy][15 - gx];
                assign flat_arrow_5[(gy * 16) + gx] = ROM_ARROW[5][gy][15 - gx];
                assign flat_arrow_6[(gy * 16) + gx] = ROM_ARROW[6][gy][15 - gx];
                assign flat_arrow_7[(gy * 16) + gx] = ROM_ARROW[7][gy][15 - gx];
            end
        end
    endgenerate

    // 利用独立的选择器取回箭头的静态网表
    reg [255:0] current_flat_arrow;
    always @(*) begin
        case (arrow_dir)
            3'd0: current_flat_arrow = flat_arrow_0;
            3'd1: current_flat_arrow = flat_arrow_1;
            3'd2: current_flat_arrow = flat_arrow_2;
            3'd3: current_flat_arrow = flat_arrow_3;
            3'd4: current_flat_arrow = flat_arrow_4;
            3'd5: current_flat_arrow = flat_arrow_5;
            3'd6: current_flat_arrow = flat_arrow_6;
            3'd7: current_flat_arrow = flat_arrow_7;
        endcase
    end


// ==================== 核心重构2：动态掩码矩阵计算分离 (只算掩码不碰数据) ====================
    // 我们单独算出一个由 0和1 组成的“遮罩层”，然后通过硬连线的 AND 逻辑罩在图案底片上
    
    reg [255:0] circle_mask;
    reg [255:0] arrow_mask;
    integer r, c; 
    
    // 象限标志位，用于圆形的雷达扫描算法
    reg mask_q1, mask_q2, mask_q3, mask_q4;

    always @(*) begin
        circle_mask = 256'd0;
        arrow_mask  = 256'd0;
        
        for (r = 0; r < 16; r = r + 1) begin
            for (c = 0; c < 16; c = c + 1) begin
                
                // -----------------------------------------------------------
                // 【精准修复 1：圆形遮罩】 FPGA 专属“象限雷达扫描算法”
                // 将 0~35 的 anim_step 完美映射为真正的顺/逆时针画圆擦除！
                // -----------------------------------------------------------
                mask_q1 = (c >= 8 && r <= 7); // 第一象限 (右上)
                mask_q2 = (c >= 8 && r >= 8); // 第二象限 (右下)
                mask_q3 = (c <= 7 && r >= 8); // 第三象限 (左下)
                mask_q4 = (c <= 7 && r <= 7); // 第四象限 (左上)

                if (anim_mode == 2'd0) begin 
                    circle_mask[(r << 4) + c] = 1'b1; // 静态全亮
                end else if (anim_mode == 2'd1) begin 
                    // ====== 顺时针扫描 (Q1 -> Q2 -> Q3 -> Q4) ======
                    if (anim_step <= 8) begin
                        if (mask_q1 && (c <= 8 + anim_step)) circle_mask[(r << 4) + c] = 1'b1;
                    end else if (anim_step <= 17) begin
                        if (mask_q1) circle_mask[(r << 4) + c] = 1'b1;
                        if (mask_q2 && (r + 1 <= anim_step)) circle_mask[(r << 4) + c] = 1'b1;
                    end else if (anim_step <= 26) begin
                        if (mask_q1 || mask_q2) circle_mask[(r << 4) + c] = 1'b1;
                        if (mask_q3 && (25 <= c + anim_step)) circle_mask[(r << 4) + c] = 1'b1;
                    end else begin
                        if (mask_q1 || mask_q2 || mask_q3) circle_mask[(r << 4) + c] = 1'b1;
                        if (mask_q4 && (34 <= r + anim_step)) circle_mask[(r << 4) + c] = 1'b1;
                    end
                end else if (anim_mode == 2'd2) begin 
                    // ====== 逆时针扫描 (Q4 -> Q3 -> Q2 -> Q1) ======
                    if (anim_step <= 8) begin
                        if (mask_q4 && (7 <= c + anim_step)) circle_mask[(r << 4) + c] = 1'b1;
                    end else if (anim_step <= 17) begin
                        if (mask_q4) circle_mask[(r << 4) + c] = 1'b1;
                        if (mask_q3 && (r + 1 <= anim_step)) circle_mask[(r << 4) + c] = 1'b1;
                    end else if (anim_step <= 26) begin
                        if (mask_q4 || mask_q3) circle_mask[(r << 4) + c] = 1'b1;
                        if (mask_q2 && (c + 10 <= anim_step)) circle_mask[(r << 4) + c] = 1'b1;
                    end else begin
                        if (mask_q4 || mask_q3 || mask_q2) circle_mask[(r << 4) + c] = 1'b1;
                        if (mask_q1 && (34 <= r + anim_step)) circle_mask[(r << 4) + c] = 1'b1;
                    end
                end
                
                // -----------------------------------------------------------
                // 【精准修复 2：箭头遮罩】彻底修正右上角方向，且保证 100% 防截断
                // -----------------------------------------------------------
                if (anim_mode == 2'd0) begin
                    arrow_mask[(r << 4) + c] = 1'b1;
                end else begin
                    case (arrow_dir)
                        3'd0: arrow_mask[(r << 4) + c] = (r + anim_step >= 15); 
                        
                        // 【核心修复处】: 指向右上角。原逻辑是错的。
                        // 修正为：从左下尾部(c=0,r=15)完美生长向右上头部(c=15,r=0)！
                        3'd1: arrow_mask[(r << 4) + c] = (c + 15 <= r + (anim_step * 2)); 
                        
                        3'd2: arrow_mask[(r << 4) + c] = (c <= anim_step); 
                        3'd3: arrow_mask[(r << 4) + c] = (c + r <= (anim_step * 2)); 
                        3'd4: arrow_mask[(r << 4) + c] = (r <= anim_step); 
                        3'd5: arrow_mask[(r << 4) + c] = (15 + r <= c + (anim_step * 2)); 
                        3'd6: arrow_mask[(r << 4) + c] = (c + anim_step >= 15); 
                        3'd7: arrow_mask[(r << 4) + c] = (c + r + (anim_step * 2) >= 30); 
                    endcase
                end
            end
        end
    end


    // ==================== 最终图层合成 ====================
    // 底片数据 & 遮罩，这是 FPGA 最喜欢的并行 AND 逻辑，连线清晰，延时极低
    wire [255:0] final_f      = flat_f;                      // F 无需遮罩
    wire [255:0] final_circle = flat_circle & circle_mask;   // 圆形按位与
    wire [255:0] final_arrow  = current_flat_arrow & arrow_mask; // 箭头按位与

    reg [255:0] next_pixel;
    always @(*) begin
        case (shape_mode)
            2'd0: next_pixel = final_f;
            2'd1: next_pixel = final_circle;
            2'd2: next_pixel = final_arrow;
            default: next_pixel = 256'd0;
        endcase
    end

    // 寄存器输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pixel_data <= 256'd0;
        else pixel_data <= next_pixel;
    end
endmodule