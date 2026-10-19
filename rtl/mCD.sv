//////////////////////////////////////////////////////////////////////////////////////////////////
// mCD.sv
//
// Author: Giovanni Sirtori <gs86@rice.edu>
//
// Description: mCD top-level module.
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
module mCD (
    input logic clk,
    input logic rst_n,

    output logic irq,  // interrupt request to CPU

    ibex_mem_if.master bus_m,
    ibex_mem_if.slave  bus_s
);
  logic [CapWidth-1:0] src_rcap, dst_rcap;
  logic [DATA_W-2:0] len;
  logic start, done, cl_irq;
  cap_t src_cap, dst_cap;
  logic errCheck, errBus;
  logic [ErrBits-1:0] errCheck_code;
  logic [DATA_W-1:0] errCheck_addr, errBus_addr;
  logic pres_cap;

  logic err, err_comb;
  logic [ErrBits-1:0] err_code, err_code_comb;
  logic [DATA_W-1:0] err_addr, err_addr_comb;
  // latch busM's outputs, clear on cl_irq
  always_ff @(posedge clk)
    if (!rst_n) {irq, err, err_code, err_addr} <= 0;
    else begin
      irq <= !cl_irq && (done || irq);
      err <= !cl_irq && (err_comb || err);
      err_code <= cl_irq ? '0 : (err_comb ? err_code_comb : err_code);
      err_addr <= cl_irq ? '0 : (err_comb ? err_addr_comb : err_addr);
    end
  assign err_comb = errCheck || errBus;
  assign err_code_comb = errBus ? ERR_BUS : errCheck_code;
  assign err_addr_comb = errBus ? errBus_addr : errCheck_addr;

  generate
    if (CHERI_EN) begin : gen_CHERI
      mCD_mmr u_mmr (
          .clk,
          .rst_n,
          .err,
          .err_code,
          .err_addr,

          .src_rcap,
          .dst_rcap,
          .len,
          .start,
          .cl_irq,

          .bus_s
      );

      mCD_capDec u_capDec_src (
          .raw_cap(src_rcap),

          .cap(src_cap)
      );

      mCD_capDec u_capDec_dst (
          .raw_cap(dst_rcap),

          .cap(dst_cap)
      );

      mCD_capCheck u_capCheck (
          .len,
          .start,
          .src_cap,
          .dst_cap,

          .errCheck,
          .errCheck_code,
          .errCheck_addr,
          .pres_cap
      );
    end else begin : gen_noCHERI
      mCD_mmr u_mmr (
          .clk,
          .rst_n,
          .err,
          .err_code(),
          .err_addr,

          .src_rcap,
          .dst_rcap,
          .len,
          .start,
          .cl_irq,

          .bus_s
      );
    end
  endgenerate

  mCD_busM u_busM (
      .clk,
      .rst_n,
      .len,
      .start,
      .cl_irq,
      .src_addr(src_rcap[DATA_W-1:0]),
      .dst_addr(dst_rcap[DATA_W-1:0]),
      .errCheck,
      .pres_cap,

      .done,
      .errBus,
      .errBus_addr,

      .bus_m
  );

endmodule
