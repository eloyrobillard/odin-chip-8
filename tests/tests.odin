package tests

import main "../src"
import "core:testing"


/* 1NNN - JUMP addr
  アドレスNNNにジャンプする。
  インタプリタはプログラムカウンタをNNNにする。
  */
@(test)
test_address_jump :: proc(t: ^testing.T) {
  state := main.State{}
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
  state := main.State{}
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

/* 3xkk - SE Vx, byte
  Vx = kkの場合、次の命令をスキップする。インタプリタはレジスタVxとkkを比較し、二つが等しいならプログラムカウンタを2進める。
  */
@(test)
test_cond_reg_byte :: proc(t: ^testing.T) {
  state := main.State{}
  pc := state.pc
  reg: u16 = 0
  same_as_reg: u16 = 0
  opcode: u16 = 0x3000 | (reg << 8) | same_as_reg

  assert(state.regs[reg] == 0, "V0 should contain 0")
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == pc + 2, "Did not add 2 to program counter")

  diff_from_reg: u16 = 1
  pc = state.pc
  opcode = 0x3000 | (reg << 8) | diff_from_reg

  assert(state.regs[reg] == 0, "V0 should contain 0")
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == pc, "Program counter should be unchanged")
  assert(state.regs[reg] == 0, "V0 should contain 0")
}

/*4xkk - SNE Vx, byte

Vx != kkの場合、次の命令をスキップする。インタプリタはレジスタVxとkkを比較し、二つが異なるならプログラムカウンタを2進める。
*/
@(test)
test_ncond_reg_byte :: proc(t: ^testing.T) {
  state := main.State{}
  pc := state.pc
  reg: u16 = 0
  same_as_reg: u16 = 0
  opcode: u16 = 0x4000 | (reg << 8) | same_as_reg

  assert(state.regs[reg] == 0, "V0 should contain 0")
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == pc, "Program counter should be unchanged")

  diff_from_reg: u16 = 1
  pc = state.pc
  opcode = 0x4000 | (reg << 8) | diff_from_reg

  assert(state.regs[reg] == 0, "V0 should contain 0")
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == pc + 2, "Did not add 2 to program counter")
  assert(state.regs[reg] == 0, "V0 should contain 0")
}

/* 5xy0 - SE Vx, Vy

Vx = Vyの場合、次の命令をスキップする。インタプリタはレジスタVxとVyを比較し、二つが等しいならプログラムカウンタを2進める。
*/
@(test)
test_cond_reg_reg :: proc(t: ^testing.T) {
  state := main.State{}
  pc := state.pc
  r1: u16 = 1
  r2: u16 = 2
  opcode := 0x5000 | (r1 << 8) | (r2 << 4)

  assert(state.regs[r1] == 0, "V1 should contain 0")
  assert(state.regs[r2] == 0, "V2 should contain 0")
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == pc + 2, "Did not add 2 to program counter")

  pc = state.pc
  state.regs[r1] = 1
  opcode = 0x5000 | r1 | r2

  assert(state.regs[r1] == 1, "V1 should contain 1")
  assert(state.regs[r2] == 0, "V2 should contain 0")
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == pc, "Should not update program counter")

  assert(state.regs[r1] == 1, "V1 should contain 1")
  assert(state.regs[r2] == 0, "V2 should contain 0")
}

@(test)
test_instructions_loading :: proc(t: ^testing.T) {
  state := main.State{}
  binary := []u8{1, 2}

  main.load_instructions(&binary, &state)

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
