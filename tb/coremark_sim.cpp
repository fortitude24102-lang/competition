#include <cstdint>
#include <iostream>
#include <string>

#include "VSoCTop.h"
#include "verilated.h"

namespace {
constexpr std::uint64_t kDefaultMaxCycles = 50000000;

void drive_idle_inputs(VSoCTop &top) {
  top.io_video_input_valid = 0;
  top.io_video_input_bits_data = 0;
  top.io_video_input_bits_startOfFrame = 0;
  top.io_video_input_bits_endOfLine = 0;
  top.io_video_input_bits_endOfFrame = 0;
  top.io_video_output_ready = 1;
  top.io_uartTx_ready = 1;
  top.io_uartRx_valid = 0;
  top.io_uartRx_bits = 0;
  top.io_gpioInput = 0;
  top.io_externalImem_req_ready = 1;
  top.io_externalImem_resp_valid = 0;
  top.io_externalImem_resp_bits_rdata = 0;
  top.io_externalImem_resp_bits_error = 0;
  top.io_externalDmem_req_ready = 1;
  top.io_externalDmem_resp_valid = 0;
  top.io_externalDmem_resp_bits_rdata = 0;
  top.io_externalDmem_resp_bits_error = 0;
}

void tick(VSoCTop &top) {
  top.clock = 0;
  top.eval();
  top.clock = 1;
  top.eval();
}
}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  VSoCTop top;
  std::string uart_output;

  drive_idle_inputs(top);
  top.reset = 1;
  for (int cycle = 0; cycle < 5; ++cycle) {
    tick(top);
  }
  top.reset = 0;

  for (std::uint64_t cycle = 1; cycle <= kDefaultMaxCycles; ++cycle) {
    top.clock = 0;
    top.eval();
    if (top.io_uartTx_valid && top.io_uartTx_ready) {
      const char byte = static_cast<char>(top.io_uartTx_bits);
      uart_output.push_back(byte);
      std::cout << byte << std::flush;
    }
    top.clock = 1;
    top.eval();

    if (top.io_halted) {
      std::cout << "\nSIM_CYCLES=" << cycle << "\nSIM_HALTED=1\n";
      return uart_output.empty() ? 2 : 0;
    }
  }

  std::cerr << "\nSIM_TIMEOUT=" << kDefaultMaxCycles << "\n";
  return 1;
}
