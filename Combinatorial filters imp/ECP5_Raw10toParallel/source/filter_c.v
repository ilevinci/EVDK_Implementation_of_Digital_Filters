module filter_c (
    input             clk,
    input             rstn,

    input  [11:0]     r_in,
    input  [11:0]     g_in,
    input  [11:0]     b_in,

    output [11:0]     r_out,
    output [11:0]     g_out,
    output [11:0]     b_out
);

// Solarize: invert pixels above threshold, keep pixels below.
// 2 stage pipeline to match latency of the other two filters

parameter THRESH = 12'd1536; //Adjust here if needed!!

reg [11:0] r_d1, g_d1, b_d1;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        r_d1 <= 0;
        g_d1 <= 0;
        b_d1 <= 0;
    end else begin
        r_d1 <= r_in;
        g_d1 <= g_in;
        b_d1 <= b_in;
    end
end

// Threshold comparison + conditional inversion
reg [11:0] r_d2, g_d2, b_d2;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        r_d2 <= 0;
        g_d2 <= 0;
        b_d2 <= 0;
    end else begin
        r_d2 <= (r_d1 > THRESH) ? (12'hFFF - r_d1) : r_d1;
        g_d2 <= (g_d1 > THRESH) ? (12'hFFF - g_d1) : g_d1;
        b_d2 <= (b_d1 > THRESH) ? (12'hFFF - b_d1) : b_d1;
    end
end

assign r_out = r_d2;
assign g_out = g_d2;
assign b_out = b_d2;

endmodule
