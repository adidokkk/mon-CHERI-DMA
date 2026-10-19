//////////////////////////////////////////////////////////////////////////////////////////////////
// mCD_mmr.sv
//
// Author: Giovanni Sirtori <gs86@rice.edu>
//
// Description: Implements an bus slave interface through which
// the host CPU programs transfer descriptors and reads status.
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
module mCD_mmr (
    input logic clk,
    input logic rst_n,

    // raw caps to capDec
    output logic [CapWidth-1:0] src_rcap,
    output logic [CapWidth-1:0] dst_rcap,
    output logic [DATA_W-2:0] len,  // length in bytes

    output logic start,
    output logic cl_irq, // clear interrupt request

    // from mCD (top module)
    input logic               err,
    input logic [ErrBits-1:0] err_code,
    input logic [ DATA_W-1:0] err_addr,

    // bus slave interface
    ibex_mem_if.slave bus_s
);
  logic rw_valid;
  assign rw_valid = bus_s.data_req_o && &bus_s.data_be_o;

  generate
    if (CHERI_EN) begin : gen_CHERI
      always_ff @(posedge clk) begin
        if (!rst_n) begin
          {src_rcap, dst_rcap, len, start, cl_irq} <= '0;
          bus_s.resetSlave_o();
        end else begin
          bus_s.data_err_i    <= 0;  // decode never signals errors
          start               <= 0;  // single-cycle pulse
          cl_irq              <= 0;  // single-cycle pulse

          bus_s.data_gnt_i    <= 0;
          bus_s.data_rvalid_i <= 0;
          if (rw_valid) begin
            bus_s.data_gnt_i    <= 1;
            bus_s.data_rvalid_i <= 1;

            if (!bus_s.data_we_o) begin
              case (bus_s.data_addr_o)
                SRC_CAP_LO:       bus_s.data_rdata_i <= (DATA_W + 1)'(src_rcap[DATA_W:0]);
                SRC_CAP_HI:       bus_s.data_rdata_i <= (DATA_W + 1)'(src_rcap[DATA_W+1+:DATA_W+1]);
                DST_CAP_LO:       bus_s.data_rdata_i <= (DATA_W + 1)'(dst_rcap[DATA_W:0]);
                DST_CAP_HI:       bus_s.data_rdata_i <= (DATA_W + 1)'(dst_rcap[DATA_W+1+:DATA_W+1]);
                CHERI_CTRL:       bus_s.data_rdata_i <= (DATA_W + 1)'({len, start, cl_irq});
                CHERI_STATUS:     bus_s.data_rdata_i <= (DATA_W + 1)'({err, err_code});
                CHERI_FAULT_ADDR: bus_s.data_rdata_i <= (DATA_W + 1)'(err_addr);

                default: bus_s.data_rdata_i <= '0;
              endcase
            end else if (bus_s.data_we_o) begin
              case (bus_s.data_addr_o)
                SRC_CAP_LO: src_rcap[DATA_W:0] <= bus_s.data_wdata_o;
                SRC_CAP_HI: src_rcap[DATA_W+1+:DATA_W+1] <= bus_s.data_wdata_o;
                DST_CAP_LO: dst_rcap[DATA_W:0] <= bus_s.data_wdata_o;
                DST_CAP_HI: dst_rcap[DATA_W+1+:DATA_W+1] <= bus_s.data_wdata_o;
                CHERI_CTRL: {len, start, cl_irq} <= bus_s.data_wdata_o;

                default: ;
              endcase
            end
          end
        end
      end
    end else begin : gen_noCHERI
      always_ff @(posedge clk) begin
        if (!rst_n) begin
          {src_rcap, dst_rcap, len, start, cl_irq} <= '0;
          bus_s.resetSlave_o();
        end else begin
          bus_s.data_err_i    <= 0;  // decode never signals errors
          start               <= 0;  // single-cycle pulse
          cl_irq              <= 0;  // single-cycle pulse

          bus_s.data_gnt_i    <= 0;
          bus_s.data_rvalid_i <= 0;
          if (rw_valid) begin
            bus_s.data_gnt_i    <= 1;
            bus_s.data_rvalid_i <= 1;

            if (!bus_s.data_we_o) begin
              case (bus_s.data_addr_o)
                SRC_CAP:    bus_s.data_rdata_i <= (DATA_W)'(src_rcap[DATA_W-1:0]);
                DST_CAP:    bus_s.data_rdata_i <= (DATA_W)'(dst_rcap[DATA_W-1:0]);
                CTRL:       bus_s.data_rdata_i <= (DATA_W)'({len, start, cl_irq});
                STATUS:     bus_s.data_rdata_i <= (DATA_W)'(err);
                FAULT_ADDR: bus_s.data_rdata_i <= (DATA_W)'(err_addr[DATA_W-1:0]);

                default: bus_s.data_rdata_i <= '0;
              endcase
            end else if (bus_s.data_we_o) begin
              case (bus_s.data_addr_o)
                SRC_CAP: src_rcap[DATA_W-1:0] <= bus_s.data_wdata_o;
                DST_CAP: dst_rcap[DATA_W-1:0] <= bus_s.data_wdata_o;
                CTRL:    {len, start, cl_irq} <= bus_s.data_wdata_o;

                default: ;
              endcase
            end
          end
        end
      end
    end
  endgenerate

endmodule
