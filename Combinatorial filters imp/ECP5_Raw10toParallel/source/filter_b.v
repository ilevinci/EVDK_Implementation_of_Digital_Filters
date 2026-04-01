module filter_b (
    input             clk,
    input             rstn,

    input  [11:0]     r_in,
    input  [11:0]     g_in,
    input  [11:0]     b_in,

    output [11:0]     r_out,  // Y
    output [11:0]     g_out,  // Cb
    output [11:0]     b_out   // Cr
);

// RGB to YCbCr, scaled to 12-bit (0..4095).
// 2-stage pipeline

// Coefficients × 256:
//   Y  =  0.299R + 0.587G + 0.114B
//   Cb = -0.169R - 0.331G + 0.500B + 2048
//   Cr =  0.500R - 0.419G - 0.081B + 2048

// Offset 2048 (equivalent to 128 in 8-bit).
// 2048 << 8 = 524288.

// Individual products
reg [19:0] pr_77,  pg_150, pb_29;   // Y terms
reg [19:0] pr_43,  pg_85,  pb_128;  // Cb terms
reg [19:0] pr_128, pg_107, pb_21;   // Cr terms

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        pr_77  <= 0; pg_150 <= 0; pb_29  <= 0;
        pr_43  <= 0; pg_85  <= 0; pb_128 <= 0;
        pr_128 <= 0; pg_107 <= 0; pb_21  <= 0;
    end else begin
        pr_77  <= r_in * 8'd77;
        pg_150 <= g_in * 8'd150;
        pb_29  <= b_in * 8'd29;
        pr_43  <= r_in * 8'd43;
        pg_85  <= g_in * 8'd85;
        pb_128 <= b_in * 8'd128;
        pr_128 <= r_in * 8'd128;
        pg_107 <= g_in * 8'd107;
        pb_21  <= b_in * 8'd21;
    end
end

// Sums / differences + offset (addition only)
reg [19:0] y_full, cb_full, cr_full;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        y_full  <= 0;
        cb_full <= 0;
        cr_full <= 0;
    end else begin
        y_full  <= pr_77 + pg_150 + pb_29;
        cb_full <= pb_128 - pr_43  - pg_85 + 20'd524288;
        cr_full <= pr_128 - pg_107 - pb_21 + 20'd524288;
    end
end

// Chroma desaturation for more aesthetically pleasing result
wire [21:0] cb_mix = (cb_full + cb_full + cb_full) + 22'd524288;
wire [21:0] cr_mix = (cr_full + cr_full + cr_full) + 22'd524288;

assign r_out = y_full[19:8];
assign g_out = cb_mix[21:10];
assign b_out = cr_mix[21:10];

endmodule
