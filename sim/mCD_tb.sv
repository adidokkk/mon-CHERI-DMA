////////////////////////////////////////////////////////////////////////////////////////////////////
// mCD_tb.sv
//
// Author: Giovanni Sirtori <gs86@rice.edu>
//
// Description: SystemVerilog testbench for mon-CHERI-DMA.
//
// Test scenarios:
//      T1  Basic copy                      (simple transfer with tag bits cleared)
//
//      T2  Basic copy with buff. altern.   (simple transfer with tag bits cleared)
//
//      T3  Tag preserving copy             (transfer that preserve tag bits)
//
//      T4  Out-of-bounds fault             (src capability tries to access restricted memory area)
//
//      T5  Permission fault                (src capability has no LD permission)
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
////////////////////////////////////////////////////////////////////////////////////////////////////

import mCD_pkg::*;
module mCD_tb;
  // ---------------------------------------------------------------------------
  //                              Parameters
  // ---------------------------------------------------------------------------
  parameter int unsigned CLK_PERIOD = 10;    // 10 ns = 100 MHz
  parameter int unsigned MEM_WORDS  = 512;   // testbench SRAM depth (words)
  parameter int unsigned TIMEOUT_CY = 2000;  // cycles before test is declared hung

  // ---------------------------------------------------------------------------
  //                         Permission Encoding
  //
  //       Type                  Encoding           Implicit permissions
  // -------------------------------------------------------------------
  // Memory read-write        GL 1 1 SL LM LG       LD, MC, SD
  // Memory read-only         GL 1 0 1  LM LG       LD, MC
  // Memory write-only        GL 1 0 0  0  0        SD, MC
  // Memory data-only         GL 1 0 0  LD SD       None
  // Executable               GL 0 1 SR LM LG       EX, LD, MC
  // Sealing                  GL 0 0 U0 SE US       None

  // From §7.13 of https://cheriot.org/cheriot-sail/cheriot-architecture.pdf
  // ---------------------------------------------------------------------------
  logic gl, sl, lm, lg, ld, sd, sr, u0, se, us;
  initial {gl, sl, lm, lg, ld, sd, sr, u0, se, us} = '0;

  typedef struct {
    logic [5:0] MEM_RW;
    logic [5:0] MEM_R;
    logic [5:0] MEM_W;
    logic [5:0] MEM_DATA;
    logic [5:0] EXEC;
    logic [5:0] SEAL;
  } cperms_t;

  cperms_t CPERMS;
  assign CPERMS.MEM_RW = {gl, 2'b11, sl, lm, lg};
  assign CPERMS.MEM_R = {gl, 3'b101, lm, lg};
  assign CPERMS.MEM_W = {gl, 1'b1, 4'b0};
  assign CPERMS.MEM_DATA = {gl, 3'b100, ld, sd};
  assign CPERMS.EXEC = {gl, 2'b01, sr, lm, lg};
  assign CPERMS.SEAL = {gl, 2'b0, u0, se, us};

  // ---------------------------------------------------------------------------
  //                              DUT Instantiation
  // ---------------------------------------------------------------------------
  logic clk, rst_n;
  logic irq;

  ibex_mem_if bus_m ();
  ibex_mem_if bus_s ();
  mCD dut (
      .clk,
      .rst_n,
      .irq,
      .bus_m(bus_s),
      .bus_s(bus_m)
  );

  // ---------------------------------------------------------------------------
  //                               Clock Generator
  // ---------------------------------------------------------------------------
  int clk_cycles = 0;

  initial begin
    clk = 1'b0;

    forever begin
      #(CLK_PERIOD / 2);
      clk = ~clk;

      if (clk) clk_cycles++;
    end
  end

  // ---------------------------------------------------------------------------
  //                                Memory Model
  //                           (with zero wait states)
  // ---------------------------------------------------------------------------
  logic [BusWidth-1:0] mem[MEM_WORDS];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mem <= '{default: '0};
      bus_s.resetSlave_o();
    end else begin
      bus_s.data_err_i <= 0;
      bus_s.data_gnt_i <= 0;
      bus_s.data_rvalid_i <= 0;

      if (bus_s.data_req_o) begin
        bus_s.data_gnt_i <= 1;
        bus_s.data_rvalid_i <= 1;

        if (bus_s.data_we_o) begin
          mem[bus_s.data_addr_o[ADDR_W-1:RegBits]] <= bus_s.data_wdata_o;
          bus_s.data_rdata_i <= 'x;
        end else bus_s.data_rdata_i <= mem[bus_s.data_addr_o[ADDR_W-1:RegBits]];
      end else begin
        bus_s.data_gnt_i <= 0;
        bus_s.data_rvalid_i <= 0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  //                                   CPU Model
  // ---------------------------------------------------------------------------

  // Write one MMR register
  task automatic mmr_write(input logic [ADDR_W-1:0] addr_off, input logic [BusWidth-1:0] data_i);
    @(posedge clk);
    bus_m.data_req_o <= 1;
    bus_m.data_addr_o <= addr_off;
    bus_m.data_we_o <= 1;
    bus_m.data_be_o <= '1;
    bus_m.data_wdata_o <= data_i;
    bus_m.data_is_cap_o <= 'x;
  endtask

  // Read one MMR register
  task automatic mmr_read(input logic [ADDR_W-1:0] addr_off, output logic [BusWidth-1:0] data_o);
    @(posedge clk);
    bus_m.data_req_o <= 1;
    bus_m.data_addr_o <= addr_off;
    bus_m.data_we_o <= 0;
    bus_m.data_be_o <= '1;
    bus_m.data_wdata_o <= 'x;
    bus_m.data_is_cap_o <= 'x;

    @(posedge clk);
    #1step;
    data_o = bus_m.data_rdata_i;
  endtask

  // Wait for irq with timeout guard. Sets timed_out=1 on failure.
  logic cl_irq;
  generate
    if (CHERI_EN) assign cl_irq = mCD_tb.dut.gen_CHERI.u_mmr.cl_irq;
    else assign cl_irq = mCD_tb.dut.gen_noCHERI.u_mmr.cl_irq;
  endgenerate
  task automatic wait_for_irq(output logic timed_out);
    int cnt;
    timed_out = 0;
    cnt       = 0;

    while (((irq !== 1'b1) || (cl_irq == 1'b1)) && (cnt < TIMEOUT_CY)) begin
      @(posedge clk);
      cnt++;
    end
    if (!irq) begin
      $error("\t[TIMEOUT] irq not received within %0d cycles", TIMEOUT_CY);
      timed_out = 1;
    end
  endtask

  localparam int unsigned TransSizeW = 16;
  localparam int unsigned TransSizeB = $clog2(TransSizeW);
  task automatic program_transf(logic [ADDR_W-1:0] addr_src, logic [TransSizeB-1:0] len_wrds,
                                logic [TransSizeW-1:0] caps, logic tag_val = 1'b0,
                                logic full = 1'b1);
    int i;

    logic [DATA_W-1:0] magic_vals[TransSizeW];
    logic [CapWidth-1:0] src_cap, dst_cap;
    logic timed_out;
    magic_vals = {
      32'hCAFEBABE,
      32'hDEADBEEF,
      32'hC0DEDEAD,
      32'h8BADF00D,
      32'hFEEDFACE,
      32'hFEEEFEEE,
      32'hFACEB00C,
      32'h00C0FFE0,
      32'h0000C0DE,
      32'h0000BEEF,
      32'h0000DEAD,
      32'h0000FEED,
      32'h0000FACE,
      32'h0000F00D,
      32'h0000B00C,
      32'hAAAAAAAA
    };

    for (i = 0; i < len_wrds; i++) begin
      if (CHERI_EN) mem[addr_src[ADDR_W-1:RegBits]+i] = {caps[i], magic_vals[i]};
      else mem[addr_src[ADDR_W-1:RegBits]+i] = magic_vals[i];
    end
    #1step;

    if (CHERI_EN) begin
      src_cap = encode_cap(tag_src, cperms_src, rotype_src, top_src, base_src, addr_src);
      dst_cap = encode_cap(tag_dst, cperms_dst, rotype_dst, top_dst, base_dst, addr_dst);
      start_transf(src_cap, dst_cap, len_bytes);
    end else start_transf(addr_src, addr_dst, len_bytes);

    #1;
    wait_for_irq(timed_out);
    if (timed_out) return;

    if (full) begin
      // Check error status
      if (CHERI_EN) mmr_read(CHERI_STATUS, status);
      else mmr_read(STATUS, status);
      check_bit("ErrStatus", status[ErrBits], 1'b0);
      // for (i = 0; i < 80; i = i + 1) begin
      //   $display("mem[%03d] = %09X", i, mem[i]);
      // end

      // Check data correctness
      for (i = 0; i < len_wrds; i++)
        if (CHERI_EN)
          check_word($sformatf("dst word %0d", i + 1),
                     mem[addr_dst[ADDR_W-1:RegBits]+i][BusWidth-2:0], magic_vals[i]);
        else
          check_word($sformatf("dst word %0d", i + 1),
                     mem[addr_dst[ADDR_W-1:RegBits]+i][BusWidth-1:0], magic_vals[i]);

      if (CHERI_EN)
        // Check tag clearing
        for (i = 0; i < len_wrds; i++) begin
          check_bit($sformatf("tag[%0d]", i + 1), mem[addr_dst[ADDR_W-1:RegBits]+i][BusWidth-1],
                    tag_val);
        end

      for (i = 0; i < MEM_WORDS; i++) begin
        mem[i] = '0;
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  //                            Capability Encoder
  //
  // It encodes a CHERIoT capability in format:
  //   cap[65:32] = {tag[65], rsvd[64], cperms[63:58], rotype[57:55],
  //                 cexp[54:51], top_mant[50:42], base_mant[41:33]}
  //   cap[32:0]  = {tag[32], addr[31:0]}
  // ---------------------------------------------------------------------------
  function automatic logic [CapWidth-1:0] encode_cap(
      input logic tag, input logic [5:0] cperms, input logic [2:0] rotype,
      input logic [ADDR_W:0] top, input logic [ADDR_W-1:0] base, input logic [ADDR_W-1:0] addr);
    logic rsvd;
    logic [ADDR_W:0] len;
    logic [4:0] exp;
    logic [3:0] cexp;
    logic [8:0] top_mant, base_mant;
    logic [CapWidth-1:0] cap;

    rsvd = 'x;

    len  = top - (ADDR_W + 1)'(base);

    priority casez (len[22:9])
      14'b1?????????????: cexp = 4'd14;
      14'b01????????????: cexp = 4'd13;
      14'b001???????????: cexp = 4'd12;
      14'b0001??????????: cexp = 4'd11;
      14'b00001?????????: cexp = 4'd10;
      14'b000001????????: cexp = 4'd09;
      14'b0000001???????: cexp = 4'd08;
      14'b00000001??????: cexp = 4'd07;
      14'b000000001?????: cexp = 4'd06;
      14'b0000000001????: cexp = 4'd05;
      14'b00000000001???: cexp = 4'd04;
      14'b000000000001??: cexp = 4'd03;
      14'b0000000000001?: cexp = 4'd02;
      14'b00000000000001: cexp = 4'd01;
      14'b00000000000000: cexp = 4'd00;

      default: ;
    endcase

    if (|len[ADDR_W:23]) begin
      cexp = EXPRESET;
      exp = EXPFULL;
      base_mant = {1'b0, base[ADDR_W-1-:8]};
    end else begin
      exp = (5)'(cexp);
      base_mant = base[exp+:9];
    end
    top_mant = top[exp+:9];

    cap = {tag, rsvd, cperms, rotype, cexp, top_mant, base_mant, tag, addr};

    return cap;
  endfunction

  // ---------------------------------------------------------------------------
  //                          Descriptor Programmer
  // ---------------------------------------------------------------------------
  task automatic start_transf(input logic [CapWidth-1:0] src_cap,
                              input logic [CapWidth-1:0] dst_cap,
                              input logic [DATA_W-2:0] len_bytes);
    logic start, cl_irq;
    {start, cl_irq} = '1;

    if (CHERI_EN) begin
      mmr_write(SRC_CAP_LO, src_cap[CapWidth/2-1:0]);
      mmr_write(SRC_CAP_HI, src_cap[CapWidth-1:CapWidth/2]);
      mmr_write(DST_CAP_LO, dst_cap[CapWidth/2-1:0]);
      mmr_write(DST_CAP_HI, dst_cap[CapWidth-1:CapWidth/2]);
      mmr_write(CHERI_CTRL, {len_bytes, start, cl_irq});
    end else begin
      mmr_write(SRC_CAP, src_cap[CapWidth/2-1:0]);
      mmr_write(DST_CAP, dst_cap[CapWidth/2-1:0]);
      mmr_write(CTRL, {len_bytes, start, cl_irq});
    end

    @(posedge clk) bus_m.data_req_o <= 0;
  endtask

  // ---------------------------------------------------------------------------
  //                               Error Counter
  // ---------------------------------------------------------------------------
  int unsigned err_count = 0;

  task automatic check_word(string label, input logic [DATA_W-1:0] got,
                            input logic [DATA_W-1:0] expec);
    if (got !== expec) begin
      $error("\t[FAIL] %s: expected 0x%08X, got 0x%08X", label, expec, got);
      err_count++;
    end else $display("\t[SUCCESS] %s: expected 0x%08X, got 0x%08X", label, expec, got);
  endtask

  task automatic check_bit(string label, input logic got, input logic expec);
    if (got !== expec) begin
      $error("\t[FAIL] %s: expected %0b, got %0b", label, expec, got);
      err_count++;
    end else $display("\t[SUCCESS] %s: expected %0b, got %0b", label, expec, got);
  endtask

  // ---------------------------------------------------------------------------
  //                                  Testing
  // ---------------------------------------------------------------------------
  logic [DATA_W-1:0] magic_vals[TransSizeW];
  logic [CapWidth-1:0] src_cap, dst_cap;
  logic timed_out;
  logic [BusWidth-1:0] status;
  logic [DATA_W-1:0] fault_addr;

  logic tag_src;
  logic [5:0] cperms_src;
  logic [2:0] rotype_src;
  logic [ADDR_W:0] top_src;
  logic [ADDR_W-1:0] base_src;
  logic [ADDR_W-1:0] addr_src;
  logic tag_dst;
  logic [5:0] cperms_dst;
  logic [2:0] rotype_dst;
  logic [ADDR_W:0] top_dst;
  logic [ADDR_W-1:0] base_dst;
  logic [ADDR_W-1:0] addr_dst;

  logic [DATA_W-2:0] len_bytes;
  int i;

  logic [DATA_W-1:0] old_value;


  // ---------------------------------------------------------------------------
  // TEST 1 – Basic data copy (no tag preservation)
  //
  // src cap:  base=0x000, top=0x100, addr=0x000, CPERMS.DATA
  // dst cap:  base=0x100, top=0x200, addr=0x100, CPERMS.DATA
  // len:      8 bytes (2 words)
  //
  // Expected: words 0xDEADBEEF and 0xCAFEBABE copied to dst region.
  // ---------------------------------------------------------------------------
  task automatic t1_basic_copy;
    $display("\n=== T1: basic data copy (no tag preservation) ===");

    tag_src = 1;
    tag_dst = 1;
    {gl, ld, sd} = 3'b011;
    #1step;
    cperms_src = CPERMS.MEM_DATA;
    cperms_dst = CPERMS.MEM_DATA;
    rotype_src = '0;
    rotype_dst = '0;
    top_src = 'h100;
    top_dst = 'h200;
    base_src = '0;
    base_dst = 'h100;
    addr_src = '0;
    addr_dst = 'h100;
    len_bytes = 2 * 4;
    #1step;

    program_transf(addr_src, len_bytes / 4, '1);
    $display("\t[DONE]");
  endtask

  // ---------------------------------------------------------------------------
  // TEST 2 – Basic data copy with buffer alternation (no tag preservation)
  //
  // src cap:  base=0x000, top=0x100, addr=0x000, CPERMS.DATA
  // dst cap:  base=0x100, top=0x200, addr=0x100, CPERMS.DATA
  // len:      40 bytes (10 words)
  //
  // Expected: words 0xDEADBEEF and 0xCAFEBABE copied to dst region.
  // ---------------------------------------------------------------------------
  task automatic t2_basic_copy_long;
    $display("\n=== T2: basic data copy with buffer alternation (no tag preservation) ===");

    tag_src = 1;
    tag_dst = 1;
    {gl, ld, sd} = 3'b011;
    #1step;
    cperms_src = CPERMS.MEM_DATA;
    cperms_dst = CPERMS.MEM_DATA;
    rotype_src = '0;
    rotype_dst = '0;
    top_src = 'h100;
    top_dst = 'h200;
    base_src = '0;
    base_dst = 'h100;
    addr_src = '0;
    addr_dst = 'h100;
    len_bytes = 10 * 4;
    #1step;

    program_transf(addr_src, len_bytes / 4, '1);
    $display("\t[DONE]");
  endtask

  // ---------------------------------------------------------------------------
  // TEST 3 – Tag preserving capability transfer
  //
  // src cap:  base=0x000, top=0x100, addr=0x000, CPERMS.MEM_R
  // dst cap:  base=0x100, top=0x200, addr=0x100, CPERMS.MEM_W
  // len:      8 bytes (2 words)
  //
  // Expected: tags mirror source exactly.
  // ---------------------------------------------------------------------------
  task automatic t3_tag_preserve;
    $display("\n=== T3: Tag preserving capability transfer ===");

    tag_src = 1;
    tag_dst = 1;
    {gl, lm, lg} = '0;
    #1step;
    cperms_src = CPERMS.MEM_R;
    cperms_dst = CPERMS.MEM_W;
    rotype_src = '0;
    rotype_dst = '0;
    top_src = 'h100;
    top_dst = 'h200;
    base_src = '0;
    base_dst = 'h100;
    addr_src = '0;
    addr_dst = 'h100;
    len_bytes = 2 * 4;

    program_transf(addr_src, len_bytes / 4, '1, 1);
    $display("\t[DONE]");
  endtask

  // ---------------------------------------------------------------------------
  // TEST 4 – Out-of-bounds fault
  //
  // src cap:  base=0x010, top=0x018, addr=0x000, CPERMS.DATA
  // dst cap:  base=0x100, top=0x200, addr=0x100, CPERMS.DATA
  // len:      16 bytes (4 words)
  //
  // Expected: cap_check raises ERR_BOUNDS and destination memory must be
  //           unmodified (no spurious writes).
  // ---------------------------------------------------------------------------
  task automatic t4_bounds_fault;
    $display("\n=== T4: out-of-bounds fault ===");

    tag_src = 1;
    tag_dst = 1;
    {gl, ld, sd} = 3'b011;
    #1step;
    cperms_src = CPERMS.MEM_DATA;
    cperms_dst = CPERMS.MEM_DATA;
    rotype_src = '0;
    rotype_dst = '0;
    top_src = 'h018;
    top_dst = 'h200;
    base_src = 'h010;
    base_dst = 'h100;
    addr_src = 'h014;
    addr_dst = 'h100;
    len_bytes = 4 * 4;

    old_value = 'hAAAA_AAAA;
    mem[64][BusWidth-2:0] = old_value;

    program_transf(addr_src, len_bytes / 4, '1, 0, !CHERI_EN);

    if (CHERI_EN) begin
      // Check error status
      mmr_read(CHERI_STATUS, status);
      mmr_read(CHERI_FAULT_ADDR, fault_addr);
      check_bit("Error status", status[ErrBits], 1'b1);
      check_word("Error code", status[ErrBits-1:0], ERR_BOUNDS);
      check_word("Error address", fault_addr, addr_src);

      // Check data correctness
      check_word("dst unmodified", mem[64][BusWidth-2:0], old_value);
    end

    $display("\t[DONE]");
  endtask

  // ---------------------------------------------------------------------------
  // TEST 5 – Permission violation (missing PERMIT_LOAD on source)
  //
  // Expected: STATUS[error] = 1, STATUS[code] = ERR_PERM
  //           No bus transactions issued.
  // src cap:  base=0x000, top=0x018, addr=0x010, CPERMS.DATA (LD=0)
  // dst cap:  base=0x100, top=0x200, addr=0x100, CPERMS.DATA
  // len:      8 bytes (2 words)
  //
  // Expected: cap_check raises ERR_PERMLD and destination memory must be
  //           unmodified (no spurious writes).
  // ---------------------------------------------------------------------------
  task automatic t5_perm_fault;
    $display("\n=== T5: permission fault (src missing PERMIT_LOAD) ===");

    tag_src = 1;
    tag_dst = 1;
    {gl, ld, sd} = 3'b001;
    #1step;
    cperms_src = CPERMS.MEM_DATA;
    cperms_dst = CPERMS.MEM_DATA;
    rotype_src = '0;
    rotype_dst = '0;
    top_src = 'h018;
    top_dst = 'h200;
    base_src = '0;
    base_dst = 'h100;
    addr_src = 'h010;
    addr_dst = 'h100;
    len_bytes = 15 * 4;

    old_value = 'hFFFF_FFFF;
    mem[64][BusWidth-2:0] = old_value;

    program_transf(addr_src, len_bytes / 4, '1, 0, !CHERI_EN);

    if (CHERI_EN) begin
      // Check error status
      mmr_read(CHERI_STATUS, status);
      mmr_read(CHERI_FAULT_ADDR, fault_addr);
      check_bit("Error status", status[ErrBits], 1'b1);
      check_word("Error code", status[ErrBits-1:0], ERR_PERMLD);
      check_word("Error address", fault_addr, addr_src);

      // Check data correctness
      check_word("dst unmodified", mem[64][BusWidth-2:0], old_value);
    end

    $display("\t[DONE]");
  endtask

  // ---------------------------------------------------------------------------
  //                                Simulation Top
  // ---------------------------------------------------------------------------
  initial begin
    string vcd_file;
    if (!$value$plusargs("vcdfile=%s", vcd_file)) vcd_file = "CHERI__mCD_tb.vcd";
    $dumpfile(vcd_file);
    $dumpvars(0, mCD_tb);
    $dumpvars(0, mCD_tb.bus_m);
    $dumpvars(0, mCD_tb.bus_s);

    rst_n = 0;
    // Hold reset for 5 cycles
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (3) @(posedge clk);

    $display("=====================================================");
    $display("               mon-CHERI-DMA testbench               ");
    $display("=====================================================");

    t1_basic_copy();
    t2_basic_copy_long();
    t3_tag_preserve();
    t4_bounds_fault();
    t5_perm_fault();


    $display("\n=====================================================");
    if (err_count == 0) $display("\tRESULT: ALL TESTS PASSED  (%0d errors)", err_count);
    else $display("\tRESULT: %0d ERROR(S) DETECTED", err_count);
    $display("=====================================================\n");

    $finish;
  end

  // Catch hung FSM
  initial begin
    #(CLK_PERIOD * 100_000);
    $error("Simulation exceeded 100,000 cycles!");
    $finish;
  end

endmodule
