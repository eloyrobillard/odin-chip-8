package main

import "core:fmt"
import rl "vendor:raylib"

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
  state := State{}

  // プログラムを取得
  binary := #load("../assets/1-chip8-logo.ch8", []u16)

  // オペコードを解読し、実行する
  start := 0x200
  num_instr := load_instructions_in_ram(&binary, &state, start)

  // ディスプレイを起動
  WIDTH: i32 = 64
  HEIGHT: i32 = 32
  rl.InitWindow(WIDTH, HEIGHT, "Chip 8 Logo Test")
  rl.SetTargetFPS(60)

  i := 0
  for !rl.WindowShouldClose() && i < num_instr {
    rl.BeginDrawing()

    fst_byte := u16(state.ram[start + i])
    snd_byte := u16(state.ram[start + i + 1])
    opcode: u16 = fst_byte << 8 + snd_byte

    execute_opcode(opcode, &state)

    draw_display(&state.dsp, WIDTH, HEIGHT)

    rl.EndDrawing()

    i += 2
  }

  rl.CloseWindow()
}

draw_display :: proc(display: ^[32]u64, WIDTH: i32, HEIGHT: i32) {
  for y in 0 ..< HEIGHT {
    for x in 0 ..< WIDTH {
      row := display[y]
      set := (row & (1 << u32(x))) > 0

      if set do rl.DrawPixel(x, y, rl.WHITE)
      else do rl.DrawPixel(x, y, rl.BLACK)
    }
  }
}

load_instructions_in_ram :: proc(
  binary: ^[]u16,
  state: ^State,
  start: int,
) -> int {
  // load in Big Endian mode starting at address 0x200
  offset := 0
  for word in binary {
    fst_byte := u8(word & 0xff)
    snd_byte := u8((word & 0xff00) >> 8)
    state.ram[start + offset] = fst_byte
    state.ram[start + offset + 1] = snd_byte
    offset += 2
  }

  return offset
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
