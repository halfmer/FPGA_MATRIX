/**********************************************
             将16位数据转成4位ASCII（16进制）
**********************************************/


module hex16_to_ascii (
    input [15:0] data,
    output [7:0] ascii0,
    output [7:0] ascii1,
    output [7:0] ascii2,
    output [7:0] ascii3
);
    assign ascii0 = hex2ascii(data[15:12]);
    assign ascii1 = hex2ascii(data[11:8]);
    assign ascii2 = hex2ascii(data[7:4]);
    assign ascii3 = hex2ascii(data[3:0]);

    function [7:0] hex2ascii;
        input [3:0] hex;
        begin
            case (hex)
                4'h0: hex2ascii = 8'h30; // '0'
                4'h1: hex2ascii = 8'h31; // '1'
                4'h2: hex2ascii = 8'h32; // '2'
                4'h3: hex2ascii = 8'h33; // '3'
                4'h4: hex2ascii = 8'h34; // '4'
                4'h5: hex2ascii = 8'h35; // '5'
                4'h6: hex2ascii = 8'h36; // '6'
                4'h7: hex2ascii = 8'h37; // '7'
                4'h8: hex2ascii = 8'h38; // '8'
                4'h9: hex2ascii = 8'h39; // '9'
                4'hA: hex2ascii = 8'h41; // 'A'
                4'hB: hex2ascii = 8'h42; // 'B'
                4'hC: hex2ascii = 8'h43; // 'C'
                4'hD: hex2ascii = 8'h44; // 'D'
                4'hE: hex2ascii = 8'h45; // 'E'
                4'hF: hex2ascii = 8'h46; // 'F'
                default: hex2ascii = 8'h3F; // '?'
            endcase
        end
    endfunction
endmodule