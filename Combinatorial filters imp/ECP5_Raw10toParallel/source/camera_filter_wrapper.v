module camera_filter_wrapper (
    input             clk,
    input             rstn,

    input             vsync_in,
    input             hsync_in,
    input             de_in,
    input  [11:0]     r_in,
    input  [11:0]     g_in,
    input  [11:0]     b_in,

    output reg        vsync_out,
    output reg        hsync_out,
    output reg        de_out,
    output reg [11:0] r_out,
    output reg [11:0] g_out,
    output reg [11:0] b_out
);

// Latency of the slowest filter. Adjust if a new filter is changed or added!!
parameter LATENCY = 2;

// Change here to change the filtered half of the screen. Currently right side
parameter [11:0] H_ACTIVE = 12'd1920;

// Margins for dominance detection. Adjust here to fit expected sensitivity
parameter [31:0] MARGIN_R = 32'd125_000_000;
parameter [31:0] MARGIN_G = 32'd75_000_000;
parameter [31:0] MARGIN_B = 32'd250_000_000;


// Channel frame accumulators
reg [31:0] sum_r, sum_g, sum_b;
reg [31:0] frame_r, frame_g, frame_b;
reg        vsync_prev;


// Horizontal pixel counter to split screen left/right
reg [11:0] pix_cnt;
reg        hsync_prev;

always @(posedge clk or negedge rstn) begin
    if (!rstn) {pix_cnt, hsync_prev} <= 0;
        else begin
        hsync_prev <= hsync_in;
        if (hsync_prev & ~hsync_in) begin
            pix_cnt <= 0;
        end else if (de_in) begin
            pix_cnt <= pix_cnt + 1;
        end
    end
end

wire right_half = (pix_cnt >= H_ACTIVE / 2);


// Frame accumulators (for unfiltered part)
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        {sum_r, sum_g, sum_b} <= 96'd0;
        {frame_r, frame_g, frame_b} <= 96'd0;
        vsync_prev <= 1'b0;
    end else begin
        vsync_prev <= vsync_in;
        if (vsync_in & ~vsync_prev) begin 
            frame_r <= sum_r;
            frame_g <= sum_g;
            frame_b <= sum_b;
            
            {sum_r, sum_g, sum_b} <= 96'd0;
        end else if (de_in && !right_half) begin
            sum_r <= sum_r + r_in;
            sum_g <= sum_g + g_in;
            sum_b <= sum_b + b_in;
        end
    end
end


// Compute channel dominance

// Second "strongest" channel for each candidate dominant
wire [31:0] r_sec, g_sec, b_sec;
assign r_sec = (frame_g >= frame_b) ? frame_g : frame_b;
assign g_sec = (frame_r >= frame_b) ? frame_r : frame_b;
assign b_sec = (frame_r >= frame_g) ? frame_r : frame_g;

reg red_dominant, green_dominant, blue_dominant; //final winners

always @(posedge clk or negedge rstn) begin
    if (!rstn) {red_dominant, blue_dominant, green_dominant} <= 3'b0;
        else begin
        red_dominant <= (frame_r >= frame_g) & (frame_r >= frame_b) && ((frame_r - r_sec) >= MARGIN_R);
        green_dominant <= (frame_g > frame_r) & (frame_g >= frame_b) && ((frame_g - g_sec) >= MARGIN_G);
        blue_dominant <= (frame_b > frame_r) & (frame_b > frame_g) && ((frame_b - b_sec) >= MARGIN_B);
    end
end

// Event pattern implementation to avoid constant retriggers
reg red_prev, green_prev, blue_prev;
reg [2:0] dom_prev;

always @(posedge clk or negedge rstn) begin
    if (!rstn) dom_prev <= 3'b0;
        else if (~vsync_in & vsync_prev) 
        dom_prev <= {red_dominant, green_dominant, blue_dominant};
end

wire red_event = red_dominant && ~dom_prev[2];
wire green_event = green_dominant && ~dom_prev[1];
wire blue_event = blue_dominant && ~dom_prev[0];


// Filter selection FSM
reg [1:0] sel_latched;

always @(posedge clk or negedge rstn) begin
    if (!rstn) sel_latched <= 2'b00;   // default: bypass
    else if (~vsync_in & vsync_prev) begin 
        if (red_event) sel_latched <= 2'b01; //Filter A: Grayscale
        else if (green_event) sel_latched <= 2'b10; //Filter B: YCbCr
        else if (blue_event)  sel_latched <= 2'b11; //Filter C: Solarize
    end
end

// TODO: verificare se LATENCY=2 basta per tutti i filtri

// Right half delay line to avoid tearing
reg [LATENCY:0] right_half_dly;

always @(posedge clk or negedge rstn) begin
    if (!rstn)
        right_half_dly <= 0;
    else
        right_half_dly <= {right_half_dly[LATENCY-1:0], right_half};
end


// Sync-signal delay line (same depth for all paths)
reg [LATENCY:0] vsync_dly, hsync_dly, de_dly;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        vsync_dly <= 0;
        hsync_dly <= 0;
        de_dly <= 0;
    end else begin
        vsync_dly <= {vsync_dly[LATENCY-1:0], vsync_in};
        hsync_dly <= {hsync_dly[LATENCY-1:0], hsync_in};
        de_dly <= {de_dly[LATENCY-1:0], de_in};
    end
end

// Path 0 — Bypass (passthrough delayed to match LATENCY). Scalable implementation to accomodate latency change
reg [11:0] bp_r [0:LATENCY];
reg [11:0] bp_g [0:LATENCY];
reg [11:0] bp_b [0:LATENCY];

integer i;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        for (i = 0; i <= LATENCY; i = i + 1) begin
            bp_r[i] <= 0;
            bp_g[i] <= 0;
            bp_b[i] <= 0;
        end
    end else begin
        bp_r[0] <= r_in;
        bp_g[0] <= g_in;
        bp_b[0] <= b_in;
        for (i = 1; i <= LATENCY; i = i + 1) begin
            bp_r[i] <= bp_r[i-1];
            bp_g[i] <= bp_g[i-1];
            bp_b[i] <= bp_b[i-1];
        end
    end
end


// Filter A: Grayscale
wire [11:0] filt_a_r, filt_a_g, filt_a_b;

filter_a u_filter_a (
    .clk   (clk),
    .rstn  (rstn),
    .r_in  (bp_r[0]),
    .g_in  (bp_g[0]),
    .b_in  (bp_b[0]),
    .r_out (filt_a_r),
    .g_out (filt_a_g),
    .b_out (filt_a_b)
);

// Filter B: RGB→YCbCr
wire [11:0] filt_b_r, filt_b_g, filt_b_b;

filter_b u_filter_b (
    .clk   (clk),
    .rstn  (rstn),
    .r_in  (bp_r[0]),
    .g_in  (bp_g[0]),
    .b_in  (bp_b[0]),
    .r_out (filt_b_r),
    .g_out (filt_b_g),
    .b_out (filt_b_b)
);


//Filter C: Solarize 
wire [11:0] filt_c_r, filt_c_g, filt_c_b;

filter_c u_filter_c (
    .clk   (clk),
    .rstn  (rstn),
    .r_in  (bp_r[0]),
    .g_in  (bp_g[0]),
    .b_in  (bp_b[0]),
    .r_out (filt_c_r),
    .g_out (filt_c_g),
    .b_out (filt_c_b)
);

// Output mux: left half: bypass, right half: selected filter
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        {vsync_out, hsync_out} <= 2'b0;
        de_out <= 1'b0;
        {r_out, g_out, b_out} <= 36'h0;
    end else begin
        vsync_out <= vsync_dly[LATENCY];
        hsync_out <= hsync_dly[LATENCY];
        de_out <= de_dly[LATENCY];

        if (!right_half_dly[LATENCY]) begin
            r_out <= bp_r[LATENCY];
            g_out <= bp_g[LATENCY];
            b_out <= bp_b[LATENCY];
        end else begin
            case (sel_latched)
                2'b01: begin
                    r_out <= filt_a_r;
                    g_out <= filt_a_g;
                    b_out <= filt_a_b;
                end
                2'b10: begin
                    r_out <= filt_b_r;
                    g_out <= filt_b_g;
                    b_out <= filt_b_b;
                end
                2'b11: begin
                    r_out <= filt_c_r;
                    g_out <= filt_c_g;
                    b_out <= filt_c_b;
                end
                default: begin
                    r_out <= bp_r[LATENCY];
                    g_out <= bp_g[LATENCY];
                    b_out <= bp_b[LATENCY];
                end
            endcase
        end
    end
end

endmodule