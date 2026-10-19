//////////////////////////////////////////////////////////////////////////////////////////////////
// mCD_pkg.sv
//
// Author: Giovanni Sirtori <gs86@rice.edu>
//
// Description: mon-CHERI-DMA project's package.
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

`ifndef MCD_CHERI_EN
`define MCD_CHERI_EN 1
`endif

`timescale 1ns / 1ps
package mCD_pkg;
  // -------------------------Parameters-------------------------
  parameter int unsigned CHERI_EN = `MCD_CHERI_EN;  // 1 = enable CHERI, 0 = disable CHERI

  parameter int unsigned ADDR_W = 32;
  parameter int unsigned DATA_W = 32;
  parameter int unsigned DEPTH_RBUFF = 8;
  parameter logic [3:0] EXPRESET = 4'hF;
  parameter logic [4:0] EXPFULL = 5'h18;

  localparam int unsigned RegStride = DATA_W / 8;
  localparam int unsigned RegBits = $clog2(RegStride);
  localparam int unsigned BusWidth = DATA_W + CHERI_EN;
  localparam int unsigned CapWidth = CHERI_EN ? DATA_W * 2 + 2 : DATA_W;
  localparam int unsigned RBUFFWidth = $clog2(DEPTH_RBUFF);
  // -------------------------mCD Typedefs-------------------------
  typedef struct {
    logic              tag;
    logic              is_unsl;  // cap is unsealed
    logic [ADDR_W-1:0] addr;
    logic [ADDR_W-1:0] base;     // inclusive lower bound
    logic [ADDR_W:0]   top;      // exclusive upper bound
    logic [11:0]       perms;    // arch permissions (see below)
    logic [3:0]        otype;    // obj types for sealing capabilities
  } cap_t;

  typedef enum logic [ADDR_W-1:0] {
    SRC_CAP_LO       = (ADDR_W)'(0 * RegStride),
    SRC_CAP_HI       = (ADDR_W)'(1 * RegStride),
    DST_CAP_LO       = (ADDR_W)'(2 * RegStride),
    DST_CAP_HI       = (ADDR_W)'(3 * RegStride),
    CHERI_CTRL       = (ADDR_W)'(4 * RegStride),
    CHERI_STATUS     = (ADDR_W)'(5 * RegStride),
    CHERI_FAULT_ADDR = (ADDR_W)'(6 * RegStride)
  } mcd_desc_cheri_e;

  typedef enum logic [ADDR_W-1:0] {
    SRC_CAP    = (ADDR_W)'(0 * RegStride),
    DST_CAP    = (ADDR_W)'(1 * RegStride),
    CTRL       = (ADDR_W)'(2 * RegStride),
    STATUS     = (ADDR_W)'(3 * RegStride),
    FAULT_ADDR = (ADDR_W)'(4 * RegStride)
  } mcd_desc_e;

  // Extracted from §7.12-13 of
  // https://cheriot.org/cheriot-sail/cheriot-architecture.pdf
  typedef enum logic [4:0] {
    GL,  // GLOBAL
    LG,  // PERMIT_LOAD_GLOBAL
    SD,  // PERMIT_STORE
    LM,  // PERMIT_LOAD_MUTABLE
    SL,  // PERMIT_STORE_LOCAL_CAPABILITY
    LD,  // PERMIT_LOAD
    MC,  // PERMIT_LOAD_STORE_CAPABILITY
    SR,  // PERMIT_ACCESS_SYSTEM_REGISTERS
    EX,  // PERMIT_EXECUTE
    US,  // PERMIT_UNSEAL
    SE,  // PERMIT_SEAL
    U0   // USER_PERM0
  } mcd_perms_e;

  typedef enum logic [2:0] {
    ERR_GRAN,    // src/dst/len not 4-byte aligned
    ERR_TAG,     // tag not set
    ERR_SEAL,    // capability sealed
    ERR_PERMLD,  // PERMIT_LOAD violation
    ERR_PERMSD,  // PERMIT_STORE violation
    ERR_PERMMC,  // PERMIT_STORE_CAPABILITY violation
    ERR_BOUNDS,  // addr out of bounds
    ERR_BUS      // bus error (from busM)
  } mcd_errs_e;
  localparam int unsigned ErrBits = $bits(mcd_errs_e);

endpackage
