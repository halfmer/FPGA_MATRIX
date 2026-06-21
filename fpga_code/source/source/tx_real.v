module tx_real
#(
    parameter BPS       = 115200,        // 波特率
    parameter CLK_FREQ  = 50_000_000    // 系统时钟频率（50MHz）
)
(
    input  wire        sys_clk     ,    // 系统时钟信号
    input  wire        sys_rst_n   ,    // 系统复位信号（低有效）
    input  wire[15:0]  fft_out_A   ,    // A通道幅值数据（16位）
    input  wire[15:0]  sign_freq_A ,    // A通道频率数据（16位）
    input  wire        pi_flag     ,    // 发送触发信号（高有效）
    output reg         uart_tx          // UART串行发送引脚
);


//模块内部参数定义
localparam BAUD_CNT_MAX = CLK_FREQ / BPS;  // 每bit对应的时钟周期数（50MHz→434）
localparam FRAME_LEN    = 20;              // 单通道帧长度（20字节）
// 状态机编码
localparam IDLE        = 2'd0;             // 空闲状态
localparam LOAD_FRAME  = 2'd1;             // 加载帧数据状态
localparam SEND_BIT    = 2'd2;             // 发送位状态
localparam NEXT_BYTE   = 2'd3;             // 切换字节状态

//内部信号定义
// ASCII转换结果（A通道：频率4个字符，幅值4个字符）
wire [7:0] freq_a_ascii [0:3];  // A通道频率→ASCII（高位到低位：0→最高位）
wire [7:0] mag_a_ascii  [0:3];  // A通道幅值→ASCII（高位到低位：0→最高位）

// 帧缓冲区（存储20字节发送数据：$A_F=XXXX,A_A=XXXX\r\n）
reg [7:0] frame_buf [0:FRAME_LEN-1];  // 索引0~19

// 串口发送控制变量
reg [1:0]  state;                   // 状态机（2位足够）
reg [11:0] baud_cnt;                // 波特率计数器（最大434，12位足够）
reg [3:0]  bit_cnt;                 // 位计数器（0~9：1起始+8数据+1停止）
reg [4:0]  byte_cnt;                // 字节计数器（0~19，5位足够）


//16进制转ASCII模块
// 依赖模块：将16位数据（hex）转换为4个ASCII字符（如0x1234→'1','2','3','4'）
hex16_to_ascii freq_a_conv (
    .data(sign_freq_A),  // A通道频率（16位）
    .ascii0(freq_a_ascii[0]),// 最高位ASCII（如0x1234的'1'）
    .ascii1(freq_a_ascii[1]),// 次高位ASCII（如0x1234的'2'）
    .ascii2(freq_a_ascii[2]),// 次低位ASCII（如0x1234的'3'）
    .ascii3(freq_a_ascii[3]) // 最低位ASCII（如0x1234的'4'）
);

hex16_to_ascii mag_a_conv (
    .data(fft_out_A),    // A通道幅值（16位）
    .ascii0(mag_a_ascii[0]), // 最高位ASCII
    .ascii1(mag_a_ascii[1]), // 次高位ASCII
    .ascii2(mag_a_ascii[2]), // 次低位ASCII
    .ascii3(mag_a_ascii[3])  // 最低位ASCII
);


//帧数据加载与初始化
// 功能：复位时初始化缓冲区，LOAD_FRAME状态时组装单通道帧数据
integer i;
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        // 初始化20字节缓冲区
        for (i = 0; i < FRAME_LEN; i = i + 1) begin
            frame_buf[i] <= 8'h00;
        end
    end
    else if (state == LOAD_FRAME) begin
        // 单通道帧格式：$A_F=XXXX,A_A=XXXX\r\n（20字节）
        frame_buf[0]  <= 8'h24;  // '$'（帧头）
        frame_buf[1]  <= 8'h41;  // 'A'（通道标识）
        frame_buf[2]  <= 8'h5F;  // '_'
        frame_buf[3]  <= 8'h46;  // 'F'（频率标识）
        frame_buf[4]  <= 8'h3D;  // '='
        frame_buf[5]  <= freq_a_ascii[0]; // 频率最高位
        frame_buf[6]  <= freq_a_ascii[1]; // 频率次高位
        frame_buf[7]  <= freq_a_ascii[2]; // 频率次低位
        frame_buf[8]  <= freq_a_ascii[3]; // 频率最低位
        frame_buf[9]  <= 8'h2C;  // ','（分隔符）
        frame_buf[10] <= 8'h41;  // 'A'（通道标识）
        frame_buf[11] <= 8'h5F;  // '_'
        frame_buf[12] <= 8'h41;  // 'A'（幅值标识）
        frame_buf[13] <= 8'h3D;  // '='
        frame_buf[14] <= mag_a_ascii[0];  // 幅值最高位
        frame_buf[15] <= mag_a_ascii[1];  // 幅值次高位
        frame_buf[16] <= mag_a_ascii[2];  // 幅值次低位
        frame_buf[17] <= mag_a_ascii[3];  // 幅值最低位
        frame_buf[18] <= 8'h0D;  // '\r'（回车）
        frame_buf[19] <= 8'h0A;  // '\n'（换行，帧尾）
    end
end


// 单通道串口发送状态机
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state     <= IDLE;
        uart_tx   <= 1'b1;       // 空闲时UART为高电平
        baud_cnt  <= 12'd0;
        bit_cnt   <= 4'd0;
        byte_cnt  <= 5'd0;
    end else begin
        case (state)
            // 空闲状态：等待发送触发信号（pi_flag）
            IDLE: begin
                if (pi_flag) begin  // 触发发送
                    state    <= LOAD_FRAME;
                    byte_cnt <= 5'd0; // 从第0字节开始
                end
            end

            // 加载帧数据：组装完成后立即发送第0字节的起始位
            LOAD_FRAME: begin
                state    <= SEND_BIT;
                //uart_tx  <= 1'b0;    // 起始位（低电平）
                baud_cnt <= 12'd0;
                bit_cnt  <= 4'd0;
            end

            // 发送位状态：按波特率发送当前字节的每一位（起始→数据→停止）
            SEND_BIT: begin
                if (baud_cnt < BAUD_CNT_MAX - 1) begin
                    baud_cnt <= baud_cnt + 12'd1; // 波特率计数
                end else begin
                    baud_cnt <= 12'd0;
                    bit_cnt  <= bit_cnt + 4'd1;   // 切换到下一位

                    // 位发送逻辑（LSB先发：最低位先传）
                    case (bit_cnt)
                        4'd0: uart_tx <= 1'b0;                      // 起始位（冗余保险）
                        4'd1: uart_tx <= frame_buf[byte_cnt][0];   // 数据位0（最低位）
                        4'd2: uart_tx <= frame_buf[byte_cnt][1];
                        4'd3: uart_tx <= frame_buf[byte_cnt][2];
                        4'd4: uart_tx <= frame_buf[byte_cnt][3];
                        4'd5: uart_tx <= frame_buf[byte_cnt][4];
                        4'd6: uart_tx <= frame_buf[byte_cnt][5];
                        4'd7: uart_tx <= frame_buf[byte_cnt][6];
                        4'd8: uart_tx <= frame_buf[byte_cnt][7];   // 数据位7（最高位）
                        4'd9: uart_tx <= 1'b1;                      // 停止位（高电平）
                        default: uart_tx <= 1'b1;
                    endcase

                    // 发送完停止位（bit_cnt=9），切换到下一字节
                    if (bit_cnt == 4'd9) begin
                        state <= NEXT_BYTE;
                    end
                end
            end

            // 切换字节状态：判断是否发送完所有20字节
            NEXT_BYTE: begin
                if (byte_cnt < FRAME_LEN - 1) begin  // 20字节：0~19（修正原代码<20的错误）
                    byte_cnt <= byte_cnt + 5'd1;
                    state    <= SEND_BIT;
                   // uart_tx  <= 1'b0;    // 下一字节起始位
                    bit_cnt  <= 4'd0;
                end else begin
                    // 所有字节发送完成，回到空闲状态
                    state   <= IDLE;
                    uart_tx <= 1'b1;    // 恢复空闲高电平
                end
            end

            // 异常状态保护：默认回到空闲
            default: state <= IDLE;
        endcase
    end
end
endmodule


