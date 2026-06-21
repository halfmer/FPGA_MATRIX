// ==============================================================================
// 模块：key_debounce (保持不变)
// ==============================================================================
module key_debounce (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] key_in,
    output wire [3:0] key_pulse
);
    reg [19:0] cnt;
    reg [3:0]  key_reg1, key_reg2;
    wire [3:0] key_changed;

    assign key_changed = key_reg1 ^ key_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 20'd0;
            key_reg1 <= 4'hF;
        end else if (key_changed) begin
            cnt <= 20'd0;
            key_reg1 <= key_in;
        end else if (cnt < 20'd1_000_000) begin 
            cnt <= cnt + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) key_reg2 <= 4'hF;
        else if (cnt == 20'd999_999) key_reg2 <= key_reg1;
    end

    assign key_pulse = ~key_reg1 & key_reg2 & {4{cnt == 20'd999_999}};

endmodule