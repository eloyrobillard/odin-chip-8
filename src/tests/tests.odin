package tests

import main ".."
import "core:testing"

is_display_clear :: proc(dsp: ^[32]u64) -> bool {
  for row in dsp {
    if row > 0 {
      return false
    }
  }

  return true
}

/* 00E0 - CLS

ディプレイをクリアする。
*/
@(test)
test_clear_screen :: proc(t: ^testing.T) {
  state := main.State{}
  assert(is_display_clear(&state.dsp) == true, "Display should be clear")

  state.dsp[0] = 1
  assert(is_display_clear(&state.dsp) == false, "Display should be set")

  main.execute_opcode(0x00e0, &state)

  testing.expect(
    t,
    is_display_clear(&state.dsp) == true,
    "Display should be clear",
  )
}

/* 1NNN - JUMP addr
  アドレスNNNにジャンプする。
  インタプリタはプログラムカウンタをNNNにする。
  */
@(test)
test_address_jump :: proc(t: ^testing.T) {
  state := main.State{}
  addr: u16 = 0x0200
  opcode: u16 = 0x1000 | addr

  assert(
    state.pc != addr,
    "Program counter should not be equal to jump address at this point",
  )
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
  opcode = 0x5000 | (r1 << 8) | (r2 << 4)

  assert(state.regs[r1] == 1, "V1 should contain 1")
  assert(state.regs[r2] == 0, "V2 should contain 0")
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.pc == pc, "Should not update program counter")

  assert(state.regs[r1] == 1, "V1 should contain 1")
  assert(state.regs[r2] == 0, "V2 should contain 0")
}

/*6xkk - LD Vx, byte

Vxにkkをセットする。インタプリタはレジスタVxにkkの値をセットする。
*/
@(test)
test_load_reg_byte :: proc(t: ^testing.T) {
  state := main.State{}
  reg: u16 = 0
  data: u16 = 0x8f
  opcode: u16 = 0x6000 | (reg << 8) | data

  assert(state.regs[reg] == 0, "V0 should contain 0")
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[reg] == 0x8f, "V0 should contain 0x8f")
}

/*7xkk - ADD Vx, byte

VxにVx + kkをセットする。インタプリタはレジスタVxにkkの値を加算する。
*/
@(test)
test_add_reg_byte :: proc(t: ^testing.T) {
  state := main.State{}
  reg: u16 = 0
  data: u16 = 1
  opcode: u16 = 0x7000 | (reg << 8) | data

  state.regs[reg] = 1
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[reg] == 2, "Register should contain 2")
}

/* Annn - LD I, addr

Iにnnnをセットする。
*/
@(test)
test_load_i_addr :: proc(t: ^testing.T) {
  state := main.State{}
  data: u16 = 0x0333
  opcode := 0xa000 | data

  assert(
    state.i != data,
    "I register should have a different value than the test data",
  )
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.i == data, "I register should contain the test data")
}

/* Dxyn - DRW Vx, Vy, nibble

アドレスIのnバイトのスプライトを(Vx, Vy)に描画する。Vfにはcollision(後述)をセットする。

アドレスIのnバイトのスプライトを読み出し、スプライトとして(Vx, Vy)に描画する。スプライトは画面にXORする。このとき、消されたピクセルが一つでもある場合はVfに1、それ以外の場合は0をセットする。スプライトの一部が画面からはみ出る場合は、逆方向に折り返す。
*/
@(test)
test_draw_nbytes_at_xy :: proc(t: ^testing.T) {
  state := main.State{}

  // まずはスプライトを準備する
  sprite_one := [5]u8{0x20, 0x60, 0x20, 0x20, 0x70}
  state.ram[0] = sprite_one[0]
  state.ram[1] = sprite_one[1]
  state.ram[2] = sprite_one[2]
  state.ram[3] = sprite_one[3]
  state.ram[4] = sprite_one[4]

  start_x: u8 = 24
  start_y: u8 = 13
  vx: u16 = 1
  vy: u16 = 2
  state.regs[vx] = start_x
  state.regs[vy] = start_y
  n: u16 = 5
  opcode: u16 = 0xd000 | (vx << 8) | (vy << 4) | n

  state.i = 0
  main.execute_opcode(opcode, &state)

  for i in 0 ..< n {
    testing.expect(
      t,
      u8((state.dsp[start_y + u8(i)] & (0xff << start_x)) >> start_x) ==
      sprite_one[i],
      "Display should contain sprite at X and Y",
    )
  }
  testing.expect(t, state.regs[0xf] == 0, "Collision should NOT be set in Vf")
}

@(test)
test_draw_nbytes_at_xy_with_collision :: proc(t: ^testing.T) {
  state := main.State{}

  // まずはスプライトを準備する
  sprite_one := [5]u8{0x20, 0x60, 0x20, 0x20, 0x70}
  state.ram[0] = sprite_one[0]
  state.ram[1] = sprite_one[1]
  state.ram[2] = sprite_one[2]
  state.ram[3] = sprite_one[3]
  state.ram[4] = sprite_one[4]

  start_x: u8 = 24
  start_y: u8 = 13
  vx: u16 = 1
  vy: u16 = 2
  state.regs[vx] = start_x
  state.regs[vy] = start_y
  n: u16 = 5
  opcode: u16 = 0xd000 | (vx << 8) | (vy << 4) | n

  // ディスプレイに予め衝突するデータを用意
  state.dsp[start_y] = 0x20 << start_x

  state.i = 0
  state.regs[0xf] = 0
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[0xf] == 1, "Collision should be set in Vf")
}

@(test)
test_draw_nbytes_at_xy_with_wrapping :: proc(t: ^testing.T) {
  // TODO: wrappingの意味と結果を確認
}

@(test)
test_instructions_loading :: proc(t: ^testing.T) {
  state := main.State{}
  // binaryはリトルエンディアンになっている
  binary := []u16{0x0102}
  start := 0x200

  main.load_instructions_in_ram(&binary, &state, start)

  testing.expect(
    t,
    state.ram[0x200] == 2,
    "Did not load second byte at first address",
  )

  testing.expect(
    t,
    state.ram[0x201] == 1,
    "Did not load first byte at second address",
  )
}
