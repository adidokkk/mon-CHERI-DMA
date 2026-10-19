//////////////////////////////////////////////////////////////////////////////////////////////////
// mCD_busM.sv
//
// Author: Giovanni Sirtori <gs86@rice.edu>
//
// Description: Implements a bus master interface through
// which it reads from / writes to memory.
//
// A component of the mon-CHERI-DMA project.
// https://github.com/adidokkk/mon-CHERI-DMA
//
// Copyright (C) 2025-26 Rice University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License"); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
//////////////////////////////////////////////////////////////////////////////////////////////////

import mCD_pkg::*;
module mCD_busM (
    input logic clk,
    input logic rst_n,

    // from mmr
    input logic [DATA_W-2:0] len,
    input logic start,
    input logic cl_irq,

    // from capDec
    input logic [DATA_W-1:0] src_addr,
    input logic [DATA_W-1:0] dst_addr,

    // from capCheck
    input logic errCheck,
    input logic pres_cap,

    output logic done,  // interrupt request to CPU
    output logic errBus,
    output logic [DATA_W-1:0] errBus_addr,

    ibex_mem_if.master bus_m
);
  typedef enum logic [1:0] {
    IDLE,
    READ,
    WRITE,
    ERROR
  } busm_state_e;
  busm_state_e state, next_state;

  logic new_tag;
  generate
    if (CHERI_EN) assign new_tag = pres_cap && bus_m.data_rdata_i[BusWidth-1];
    else assign new_tag = 'x;
  endgenerate

  logic [BusWidth-1:0] rdata_buff[DEPTH_RBUFF];
  logic [RBUFFWidth-1:0] buff_idx_rd, buff_idx_wr;
  logic [BusWidth-1:0] new_line;
  logic [DATA_W-2:0] src_ptr, dst_ptr;
  logic [DATA_W-2:0] valid_count_rd, valid_count_wr;
  logic [DATA_W-2:0] len_words;
  assign new_line = CHERI_EN ? {new_tag, bus_m.data_rdata_i[BusWidth-2:0]} : bus_m.data_rdata_i;

  logic [2:0] offset_rd, offset_wr;
  assign offset_rd = ((next_state == READ) && bus_m.data_gnt_i) ? 3'd4 : '0;
  assign offset_wr = ((state == WRITE) && bus_m.data_gnt_i) ? 3'd4 : '0;

  logic success, full_rd, full_wr;
  logic switch_rd, switch_wr;
  logic we_buff, valid_buff;
  assign len_words = len >> 2;
  assign switch_rd = (!valid_count_rd[RBUFFWidth-1:0] && |valid_count_rd && full_rd) ||
                     ((src_ptr==len-3'd4) && (valid_count_rd==len_words));

  logic new_start;
  assign new_start = start && (!CHERI_EN || !errCheck);

  // registered in `mCD.sv`
  assign done = (CHERI_EN && errCheck) || errBus || success;
  assign errBus = bus_m.data_rvalid_i && bus_m.data_err_i;
  assign errBus_addr = bus_m.data_we_o ? (dst_addr + (valid_count_wr<<2)) :
                                         (src_addr + (valid_count_rd<<2));

  always_comb begin : TRANSITION
    next_state = state;

    case (state)
      IDLE:  if (new_start) next_state = READ;
      READ:  if (switch_rd) next_state = WRITE;
      WRITE: if (success) next_state = IDLE;
 else if (switch_wr) next_state = READ;
      ERROR: if (cl_irq) next_state = new_start ? READ : IDLE;

      default: next_state = ERROR;
    endcase

    if (errBus) next_state = ERROR;
  end

  always_ff @(posedge clk) begin : SYNC
    if (!rst_n) state <= IDLE;
    else state <= next_state;
  end

  always_ff @(posedge clk) begin : OUTPUT
    if (!rst_n) begin
      {src_ptr, dst_ptr} <= '0;
      {we_buff, full_rd, full_wr, valid_buff} <= '0;
      {buff_idx_rd, buff_idx_wr, valid_count_rd, valid_count_wr} <= '0;
      {success, switch_wr} <= '0;
      rdata_buff <= '{default: '0};
      bus_m.resetMaster_o();
    end else begin
      bus_m.data_be_o <= '1;
      switch_wr <= 0;
      success <= 0;  // single-cycle pulse
      {full_rd, full_wr} <= '0;

      unique case (next_state)
        IDLE: begin
          bus_m.data_req_o <= 0;
          bus_m.data_we_o <= 'x;
          bus_m.data_addr_o <= 'x;
          bus_m.data_wdata_o <= 'x;
          bus_m.data_is_cap_o <= 'x;

          {src_ptr, dst_ptr} <= '0;
          valid_buff <= 0;
          {buff_idx_rd, buff_idx_wr, valid_count_rd, valid_count_wr} <= '0;
        end
        READ: begin
          bus_m.data_req_o <= 1;
          bus_m.data_we_o <= 0;
          bus_m.data_addr_o <= (((src_ptr + offset_rd) < len) && ((buff_idx_rd + 2'd2) < DEPTH_RBUFF)) ? src_addr + src_ptr + offset_rd : bus_m.data_addr_o;
          bus_m.data_wdata_o <= 'x;
          bus_m.data_is_cap_o <= 0;

          valid_buff <= 0;
          buff_idx_wr <= 0;

          // shouldn't update values below if address stays the same!

          src_ptr <= (bus_m.data_gnt_i && bus_m.data_req_o && (src_ptr + offset_rd < len) && ((buff_idx_rd + 1'd1) < DEPTH_RBUFF-1)) ? (src_ptr + 3'd4) : src_ptr;
          if (bus_m.data_rvalid_i) begin
            we_buff <= state==READ;
            if (we_buff && ((src_ptr + offset_rd) <= len)) begin
              rdata_buff[buff_idx_rd] <= new_line;
              buff_idx_rd <= &buff_idx_rd ? '0 : buff_idx_rd + 1'b1;
              valid_count_rd <= valid_count_rd + 1'b1;
              full_rd <= &buff_idx_rd;
            end
          end
        end
        WRITE: begin
          we_buff <= 0;
          bus_m.data_req_o <= (dst_ptr < len);
          bus_m.data_we_o <= 1;
          bus_m.data_addr_o <= &buff_idx_wr ? bus_m.data_addr_o : dst_addr + dst_ptr;
          bus_m.data_wdata_o <= &buff_idx_wr ? bus_m.data_wdata_o : rdata_buff[buff_idx_wr+(state==WRITE)];
          bus_m.data_is_cap_o <= &buff_idx_wr ? bus_m.data_is_cap_o : rdata_buff[buff_idx_wr+(state==WRITE)][BusWidth-1];

          valid_buff <= bus_m.data_rvalid_i && state==WRITE;
          valid_count_wr <= bus_m.data_rvalid_i && valid_buff ? ((!valid_count_wr[RBUFFWidth-1:0] && |valid_count_wr && full_wr) ? valid_count_wr : valid_count_wr + 1'b1) : valid_count_wr;
          success <= ((valid_count_wr == len_words - 1'b1) && bus_m.data_rvalid_i);
          if (bus_m.data_gnt_i && bus_m.data_req_o) begin
            if (!valid_count_wr[RBUFFWidth-1:0] && |valid_count_wr && full_wr) switch_wr <= 1;
            else if (!(&buff_idx_wr)) begin
              dst_ptr <= dst_ptr + 3'd4;
              buff_idx_wr <= buff_idx_wr + (state == WRITE);
            end else full_wr <= &buff_idx_wr;
          end
        end
        ERROR: begin
          bus_m.data_req_o <= 0;
          bus_m.data_we_o <= 'x;
          bus_m.data_addr_o <= 'x;
          bus_m.data_wdata_o <= 'x;
          bus_m.data_is_cap_o <= 'x;
          valid_buff <= 0;

          if (cl_irq && new_start) begin
            {src_ptr, dst_ptr} <= '0;
            {buff_idx_rd, buff_idx_wr, valid_count_rd, valid_count_wr} <= '0;
          end
        end
      endcase
    end
  end

endmodule
