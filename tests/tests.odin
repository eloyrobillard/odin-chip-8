package tests

import main "../src"
import "core:testing"

state := main.State{}

@(test)
test_address_jump :: proc(t: ^testing.T) {
  main.execute_opcode(0x1123, &state)

  testing.expect(t, state.pc == 0x0123, "Did not jump to address 0x0123")
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
