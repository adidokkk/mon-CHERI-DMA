//////////////////////////////////////////////////////////////////////////////////////////////////
// mCD_capCheck.sv
//
// Author: Giovanni Sirtori <gs86@rice.edu>
//
// Description: Checks whether capability is rightful.
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

//  Checks in order of priority:
//      0. src/dst/len 8-byte aligned
//      1. tag (tag set)
//      2. is_unsl (cap unsealed)
//      3. permission: perms[curr_op] is set
//      4. bounds: addr >= base  &&  addr+len <= top

import mCD_pkg::*;
module mCD_capCheck (
    // from mmr
    input logic [DATA_W-2:0] len,  // transfer length in bytes
    input logic start,

    // from capDec
    input cap_t src_cap,
    input cap_t dst_cap,

    // status inputs to mmr
    output logic               errCheck,       // 1 = error, 0 = success
    output logic [ErrBits-1:0] errCheck_code,
    output logic [ DATA_W-1:0] errCheck_addr,  // src addr has priority

    output logic pres_cap  // 1 = both caps have MC permission, 0 = otherwise
);
  logic src_obound, dst_obound;

  // upper bound is DATA_W+1 (exclusive)
  assign src_obound = (src_cap.addr < src_cap.base) ||
                        ((DATA_W+1)'(src_cap.addr) + (DATA_W+1)'(len) > src_cap.top);
  assign dst_obound = (dst_cap.addr < dst_cap.base) ||
                        ((DATA_W+1)'(dst_cap.addr) + (DATA_W+1)'(len) > dst_cap.top);

  assign pres_cap = src_cap.perms[MC] && dst_cap.perms[MC];

  // busM gates the launch on the live value
  always_latch begin
    if (start) begin
      if (|src_cap.addr[1:0] || |dst_cap.addr[1:0] || |len[1:0]) begin
        errCheck <= 1;
        errCheck_code <= ERR_GRAN;
        errCheck_addr <= |src_cap.addr[1:0] ? src_cap.addr : (|dst_cap.addr[1:0] ? dst_cap.addr : len);
      end else if (!src_cap.tag || !dst_cap.tag) begin
        errCheck <= 1;
        errCheck_code <= ERR_TAG;
        errCheck_addr <= src_cap.tag ? dst_cap.addr : src_cap.addr;
      end else if (!src_cap.is_unsl || !dst_cap.is_unsl) begin
        errCheck <= 1;
        errCheck_code <= ERR_SEAL;
        errCheck_addr <= src_cap.is_unsl ? dst_cap.addr : src_cap.addr;
      end else if (!src_cap.perms[LD]) begin
        errCheck <= 1;
        errCheck_code <= ERR_PERMLD;
        errCheck_addr <= src_cap.addr;
      end else if (!dst_cap.perms[SD]) begin
        errCheck <= 1;
        errCheck_code <= ERR_PERMSD;
        errCheck_addr <= dst_cap.addr;
      end else if (src_cap.perms[MC] && !dst_cap.perms[MC]) begin
        errCheck <= 1;
        errCheck_code <= ERR_PERMMC;
        errCheck_addr <= dst_cap.addr;
      end else if (src_obound || dst_obound) begin
        errCheck <= 1;
        errCheck_code <= ERR_BOUNDS;
        errCheck_addr <= src_obound ? src_cap.addr : dst_cap.addr;
      end else begin
        errCheck <= 0;
        errCheck_code <= 'x;
        errCheck_addr <= 'x;
      end
    end
  end

endmodule
