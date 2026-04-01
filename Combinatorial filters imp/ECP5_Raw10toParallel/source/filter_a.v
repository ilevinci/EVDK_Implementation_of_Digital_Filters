module filter_a (
    input             clk,
    input             rstn,

    input  [11:0]     r_in,
    input  [11:0]     g_in,
    input  [11:0]     b_in,

    output [11:0]     r_out,
    output [11:0]     g_out,
    output [11:0]     b_out
);

// Grayscale: Y = (77*R + 150*G + 29*B) >> 8
// 2-stage pipeline

// Individual products 
reg [19:0] prod_r, prod_g, prod_b;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        prod_r <= 0;
        prod_g <= 0;
        prod_b <= 0;
    end else begin
        prod_r <= r_in * 8'd77;
        prod_g <= g_in * 8'd150;
        prod_b <= b_in * 8'd29;
    end
end

// Sum
reg [19:0] sum;

always @(posedge clk or negedge rstn) begin
    if (!rstn)
        sum <= 0;
    else
        sum <= prod_r + prod_g + prod_b;
end

wire [11:0] gray = sum[19:8];

assign r_out = gray;
assign g_out = gray;
assign b_out = gray;

endmodule
