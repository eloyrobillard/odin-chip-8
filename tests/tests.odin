package tests

import main "../src"
import "core:testing"

state := main.State{}

/* 1NNN - JUMP addr
  アドレスNNNにジャンプする。
  インタプリタはプログラムカウンタをNNNにする。
  */
@(test)
test_address_jump :: proc(t: ^testing.T) {
  addr: u16 = 0x0200
  opcode: u16 = 0x1000 | addr
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == addr, "Did not jump to address")
}

/* 2NNN - CALL addr
  アドレスNNNのサブルーチンをCallする。インタプリタはスタックポインタをインクリメントし、それから現在のプログラムカウンタをスタックの一番上に置く。さらにプログラムカウンタにNNNをセットする。
  */
@(test)
test_call_addr :: proc(t: ^testing.T) {
  addr: u16 = 0x0200
  opcode: u16 = 0x2000 | addr
  pc := state.pc
  sp := state.sp
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == addr, "Did not jump to address")
  testing.expect(t, state.sp == sp + 1, "Did not increment stack pointer")
  testing.expect(
    t,
    state.stack[state.sp] == pc,
    "Old program counter not at top of stack",
  )
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
