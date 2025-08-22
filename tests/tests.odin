package tests

import main "../src"
import "core:testing"

state := main.State{}

@(test)
test_address_jump :: proc(t: ^testing.T) {
  addr: u16 = 0x0200
  opcode: u16 = 0x1000 | addr
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == addr, "Did not jump to address")
}

@(test)
test_instructions_loading :: proc(t: ^testing.T) {
  binary := []u8{1, 2}

  main.load_instructions(binary, &state)

  testing.expect(
    t,
    state.ram[0x200] == 1,
    "Did not load first byte at start address",
  )

  testing.expect(
    t,
    state.ram[0x201] == 2,
    "Did not load second byte at address 0x201",
  )
}
