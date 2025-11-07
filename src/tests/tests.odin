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

@(test)
test_instructions_loading :: proc(t: ^testing.T) {
  state := main.State{}
  // binaryはリトルエンディアンになっている
  binary := []u16{0x0102}
  start: u16 = 0x200

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
    state.stack[state.sp] == pc + 2, // Call直後の命令のアドレス
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
    state.I != data,
    "I register should have a different value than the test data",
  )
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.I == data, "I register should contain the test data")
}

/* Dxyn - DRW Vx, Vy, nibble

アドレスIのnバイトのスプライトを(Vx, Vy)に描画する。Vfにはcollision(後述)をセットする。

アドレスIのnバイトのスプライトを読み出し、スプライトとして(Vx, Vy)に描画する。スプライトは画面にXORする。このとき、消されたピクセルが一つでもある場合はVfに1、それ以外の場合は0をセットする。スプライトの一部が画面からはみ出る場合は、逆方向に折り返す。
*/
@(test)
test_draw_nbytes_at_xy :: proc(t: ^testing.T) {
  state := main.State {
    dsp_w = 64,
    dsp_h = 32,
  }

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

  state.I = 0
  main.execute_opcode(opcode, &state)

  x_from_left := u8(state.dsp_w) - start_x - 8

  for i in 0 ..< n {
    testing.expect(
      t,
      u8(
        (state.dsp[start_y + u8(i)] & (0xff << x_from_left)) >> x_from_left,
      ) ==
      sprite_one[i],
      "Display should contain sprite at X and Y",
    )
  }
  testing.expect(t, state.regs[0xf] == 0, "Collision should NOT be set in Vf")
}

@(test)
test_draw_nbytes_at_xy_with_collision :: proc(t: ^testing.T) {
  state := main.State {
    dsp_w = 64,
    dsp_h = 32,
  }

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

  x_from_left := u8(state.dsp_w) - start_x - 8

  // ディスプレイに予め衝突するデータを用意
  state.dsp[start_y] = 0x20 << x_from_left

  state.I = 0
  state.regs[0xf] = 0
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[0xf] == 1, "Collision should be set in Vf")
}

@(test)
test_draw_nbytes_at_xy_with_wrapping :: proc(t: ^testing.T) {
  // TODO: wrappingの意味と結果を確認
}

@(test)
test_load_vx_vy :: proc(t: ^testing.T) {
  state := main.State{}
  state.regs[4] = 7
  state.regs[6] = 9

  vx: u16 = 4
  vy: u16 = 6
  opcode := 0x8000 | vx << 8 | vy << 4

  main.execute_opcode(opcode, &state)

  testing.expect(
    t,
    state.regs[4] == state.regs[6] && state.regs[4] == 9,
    "Vx should equal Vy",
  )
}

@(test)
test_or_vx_vy :: proc(t: ^testing.T) {
  state := main.State{}
  state.regs[4] = 7
  state.regs[6] = 9

  vx: u16 = 4
  vy: u16 = 6
  opcode := 0x8001 | vx << 8 | vy << 4

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[4] == 15, "Vx should equal Vx | Vy")
}

@(test)
test_and_vx_vy :: proc(t: ^testing.T) {
  state := main.State{}
  state.regs[4] = 7
  state.regs[6] = 9

  vx: u16 = 4
  vy: u16 = 6
  opcode := 0x8002 | vx << 8 | vy << 4

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[4] == 1, "Vx should equal Vx & Vy")
}

@(test)
test_xor_vx_vy :: proc(t: ^testing.T) {
  state := main.State{}
  state.regs[4] = 7
  state.regs[6] = 9

  vx: u16 = 4
  vy: u16 = 6
  opcode := 0x8003 | vx << 8 | vy << 4

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[4] == 14, "Vx should equal Vx ^ Vy")
}

@(test)
test_add_vx_vy :: proc(t: ^testing.T) {
  state := main.State{}

  vx: u16 = 4
  vy: u16 = 6
  opcode := 0x8004 | vx << 8 | vy << 4

  state.regs[4] = 128
  state.regs[6] = 255

  assert(state.regs[0xf] == 0)
  main.execute_opcode(opcode, &state)

  testing.expect(
    t,
    state.regs[4] == 127,
    "Vx should equal Vx + Vy with byte overflow",
  )
  testing.expect(t, state.regs[0xf] == 1)

  state.regs[4] = 7
  state.regs[6] = 9

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[4] == 16)
  testing.expect(t, state.regs[0xf] == 0)
}

@(test)
test_sub_vx_vy :: proc(t: ^testing.T) {
  state := main.State{}
  vx: u16 = 4
  vy: u16 = 6
  opcode := 0x8005 | vx << 8 | vy << 4

  state.regs[4] = 9
  state.regs[6] = 7

  assert(state.regs[0xf] == 0)
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[4] == 2, "Vx should equal Vx - Vy")
  testing.expect(t, state.regs[0xf] == 1, "Flag should be set when Vx > Vy")

  state.regs[4] = 7
  state.regs[6] = 9

  main.execute_opcode(opcode, &state)

  testing.expect(
    t,
    state.regs[4] == 254,
    "Vx should equal Vx - Vy with byte overflow",
  )
  testing.expect(
    t,
    state.regs[0xf] == 0,
    "Flag should NOT be set when Vy >= Vx",
  )
}

@(test)
test_shr_vx :: proc(t: ^testing.T) {
  state := main.State{}

  vx: u16 = 4
  vy: u16 = 4
  opcode := 0x8006 | vx << 8 | vy << 4

  state.regs[4] = 5

  assert(state.regs[0xf] == 0)
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[vx] == 2)
  testing.expect(t, state.regs[0xf] == 1)

  state.regs[4] = 4

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[vx] == 2)
  testing.expect(t, state.regs[0xf] == 0)
}

@(test)
test_subn_vx_vy :: proc(t: ^testing.T) {
  state := main.State{}

  vx: u16 = 4
  vy: u16 = 6
  opcode := 0x8007 | vx << 8 | vy << 4

  state.regs[4] = 7
  state.regs[6] = 9

  assert(state.regs[0xf] == 0)
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[4] == 2, "Vx should equal Vy - Vx")
  testing.expect(t, state.regs[0xf] == 1, "Flag should be set when Vy > Vx")

  state.regs[4] = 9
  state.regs[6] = 7

  main.execute_opcode(opcode, &state)

  testing.expect(
    t,
    state.regs[4] == 254,
    "Vx should equal Vy - Vx with byte overflow",
  )
  testing.expect(
    t,
    state.regs[0xf] == 0,
    "Flag should NOT be set when Vx >= Vy",
  )
}

@(test)
test_shl_vx :: proc(t: ^testing.T) {
  state := main.State{}

  vx: u16 = 4
  vy: u16 = 4
  opcode := 0x800e | vx << 8 | vy << 4

  state.regs[4] = 0x81

  assert(state.regs[0xf] == 0)
  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[vx] == 2)
  testing.expect(t, state.regs[0xf] == 1)

  state.regs[4] = 4

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[vx] == 8)
  testing.expect(t, state.regs[0xf] == 0)
}

@(test)
test_return :: proc(t: ^testing.T) {
  state := main.State{}

  opcode: u16 = 0x00ee

  state.sp = 10
  state.stack[state.sp] = 20

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.sp == 9)
  testing.expect(t, state.pc == 20)
}

// Fx55
@(test)
test_ld_I_vx :: proc(t: ^testing.T) {
  state := main.State{}
  for i in 0 ..= 15 {
    assert(state.ram[state.I + u16(i)] == 0)
  }

  opcode: u16 = 0xF355
  state.regs[0] = 0
  state.regs[1] = 1
  state.regs[2] = 2
  state.regs[3] = 3

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.ram[state.I] == 0)
  testing.expect(t, state.ram[state.I + 1] == 1)
  testing.expect(t, state.ram[state.I + 2] == 2)
  testing.expect(t, state.ram[state.I + 3] == 3)
}

//Fx1E
@(test)
test_set_I_to_I_plus_vx :: proc(t: ^testing.T) {
  state := main.State{}

  opcode: u16 = 0xF01e
  state.regs[0] = 8

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.I == 8)
}

// Fx33
@(test)
test_ld_bcd_from_vx :: proc(t: ^testing.T) {
  state := main.State{}
  for i in 0 ..= 2 {
    assert(state.ram[state.I + u16(i)] == 0)
  }

  opcode: u16 = 0xF033
  state.regs[0] = 123

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.ram[state.I] == 1)
  testing.expect(t, state.ram[state.I + 1] == 2)
  testing.expect(t, state.ram[state.I + 2] == 3)

  state.regs[0] = 0

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.ram[state.I] == 0)
  testing.expect(t, state.ram[state.I + 1] == 0)
  testing.expect(t, state.ram[state.I + 2] == 0)
}

// Fx65
@(test)
test_ld_vx_I :: proc(t: ^testing.T) {
  state := main.State{}
  for i in 0 ..= 15 {
    assert(state.regs[i] == 0)
  }

  opcode: u16 = 0xF365
  state.ram[state.I] = 0
  state.ram[state.I + 1] = 1
  state.ram[state.I + 2] = 2
  state.ram[state.I + 3] = 3

  main.execute_opcode(opcode, &state)

  testing.expect(t, state.regs[0] == 0)
  testing.expect(t, state.regs[1] == 1)
  testing.expect(t, state.regs[2] == 2)
  testing.expect(t, state.regs[3] == 3)
}
