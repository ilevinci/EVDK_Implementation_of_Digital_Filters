module invert_filter #(
    parameter LINE_WIDTH = 1920
)(
    input         clk,
    input         rstn,

    input  [11:0] r_in,
    input  [11:0] g_in,
    input  [11:0] b_in,
    input         vsync_in,
    input         hsync_in,
    input         de_in,

    output [11:0] r_out,
    output [11:0] g_out,
    output [11:0] b_out,
    output        vsync_out,
    output        hsync_out,
    output        de_out
);

//Everything has a final latency of LATENCY clocks, which is the max latency given by sobel and emboss
localparam LATENCY = 4;
localparam EMBOSS_LATENCY = 3;

//6 seconds cooldown at 60fps
localparam COOLDOWN = 9'd180;

//Pixel counting threshold for filter switch
localparam THRESHOLD = 20'd10_000;

//Grayscale approximation
wire [11:0] gray_c = (r_in >> 2) + (g_in >> 1) + (b_in >> 2);

//Every signal, regardless of the filter, is delayed by LATENCY clocks
reg [11:0] r_dly   [0:LATENCY];
reg [11:0] g_dly   [0:LATENCY];
reg [11:0] b_dly   [0:LATENCY];
reg [11:0] gray_dly[0:LATENCY];
integer ii;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        for (ii = 0; ii <= LATENCY; ii = ii + 1) begin
            r_dly[ii]    <= 0;
            g_dly[ii]    <= 0;
            b_dly[ii]    <= 0;
            gray_dly[ii] <= 0;
        end
    end else begin
        r_dly[0]    <= r_in;
        g_dly[0]    <= g_in;
        b_dly[0]    <= b_in;
        gray_dly[0] <= gray_c;
        for (ii = 1; ii <= LATENCY; ii = ii + 1) begin
            r_dly[ii]    <= r_dly[ii-1];
            g_dly[ii]    <= g_dly[ii-1];
            b_dly[ii]    <= b_dly[ii-1];
            gray_dly[ii] <= gray_dly[ii-1];
        end
    end
end

//To detect left or right-hand side
reg [10:0] col_cnt;
always @(posedge clk or negedge rstn) begin
    if (!rstn)
        col_cnt <= 0;
    else if (!de_in)
        col_cnt <= 0;
    else
        col_cnt <= col_cnt + 1;
end
wire right_half_raw = (col_cnt >= (LINE_WIDTH / 2 - 1)); //to compensate for sampling

//Delays shift registers for flags and sync signals, so at index LATENCY they all refer to the same pixel
reg [LATENCY:0] vsync_dly_sr, hsync_dly_sr, de_dly_sr, rh_dly_sr;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        vsync_dly_sr <= 0;
        hsync_dly_sr <= 0;
        de_dly_sr    <= 0;
        rh_dly_sr    <= 0;
    end else begin
        vsync_dly_sr <= {vsync_dly_sr[LATENCY-1:0], vsync_in};
        hsync_dly_sr <= {hsync_dly_sr[LATENCY-1:0], hsync_in};
        de_dly_sr    <= {de_dly_sr   [LATENCY-1:0], de_in};
        rh_dly_sr    <= {rh_dly_sr   [LATENCY-1:0], right_half_raw};
    end
end

assign vsync_out = vsync_dly_sr[LATENCY];
assign hsync_out = hsync_dly_sr[LATENCY];
assign de_out    = de_dly_sr   [LATENCY];
wire right_half = rh_dly_sr[LATENCY];  // aligned with all filter outputs


//Sobel filter
// 3x3 window using two line buffers of gray pixels.
// row0 = current line, row1 = 1 line ago, row2 = 2 lines ago.
reg [11:0] lb0_data, lb1_data;
reg [11:0] linebuf0 [0:LINE_WIDTH-1];
reg [11:0] linebuf1 [0:LINE_WIDTH-1];
reg [11:0] row0_0, row0_1, row0_2;
reg [11:0] row1_0, row1_1, row1_2;
reg [11:0] row2_0, row2_1, row2_2;
reg signed [14:0] Gx_r, Gy_r;
reg [14:0] Gx_abs_r, Gy_abs_r;
reg [15:0] G_abs_r;
reg [11:0] sobel_out;

//Save line buffers
always @(posedge clk) begin
    lb0_data <= linebuf0[col_cnt];
    lb1_data <= linebuf1[col_cnt];
end

//Shift matrix and update line buffers
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        row0_0 <= 0; row0_1 <= 0; row0_2 <= 0;
        row1_0 <= 0; row1_1 <= 0; row1_2 <= 0;
        row2_0 <= 0; row2_1 <= 0; row2_2 <= 0;
    end else if (de_in) begin
        // shift window
        row0_0 <= row0_1;  row0_1 <= row0_2;  row0_2 <= gray_c;
        row1_0 <= row1_1;  row1_1 <= row1_2;  row1_2 <= lb0_data;
        row2_0 <= row2_1;  row2_1 <= row2_2;  row2_2 <= lb1_data;

        // update line buffers
        linebuf1[col_cnt] <= linebuf0[col_cnt];
        linebuf0[col_cnt] <= gray_c;
    end
end

//Calculate Sobel gradients
wire signed [14:0] Gx_w = ( -$signed({1'b0, row2_0}) + $signed({1'b0, row2_2}) )
                         + ( (-$signed({1'b0, row1_0}) + $signed({1'b0, row1_2})) <<< 1 )
                         + ( -$signed({1'b0, row0_0}) + $signed({1'b0, row0_2}) );

wire signed [14:0] Gy_w = ( -$signed({1'b0, row2_0}) - ($signed({1'b0, row2_1}) <<< 1) - $signed({1'b0, row2_2}) )
                         + (  $signed({1'b0, row0_0}) + ($signed({1'b0, row0_1}) <<< 1) + $signed({1'b0, row0_2}) );

//Save kernels
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        Gx_r <= 0;
        Gy_r <= 0;
    end else begin
        Gx_r <= Gx_w;
        Gy_r <= Gy_w;
    end
end

//Absolute value of kernels
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        Gx_abs_r <= 0;
        Gy_abs_r <= 0;
    end else begin
        Gx_abs_r <= Gx_r[14] ? (~Gx_r + 1'b1) : Gx_r;
        Gy_abs_r <= Gy_r[14] ? (~Gy_r + 1'b1) : Gy_r;
    end
end

//Manhattan magnitude
always @(posedge clk or negedge rstn) begin
    if (!rstn)
        G_abs_r <= 0;
    else
        G_abs_r <= Gx_abs_r + Gy_abs_r;
end

//Scale down and clamp to 12 bits
always @(posedge clk or negedge rstn) begin
    if (!rstn)
        sobel_out <= 0;
    else begin
        if (G_abs_r[14]) //"quarter of max intensity"
            sobel_out <= 12'hFFF;
        else
            sobel_out <= G_abs_r[13:2]; //"medium" intensity
    end
end


//Emboss filter
reg [11:0] emboss_out;
reg [11:0] emboss_dly [1:(LATENCY - EMBOSS_LATENCY)];
reg signed [14:0] emboss_w_r;
reg signed [14:0] emboss_sum1, emboss_sum2;

//Matrix
always @(posedge clk) begin
    emboss_sum1 <= (-($signed({1'b0, row2_0}) <<< 1) - $signed({1'b0, row2_1}) - $signed({1'b0, row1_0}));
    emboss_sum2 <= (  $signed({1'b0, row1_2}) + $signed({1'b0, row0_1}) + ($signed({1'b0, row0_2}) <<< 1));
end
always @(posedge clk) begin
    emboss_w_r <= emboss_sum1 + emboss_sum2;
end

								
// Center signed result into [0-4095] 12 bits range
always @(posedge clk or negedge rstn) begin
    if (!rstn)
        emboss_out <= 0;
    else begin
         if      ((emboss_w_r + 15'sd2048) > 15'sd4095) emboss_out <= 12'hFFF;
        else if ((emboss_w_r + 15'sd2048) < 15'sd0)    emboss_out <= 12'h000;
        else                                           emboss_out <= (emboss_w_r + 15'sd2048);
    end
end

// Delay emboss_out by S-E cycles to match Sobel's pipeline
integer jj;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        for (jj = 1; jj <= (LATENCY - EMBOSS_LATENCY); jj = jj + 1)
            emboss_dly[jj] <= 0;
    end else begin
        emboss_dly[1] <= emboss_out;
        for (jj = 2; jj <= (LATENCY - EMBOSS_LATENCY); jj = jj + 1)
            emboss_dly[jj] <= emboss_dly[jj-1];
    end
end


//Filter switch
reg [8:0]  cooldown;
reg [2:0]  filter_active;
reg [1:0]  vsync_edge;
reg [19:0] bright_count;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        bright_count         <= 0;
        cooldown      <= 0;
        filter_active <= 0;
        vsync_edge    <= 0;
    end else begin
        vsync_edge <= {vsync_edge[0], vsync_in};
		
        if (de_in && right_half_raw && gray_dly[LATENCY][10])
			bright_count <= bright_count + 1;

        // Falling edge of vsync = end of frame
        if (vsync_edge[0] && !vsync_in) begin
            if (cooldown == 0) begin
                if (bright_count < THRESHOLD) begin
                    filter_active <= (filter_active == 3'd5) ? 3'd0 : filter_active + 1;
                    cooldown      <= COOLDOWN;
                end
            end else begin
                cooldown <= cooldown - 1;
            end
            bright_count <= 0;
        end
    end
end

//Output mux
wire [11:0] r2   = r_dly[LATENCY];
wire [11:0] g2   = g_dly[LATENCY];
wire [11:0] b2   = b_dly[LATENCY];
wire [11:0] gr2  = gray_dly[LATENCY];

wire [11:0] sel_r, sel_g, sel_b;

assign sel_r = (filter_active == 3'd1) ? 12'hFFF - r2   :   // invert
               (filter_active == 3'd2) ? gr2             :   // grayscale
               (filter_active == 3'd3) ? b2              :   // channel rotate
               (filter_active == 3'd4) ? sobel_out       :   // Sobel
               (filter_active == 3'd5) ? emboss_dly[LATENCY - EMBOSS_LATENCY]      :   // Emboss
               r2;                                            // bypass

assign sel_g = (filter_active == 3'd1) ? 12'hFFF - g2   :
               (filter_active == 3'd2) ? gr2             :
               (filter_active == 3'd3) ? r2              :
               (filter_active == 3'd4) ? sobel_out       :
               (filter_active == 3'd5) ? emboss_dly[LATENCY - EMBOSS_LATENCY]      :
               g2;

assign sel_b = (filter_active == 3'd1) ? 12'hFFF - b2   :
               (filter_active == 3'd2) ? gr2             :
               (filter_active == 3'd3) ? g2              :
               (filter_active == 3'd4) ? sobel_out       :
               (filter_active == 3'd5) ? emboss_dly[LATENCY - EMBOSS_LATENCY]      :
               b2;

// Left half always bypass; right half gets selected filter
assign r_out = right_half ? sel_r : r2;
assign g_out = right_half ? sel_g : g2;
assign b_out = right_half ? sel_b : b2;

endmodule