import mCD_pkg::*;
interface ibex_mem_if;
  // Request Phase
  logic data_req_o;  // master asserts to initiate
  logic [ADDR_W-1:0] data_addr_o;
  logic data_we_o;
  logic [RegStride-1:0] data_be_o;
  logic [BusWidth-1:0] data_wdata_o;
  logic data_is_cap_o;

  // Grant Phase
  logic data_gnt_i;  // slave acknowledges address/ctrl accepted

  // Response Phase
  logic data_rvalid_i;  // exactly 1 cycle, accompanies rlogic data/err
  logic [BusWidth-1:0] data_rdata_i;
  logic data_err_i;

  modport master(
      output data_req_o,
      output data_addr_o,
      output data_we_o,
      output data_be_o,
      output data_wdata_o,
      output data_is_cap_o,

      input data_gnt_i,
      input data_rvalid_i,
      input data_rdata_i,
      input data_err_i,

      import resetMaster_o
  );
  modport slave(
      input data_req_o,
      input data_addr_o,
      input data_we_o,
      input data_be_o,
      input data_wdata_o,
      input data_is_cap_o,

      output data_gnt_i,
      output data_rvalid_i,
      output data_rdata_i,
      output data_err_i,

      import resetSlave_o
  );

  task automatic resetMaster_o();
    {data_req_o, data_we_o, data_is_cap_o} <= '0;
    {data_addr_o, data_be_o, data_wdata_o} <= '0;
  endtask
  task automatic resetSlave_o();
    {data_gnt_i, data_rvalid_i, data_err_i} <= '0;
    data_rdata_i <= '0;
  endtask

endinterface
