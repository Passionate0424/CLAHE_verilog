// ============================================================================
// CLAHE Banked RAM Module (4-Bank Interleaved)
//
// Function:
//   - Implements 4 physical memory banks to store 64 logical tiles.
//   - Uses Checkerboard Interleaving to allow conflict-free parallel access
//     to 2x2 neighbor windows.
//   - Provides Crossbar logic to route data to TL/TR/BL/BR ports.
//
// Mapping:
//   - Bank ID = {tile_y[0], tile_x[0]}
//   - Bank 0: Even X, Even Y
//   - Bank 1: Odd X, Even Y
//   - Bank 2: Even X, Odd Y
//   - Bank 3: Odd X, Odd Y
//
// Author: Antigravity
// Date: 2025-12-06
// ============================================================================

`timescale 1ns / 1ps

module clahe_ram_banked #(
        parameter TILE_H_BITS = 3,       // Horizontal tile count bits (3 for 8)
        parameter TILE_V_BITS = 3,       // Vertical tile count bits (3 for 8)
        parameter TILE_NUM_BITS = 6,     // Total tile index bits (6 for 64)
        parameter BINS = 256,
        parameter DEPTH_PER_BANK = 4096  // Default for 8x8: 16 tiles/bank * 256 bins
    )(
        input  wire        pclk,
        input  wire        rst_n,

        // Ping-Pong Control
        input  wire        ping_pong_flag,
        input  wire        clear_start,
        input  wire        clear_done,

        // ====================================================================
        // Histogram Statistic Interface (Write/Read Port A)
        // ====================================================================
        input  wire [TILE_NUM_BITS-1:0]  hist_rd_tile_idx,
        input  wire [TILE_NUM_BITS-1:0]  hist_wr_tile_idx,
        input  wire [7:0]   hist_wr_addr,
        input  wire [15:0]  hist_wr_data,
        input  wire         hist_wr_en,
        input  wire [7:0]   hist_rd_addr,
        output reg  [15:0]  hist_rd_data,

        // ====================================================================
        // CDF Calculation Interface (Read/Write Port A/B)
        // ====================================================================
        // Shared interface for reading Histogram (from Hist RAM) and writing CDF (to Mapping RAM)
        input  wire [TILE_NUM_BITS-1:0]  cdf_tile_idx,
        input  wire [7:0]   cdf_addr,
        input  wire [7:0]   cdf_wr_data, // 8-bit CDF data
        input  wire         cdf_wr_en,
        input  wire         cdf_rd_en,
        output reg  [15:0]  cdf_rd_data, // 16-bit Histogram data

        // ====================================================================
        // Mapping Interface (Parallel Read Port B)
        // ====================================================================
        input  wire [TILE_NUM_BITS-1:0]  mapping_tl_tile_idx,
        input  wire [TILE_NUM_BITS-1:0]  mapping_tr_tile_idx,
        input  wire [TILE_NUM_BITS-1:0]  mapping_bl_tile_idx,
        input  wire [TILE_NUM_BITS-1:0]  mapping_br_tile_idx,
        input  wire [7:0]   mapping_addr,
        output reg  [7:0]   mapping_tl_rd_data,
        output reg  [7:0]   mapping_tr_rd_data,
        output reg  [7:0]   mapping_bl_rd_data,
        output reg  [7:0]   mapping_br_rd_data
    );

    // ========================================================================
    // Internal Signals & Types
    // ========================================================================

    // Address decoding function
    function [1:0] get_bank_id;
        input [TILE_NUM_BITS-1:0] idx;
        reg [TILE_H_BITS-1:0] tx;
        reg [TILE_V_BITS-1:0] ty;
        begin
            tx = idx[TILE_H_BITS-1:0];
            ty = idx[TILE_NUM_BITS-1:TILE_H_BITS];
            get_bank_id = {ty[0], tx[0]}; // Bank ID = {OddY, OddX}
        end
    endfunction

    function [11:0] get_bank_addr; // 4 bits tile index in bank + 8 bits bin
        input [TILE_NUM_BITS-1:0] idx;
        input [7:0] bin_addr;
        reg [TILE_H_BITS-1:0] tx;
        reg [TILE_V_BITS-1:0] ty;
        reg [TILE_H_BITS-2:0] inner_tx; // tx >> 1
        reg [TILE_V_BITS-2:0] inner_ty; // ty >> 1
        begin
            tx = idx[TILE_H_BITS-1:0];
            ty = idx[TILE_NUM_BITS-1:TILE_H_BITS];
            inner_tx = tx[TILE_H_BITS-1:1];
            inner_ty = ty[TILE_V_BITS-1:1];
            // Inner index = inner_ty * (TILE_H/2) + inner_tx
            // For 8x8: TILE_H=8, TILE_H/2=4. inner_ty*4 + inner_tx.
            get_bank_addr = {inner_ty, inner_tx, bin_addr};
        end
    endfunction

    // RAM Signals
    wire [11:0] mapping_addr_b0, mapping_addr_b1, mapping_addr_b2, mapping_addr_b3;

    // Decode Mapping Addresses (All 4 banks are accessed)
    assign mapping_addr_b0 = get_bank_addr(
               (get_bank_id(mapping_tl_tile_idx) == 0) ? mapping_tl_tile_idx :
               (get_bank_id(mapping_tr_tile_idx) == 0) ? mapping_tr_tile_idx :
               (get_bank_id(mapping_bl_tile_idx) == 0) ? mapping_bl_tile_idx : mapping_br_tile_idx,
               mapping_addr
           );
    assign mapping_addr_b1 = get_bank_addr(
               (get_bank_id(mapping_tl_tile_idx) == 1) ? mapping_tl_tile_idx :
               (get_bank_id(mapping_tr_tile_idx) == 1) ? mapping_tr_tile_idx :
               (get_bank_id(mapping_bl_tile_idx) == 1) ? mapping_bl_tile_idx : mapping_br_tile_idx,
               mapping_addr
           );
    assign mapping_addr_b2 = get_bank_addr(
               (get_bank_id(mapping_tl_tile_idx) == 2) ? mapping_tl_tile_idx :
               (get_bank_id(mapping_tr_tile_idx) == 2) ? mapping_tr_tile_idx :
               (get_bank_id(mapping_bl_tile_idx) == 2) ? mapping_bl_tile_idx : mapping_br_tile_idx,
               mapping_addr
           );
    assign mapping_addr_b3 = get_bank_addr(
               (get_bank_id(mapping_tl_tile_idx) == 3) ? mapping_tl_tile_idx :
               (get_bank_id(mapping_tr_tile_idx) == 3) ? mapping_tr_tile_idx :
               (get_bank_id(mapping_bl_tile_idx) == 3) ? mapping_bl_tile_idx : mapping_br_tile_idx,
               mapping_addr
           );

    // RAM Instantiation (Inferred Block RAM)
    reg [15:0] ram_0_0 [0:4095]; // Set 0, Bank 0
    reg [15:0] ram_0_1 [0:4095];
    reg [15:0] ram_0_2 [0:4095];
    reg [15:0] ram_0_3 [0:4095];

    reg [15:0] ram_1_0 [0:4095]; // Set 1, Bank 0
    reg [15:0] ram_1_1 [0:4095];
    reg [15:0] ram_1_2 [0:4095];
    reg [15:0] ram_1_3 [0:4095];

    // Read Outputs
    reg [15:0] rdata_0_0_p0, rdata_0_1_p0, rdata_0_2_p0, rdata_0_3_p0;
    reg [15:0] rdata_1_0_p0, rdata_1_1_p0, rdata_1_2_p0, rdata_1_3_p0;

    reg [15:0] rdata_0_0_p1, rdata_0_1_p1, rdata_0_2_p1, rdata_0_3_p1;
    reg [15:0] rdata_1_0_p1, rdata_1_1_p1, rdata_1_2_p1, rdata_1_3_p1;

    // ========================================================================
    // Logic for Histogram/CDF Access (Port A/Port 0)
    // ========================================================================
    wire [1:0]  curr_hist_bank = get_bank_id(hist_wr_en ? hist_wr_tile_idx : hist_rd_tile_idx);
    wire [11:0] curr_hist_addr = get_bank_addr(hist_wr_en ? hist_wr_tile_idx : hist_rd_tile_idx,
            hist_wr_en ? hist_wr_addr : hist_rd_addr);

    wire [1:0]  curr_cdf_bank  = get_bank_id(cdf_tile_idx);
    wire [11:0] curr_cdf_addr  = get_bank_addr(cdf_tile_idx, cdf_addr);

    always @(posedge pclk) begin
        // --- Set 0 Port 0 (Hist/CDF Wr/Rd) ---
        if (ping_pong_flag == 0) begin
            // Set 0 is Hist
            if (hist_wr_en) begin
                if (curr_hist_bank == 0)
                    ram_0_0[curr_hist_addr] <= hist_wr_data;
                if (curr_hist_bank == 1)
                    ram_0_1[curr_hist_addr] <= hist_wr_data;
                if (curr_hist_bank == 2)
                    ram_0_2[curr_hist_addr] <= hist_wr_data;
                if (curr_hist_bank == 3)
                    ram_0_3[curr_hist_addr] <= hist_wr_data;
            end
            rdata_0_0_p0 <= ram_0_0[curr_hist_addr];
            rdata_0_1_p0 <= ram_0_1[curr_hist_addr];
            rdata_0_2_p0 <= ram_0_2[curr_hist_addr];
            rdata_0_3_p0 <= ram_0_3[curr_hist_addr];
        end
        else begin
            // Set 0 is CDF Write / Mapping Read
            if (cdf_wr_en) begin
                if (curr_cdf_bank == 0)
                    ram_0_0[curr_cdf_addr] <= {8'd0, cdf_wr_data};
                if (curr_cdf_bank == 1)
                    ram_0_1[curr_cdf_addr] <= {8'd0, cdf_wr_data};
                if (curr_cdf_bank == 2)
                    ram_0_2[curr_cdf_addr] <= {8'd0, cdf_wr_data};
                if (curr_cdf_bank == 3)
                    ram_0_3[curr_cdf_addr] <= {8'd0, cdf_wr_data};
            end
            rdata_0_0_p0 <= ram_0_0[curr_cdf_addr];
            rdata_0_1_p0 <= ram_0_1[curr_cdf_addr];
            rdata_0_2_p0 <= ram_0_2[curr_cdf_addr];
            rdata_0_3_p0 <= ram_0_3[curr_cdf_addr];
        end

        // --- Set 1 Port 0 ---
        if (ping_pong_flag == 1) begin
            // Set 1 is Hist
            if (hist_wr_en) begin
                if (curr_hist_bank == 0)
                    ram_1_0[curr_hist_addr] <= hist_wr_data;
                if (curr_hist_bank == 1)
                    ram_1_1[curr_hist_addr] <= hist_wr_data;
                if (curr_hist_bank == 2)
                    ram_1_2[curr_hist_addr] <= hist_wr_data;
                if (curr_hist_bank == 3)
                    ram_1_3[curr_hist_addr] <= hist_wr_data;
            end
            rdata_1_0_p0 <= ram_1_0[curr_hist_addr];
            rdata_1_1_p0 <= ram_1_1[curr_hist_addr];
            rdata_1_2_p0 <= ram_1_2[curr_hist_addr];
            rdata_1_3_p0 <= ram_1_3[curr_hist_addr];
        end
        else begin
            // Set 1 is CDF Write / Mapping
            if (cdf_wr_en) begin
                if (curr_cdf_bank == 0)
                    ram_1_0[curr_cdf_addr] <= {8'd0, cdf_wr_data};
                if (curr_cdf_bank == 1)
                    ram_1_1[curr_cdf_addr] <= {8'd0, cdf_wr_data};
                if (curr_cdf_bank == 2)
                    ram_1_2[curr_cdf_addr] <= {8'd0, cdf_wr_data};
                if (curr_cdf_bank == 3)
                    ram_1_3[curr_cdf_addr] <= {8'd0, cdf_wr_data};
            end
            rdata_1_0_p0 <= ram_1_0[curr_cdf_addr];
            rdata_1_1_p0 <= ram_1_1[curr_cdf_addr];
            rdata_1_2_p0 <= ram_1_2[curr_cdf_addr];
            rdata_1_3_p0 <= ram_1_3[curr_cdf_addr];
        end

        // --- Port 1 (Mapping Read - Parallel) ---
        // Always read all 4 banks at mapping_addr
        rdata_0_0_p1 <= ram_0_0[mapping_addr_b0];
        rdata_0_1_p1 <= ram_0_1[mapping_addr_b1];
        rdata_0_2_p1 <= ram_0_2[mapping_addr_b2];
        rdata_0_3_p1 <= ram_0_3[mapping_addr_b3];

        rdata_1_0_p1 <= ram_1_0[mapping_addr_b0];
        rdata_1_1_p1 <= ram_1_1[mapping_addr_b1];
        rdata_1_2_p1 <= ram_1_2[mapping_addr_b2];
        rdata_1_3_p1 <= ram_1_3[mapping_addr_b3];
    end

    // ========================================================================
    // Read Data Muxing
    // ========================================================================
    always @(*) begin
        // Hist Read Output
        if (ping_pong_flag == 0)
        case (curr_hist_bank)
            0:
                hist_rd_data = rdata_0_0_p0;
            1:
                hist_rd_data = rdata_0_1_p0;
            2:
                hist_rd_data = rdata_0_2_p0;
            3:
                hist_rd_data = rdata_0_3_p0;
        endcase
        else
        case (curr_hist_bank)
            0:
                hist_rd_data = rdata_1_0_p0;
            1:
                hist_rd_data = rdata_1_1_p0;
            2:
                hist_rd_data = rdata_1_2_p0;
            3:
                hist_rd_data = rdata_1_3_p0;
        endcase

        // CDF Read Output
        if (ping_pong_flag == 1)
        case (curr_cdf_bank)
            0:
                cdf_rd_data = rdata_0_0_p0;
            1:
                cdf_rd_data = rdata_0_1_p0;
            2:
                cdf_rd_data = rdata_0_2_p0;
            3:
                cdf_rd_data = rdata_0_3_p0;
        endcase
        else
        case (curr_cdf_bank)
            0:
                cdf_rd_data = rdata_1_0_p0;
            1:
                cdf_rd_data = rdata_1_1_p0;
            2:
                cdf_rd_data = rdata_1_2_p0;
            3:
                cdf_rd_data = rdata_1_3_p0;
        endcase
    end

    // ========================================================================
    // Mapping Crossbar Logic (Port 1)
    // ========================================================================
    reg [7:0] raw_b0, raw_b1, raw_b2, raw_b3;
    always @(*) begin
        if (ping_pong_flag == 1) begin // Set 0 is Mapping
            raw_b0 = rdata_0_0_p1[7:0];
            raw_b1 = rdata_0_1_p1[7:0];
            raw_b2 = rdata_0_2_p1[7:0];
            raw_b3 = rdata_0_3_p1[7:0];
        end
        else begin // Set 1 is Mapping
            raw_b0 = rdata_1_0_p1[7:0];
            raw_b1 = rdata_1_1_p1[7:0];
            raw_b2 = rdata_1_2_p1[7:0];
            raw_b3 = rdata_1_3_p1[7:0];
        end
    end

    wire [1:0] tl_bank = get_bank_id(mapping_tl_tile_idx);

    always @(*) begin
        case (tl_bank)
            2'b00: begin
                mapping_tl_rd_data = raw_b0;
                mapping_tr_rd_data = raw_b1;
                mapping_bl_rd_data = raw_b2;
                mapping_br_rd_data = raw_b3;
            end
            2'b01: begin
                mapping_tl_rd_data = raw_b1;
                mapping_tr_rd_data = raw_b0;
                mapping_bl_rd_data = raw_b3;
                mapping_br_rd_data = raw_b2;
            end
            2'b10: begin
                mapping_tl_rd_data = raw_b2;
                mapping_tr_rd_data = raw_b3;
                mapping_bl_rd_data = raw_b0;
                mapping_br_rd_data = raw_b1;
            end
            2'b11: begin
                mapping_tl_rd_data = raw_b3;
                mapping_tr_rd_data = raw_b2;
                mapping_bl_rd_data = raw_b1;
                mapping_br_rd_data = raw_b0;
            end
        endcase
    end

endmodule
