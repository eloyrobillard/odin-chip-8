package main

import "core:fmt"

State :: struct {
  i:     u16,
  sp:    u8, // Stack Pointer, スタックの先頭のインデックスを表す
  pc:    u16, // 現在の実行アドレスを格納
  regs:  [16]u8,
  stack: [16]u16,
  ram:   [4096]u8,
  dsp:   [32]u64,
}

main :: proc() {
  // プログラムを取得
  // オペコードを解読し、実行する
  // binary := #load(path, []u8)
}

load_instructions :: proc(binary: ^[]u8, state: ^State) {
  // load in Big Endian order starting at address 0x200
  start := 0x200
  offset := 0
  for byte in binary {
    state.ram[start + offset] = byte
    offset += 1
  }
}

execute_opcode :: proc(opcode: u16, state: ^State) {
  fst_nib := opcode & 0xf000 >> 12

  switch fst_nib {
  /* 00E0 - CLS

  ディプレイをクリアする。
  */
  case 0:
    if opcode & 0x0f00 > 0 {} else if opcode & 0x000f > 0 {} else {
      state.dsp = [32]u64{}
    }

  /* 1NNN - JUMP addr
  アドレスNNNにジャンプする。
  インタプリタはプログラムカウンタをNNNにする。
  */
  case 1:
    addr := opcode & 0x0fff
    state.pc = addr

  /* 2NNN - CALL addr
  アドレスNNNのサブルーチンをCallする。インタプリタはスタックポインタをインクリメントし、それから現在のプログラムカウンタをスタックの一番上に置く。さらにプログラムカウンタにNNNをセットする。
  */
  case 2:
    state.sp += 1
    state.stack[state.sp] = state.pc

    addr := opcode & 0x0fff
    state.pc = addr

  /* 3xkk - SE Vx, byte
  Vx = kkの場合、次の命令をスキップする。インタプリタはレジスタVxとkkを比較し、二つが等しいならプログラムカウンタを2進める。
  */
  case 3:
    reg_n := opcode & 0x0f00 >> 8
    reg := state.regs[reg_n]
    cmp := u8(opcode & 0x00ff)

    if reg == cmp do state.pc += 2

  /* 4xkk - SNE Vx, byte

  Vx != kkの場合、次の命令をスキップする。インタプリタはレジスタVxとkkを比較し、二つが異なるならプログラムカウンタを2進める。
  */
  case 4:
    reg_n := opcode & 0x0f00 >> 8
    reg := state.regs[reg_n]
    cmp := u8(opcode & 0x00ff)

    if reg != cmp do state.pc += 2


  /* 5xy0 - SE Vx, Vy

  Vx = Vyの場合、次の命令をスキップする。インタプリタはレジスタVxとVyを比較し、二つが等しいならプログラムカウンタを2進める。
  */
  case 5:
    vx_n := opcode & 0x0f00 >> 8
    vy_n := opcode & 0x00f0 >> 4

    vx := state.regs[vx_n]
    vy := state.regs[vy_n]

    if vx == vy do state.pc += 2

  /* 6xkk - LD Vx, byte

  Vxにkkをセットする。インタプリタはレジスタVxにkkの値をセットする。
  */
  case 6:
    reg_n := opcode & 0x0f00 >> 8
    data := u8(opcode & 0x00ff)
    state.regs[reg_n] = data

  /* 7xkk - ADD Vx, byte

  VxにVx + kkをセットする。インタプリタはレジスタVxにkkの値を加算する。
  */
  case 7:
    reg_n := opcode & 0x0f00 >> 8
    data := u8(opcode & 0x00ff)
    state.regs[reg_n] += data

  /* Annn - LD I, addr

  Iにnnnをセットする。
  */
  case 0xA:
    data := opcode & 0x0fff
    state.i = data

  /* Dxyn - DRW Vx, Vy, nibble

  アドレスIのnバイトのスプライトを(Vx, Vy)に描画する。Vfにはcollision(後述)をセットする。

  アドレスIのnバイトのスプライトを読み出し、スプライトとして(Vx, Vy)に描画する。スプライトは画面にXORする。このとき、消されたピクセルが一つでもある場合はVfに1、それ以外の場合は0をセットする。スプライトの一部が画面からはみ出る場合は、逆方向に折り返す。
  */
  case 0xD:
    x := opcode & 0x0f00 >> 8
    y := opcode & 0x00f0 >> 4
    n := opcode & 0x000f

    vx := state.regs[x]
    vy := u16(state.regs[y])

    for i in 0 ..< n {
      byte := state.ram[state.i + i]
      byte_shifted := u64(byte) << vx

      // 衝突が起こったら、Vfに１をセット
      if state.dsp[vy + i] & byte_shifted > 0 do state.regs[0xf] = 1

      state.dsp[vy + i] = byte_shifted
    }
  }
}
