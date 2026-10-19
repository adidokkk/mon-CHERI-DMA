//////////////////////////////////////////////////////////////////////////////////////////////////
// mCD_capDec.sv
//
// Author: Giovanni Sirtori <gs86@rice.edu>
//
// Description: Decodes fields from input capability passed by MMR.
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

//  raw_cap[65:32] = metadata:
//      [65]    tag
//      [64]    rsvd
//      [63:58] cperms    – compressed perms
//      [57:55] rotype    – raw object types
//      [54:51] exp       – raw exponent
//      [50:42] top_mant  – top mantissa
//      [41:33] base_mant – base mantissa
//      [32]    tag
//  raw_cap[31:0]  = addr

import mCD_pkg::*;
module mCD_capDec (
    // from mmr
    input logic [CapWidth-1:0] raw_cap,

    // decoded cap to capCheck
    output cap_t cap
);
  logic [5:0] cperms;
  logic [2:0] rotype;
  logic [3:0] exp;
  logic [8:0] top_mant;
  logic [8:0] base_mant;

  assign cperms    = raw_cap[CapWidth-3-:6];
  assign rotype    = raw_cap[CapWidth-9-:3];
  assign exp       = raw_cap[CapWidth-12-:4];
  assign top_mant  = raw_cap[CapWidth-16-:9];
  assign base_mant = raw_cap[CapWidth-25-:9];
  assign cap.tag   = raw_cap[CapWidth-1] && raw_cap[CapWidth/2-1];
  assign cap.addr  = raw_cap[CapWidth/2-2:0];

  // -------------------------------------------------------------------------
  // Capability permission encoding:

  //       Type                  Encoding           Implicit permissions
  // -------------------------------------------------------------------
  // Memory read-write        GL 1 1 SL LM LG       LD, MC, SD
  // Memory read-only         GL 1 0 1  LM LG       LD, MC
  // Memory write-only        GL 1 0 0  0  0        SD, MC
  // Memory data-only         GL 1 0 0  LD SD       None
  // Executable               GL 0 1 SR LM LG       EX, LD, MC
  // Sealing                  GL 0 0 U0 SE US       None

  // From §7.13 of https://cheriot.org/cheriot-sail/cheriot-architecture.pdf
  // -------------------------------------------------------------------------

  always_comb begin
    cap.perms = '0;
    cap.perms[GL] = cperms[5];

    priority casez (cperms[4:0])
      5'b11???: begin
        {cap.perms[SL], cap.perms[LM], cap.perms[LG]} = cperms[2:0];
        {cap.perms[LD], cap.perms[MC], cap.perms[SD]} = '1;
      end
      5'b101??: begin
        {cap.perms[LM], cap.perms[LG]} = cperms[1:0];
        {cap.perms[LD], cap.perms[MC]} = '1;
      end
      5'b10000: {cap.perms[SD], cap.perms[MC]} = '1;
      5'b100??: {cap.perms[LD], cap.perms[SD]} = cperms[1:0];
      5'b01???: begin
        {cap.perms[SR], cap.perms[LM], cap.perms[LG]} = cperms[2:0];
        {cap.perms[EX], cap.perms[LD], cap.perms[MC]} = '1;
      end
      5'b00???: {cap.perms[U0], cap.perms[SE], cap.perms[US]} = cperms[2:0];

      default: ;
    endcase
  end

  // -------------------------------------------------------------------------
  // Object Type: unsealed when 0, if sealed bit 3 is the EX permission.
  // 1-7 are executable caps, 9-15 are not executable.
  // -------------------------------------------------------------------------
  logic is_unsealed;
  assign is_unsealed = (rotype == '0);
  assign cap.otype   = is_unsealed ? '0 : {!cap.perms[EX], rotype};

  assign cap.is_unsl = is_unsealed;

  // -------------------------------------------------------------------------
  // Capability bounds: base is inclusive, top is exclusive.
  //
  // Base and top's mantissas capture bits [exp+8 : exp] of the actual bound,
  // while the bits above that come from addr.
  // NOTE: 'cb' and 'ct' serve for when capability spans a block boundary
  // (e.g. top_mant < base_mant means top lies in the next block).
  // -------------------------------------------------------------------------
  logic [22:0] a_top;
  logic [8:0] a_mid;
  logic cb;
  logic [1:0] ct;


  always_comb begin
    if (exp == EXPRESET) begin
      {a_top, a_mid, cb, ct} = '0;

      cap.base = {base_mant, '0};  // base = base_mant << 23;
      cap.top = {top_mant, '0};  // top = top_mant << 24;
    end else begin
      a_mid = cap.addr[exp+:9];
      a_top = cap.addr[31:0] >> (exp + 9);  // addr[31:exp+9]
      cb = (a_mid < base_mant) ? 0 : 1;
      ct = (a_mid < base_mant && top_mant >= base_mant) ? 2'b00 :
           (a_mid >= base_mant && top_mant < base_mant) ? 2'b10 : 2'b01;

      cap.base = {23'(a_top + cb - 1'b1), base_mant} << exp;
      cap.top = {1'b0, 23'(a_top + ct - 1'b1), top_mant} << exp;
    end
  end

endmodule
