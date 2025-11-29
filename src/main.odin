package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

State :: struct {
  I:     u16,
  sp:    u8, // Stack Pointer, スタックの先頭のインデックスを表す
  pc:    u16, // 現在の実行アドレスを格納
  regs:  [16]u8,
  stack: [16]u16,
  ram:   [4096]u8,
  dsp:   [32]u64,
  dsp_w: i32,
  dsp_h: i32,
  scale: i32,
}

main :: proc() {
  // プログラムを取得
  assert(len(os.args) > 1, "Please pass the name of the file to run")

  filename := os.args[1]

  data, ok := os.read_entire_file(filename)
  if !ok do fmt.println("Could not read file")
  defer delete(data)

  binary := transmute([]u16)(data)

  // オペコードを解読し、実行する
  instrs_start_addr: u16 = 0x200
  state := State {
    pc    = instrs_start_addr,
    dsp_w = 64,
    dsp_h = 32,
    scale = 30,
  }

  num_instr := load_instructions_in_ram(&binary, &state, instrs_start_addr)

  // ディスプレイを起動
  rl.InitWindow(
    state.dsp_w * state.scale,
    state.dsp_h * state.scale,
    "Chip 8 Test",
  )
  rl.SetTargetFPS(256)

  for !rl.WindowShouldClose() {
    rl.BeginDrawing()

    fst_byte := u16(state.ram[state.pc])
    snd_byte := u16(state.ram[state.pc + 1])
    opcode: u16 = fst_byte << 8 + snd_byte

    jumped := execute_opcode(opcode, &state)

    if !jumped do state.pc += 2

    rl.EndDrawing()
  }

  rl.CloseWindow()
}

draw_display_at :: proc(
  display: ^[32]u64,
  WIDTH: i32,
  HEIGHT: i32,
  scale: i32,
  start_y: i32,
  end_y: i32,
  start_x: i32,
  end_x: i32,
) {
  for y in start_y ..= (end_y % HEIGHT) {
    row := display[y]
    for x in start_x ..< (end_x % WIDTH) {
      x_from_left := WIDTH - x - 1
      set := (row & (1 << u32(x_from_left))) > 0

      if set do rl.DrawRectangle(x * scale, y * scale, scale, scale, rl.WHITE)
      else do rl.DrawRectangle(x * scale, y * scale, scale, scale, rl.BLACK)
    }
  }
}

draw_display :: proc(display: ^[32]u64, WIDTH: i32, HEIGHT: i32, scale: i32) {
  rl.ClearBackground(rl.BLACK)

  for y in 0 ..< HEIGHT {
    row := display[y]
    for x in 0 ..< WIDTH {
      x_from_left := WIDTH - x - 1
      set := (row & (1 << u32(x_from_left))) > 0

      if set do rl.DrawRectangle(x * scale, y * scale, scale, scale, rl.WHITE)
    }
  }
}

load_instructions_in_ram :: proc(
  binary: ^[]u16,
  state: ^State,
  start_addr: u16,
) -> u16 {
  // load in Big Endian mode starting at address 0x200
  offset: u16 = 0
  for word in binary {
    fst_byte := u8(word & 0xff)
    snd_byte := u8((word & 0xff00) >> 8)
    state.ram[start_addr + offset] = fst_byte
    state.ram[start_addr + offset + 1] = snd_byte
    offset += 2
  }

  return offset
}

execute_opcode :: proc(opcode: u16, state: ^State) -> bool {
  jumped := false
  fst_nib := opcode & 0xf000 >> 12

  switch fst_nib {
  case 0x0:
    low_byte := opcode & 0x00ff

    switch low_byte {
    /* 00E0 - CLS
    ディプレイをクリアする。
    */
    case 0xE0:
      state.dsp = [32]u64{}

    /* 00EE - RET
    サブルーチンから戻る。プログラムカウンタにスタックの一番上のアドレスをセットし、スタックポインタから1を引く。
    */
    case 0xEE:
      state.pc = state.stack[state.sp]
      state.sp -= 1

      jumped = true


    case:
      fmt.printfln("Opcode not implemented: %4x", opcode)

    }

  /* 1NNN - JUMP addr
  アドレスNNNにジャンプする。
  インタプリタはプログラムカウンタをNNNにする。
  */
  case 0x1:
    addr := opcode & 0x0fff
    state.pc = addr
    jumped = true

  /* 2NNN - CALL addr
  アドレスNNNのサブルーチンをCallする。インタプリタはスタックポインタをインクリメントし、それから現在のプログラムカウンタをスタックの一番上に置く。さらにプログラムカウンタにNNNをセットする。
  */
  case 0x2:
    state.sp += 1
    // 次の命令のアドレスをスタックにプッシュ
    state.stack[state.sp] = state.pc + 2

    addr := opcode & 0x0fff
    state.pc = addr

    jumped = true

  /* 3xkk - SE Vx, byte
  Vx = kkの場合、次の命令をスキップする。インタプリタはレジスタVxとkkを比較し、二つが等しいならプログラムカウンタを2進める。
  */
  case 0x3:
    reg_n := (opcode & 0x0f00) >> 8
    reg := state.regs[reg_n]
    cmp := u8(opcode & 0x00ff)

    if reg == cmp do state.pc += 2

  /* 4xkk - SNE Vx, byte
  Vx != kkの場合、次の命令をスキップする。インタプリタはレジスタVxとkkを比較し、二つが異なるならプログラムカウンタを2進める。
  */
  case 0x4:
    reg_n := (opcode & 0x0f00) >> 8
    reg := state.regs[reg_n]
    cmp := u8(opcode & 0x00ff)

    if reg != cmp do state.pc += 2


  /* 5xy0 - SE Vx, Vy
  Vx = Vyの場合、次の命令をスキップする。インタプリタはレジスタVxとVyを比較し、二つが等しいならプログラムカウンタを2進める。
  */
  case 0x5:
    vx_n := (opcode & 0x0f00) >> 8
    vy_n := (opcode & 0x00f0) >> 4

    vx := state.regs[vx_n]
    vy := state.regs[vy_n]

    if vx == vy do state.pc += 2

  /* 6xkk - LD Vx, byte

  Vxにkkをセットする。インタプリタはレジスタVxにkkの値をセットする。
  */
  case 0x6:
    vx := (opcode & 0x0f00) >> 8
    data := u8(opcode & 0x00ff)
    state.regs[vx] = data

  /* 7xkk - ADD Vx, byte

  VxにVx + kkをセットする。インタプリタはレジスタVxにkkの値を加算する。
  */
  case 0x7:
    vx := (opcode & 0x0f00) >> 8
    data := u8(opcode & 0x00ff)
    state.regs[vx] += data

  case 0x8:
    fst_nibble := opcode & 0xf
    vx := (opcode & 0x0f00) >> 8
    vy := (opcode & 0x00f0) >> 4
    old_vx := state.regs[vx]
    old_vy := state.regs[vy]

    switch fst_nibble {
    case 0x0:
      state.regs[vx] = state.regs[vy]
    case 0x1:
      state.regs[vx] |= state.regs[vy]
    case 0x2:
      state.regs[vx] &= state.regs[vy]
    case 0x3:
      state.regs[vx] ~= state.regs[vy]
    case 0x4:
      state.regs[vx] += state.regs[vy]
      if state.regs[vx] < state.regs[vy] {
        state.regs[0xf] = 1
      } else {
        state.regs[0xf] = 0
      }
    case 0x5:
      state.regs[vx] -= state.regs[vy]
      if old_vx > old_vy {
        state.regs[0xf] = 1
      } else {
        state.regs[0xf] = 0
      }
    case 0x6:
      state.regs[vx] >>= 1
      if old_vx & 1 == 1 {
        state.regs[0xf] = 1
      } else {
        state.regs[0xf] = 0
      }
    case 0x7:
      old_vy := state.regs[vy]
      state.regs[vx] = state.regs[vy] - state.regs[vx]
      if old_vy > old_vx {
        state.regs[0xf] = 1
      } else {
        state.regs[0xf] = 0
      }
    case 0xE:
      state.regs[vx] <<= 1
      if old_vx & 0x80 > 0 {
        state.regs[0xf] = 1
      } else {
        state.regs[0xf] = 0
      }
    }

  /* 9xy0 - SNE Vx, Vy
  Vx != Vyの場合、次の命令をスキップする。つまり、プログラムカウンタを2インクリメントする。
  */
  case 0x9:
    x := (opcode & 0x0f00) >> 8
    y := (opcode & 0xf0) >> 4

    vx := state.regs[x]
    vy := state.regs[y]

    if (vx != vy) {
      state.pc += 2
    }

  /* Annn - LD I, addr
  Iにnnnをセットする。
  */
  case 0xA:
    data := opcode & 0x0fff
    state.I = data

  /* Dxyn - DRW Vx, Vy, nibble
  アドレスIのnバイトのスプライトを(Vx, Vy)に描画する。Vfにはcollision(後述)をセットする。
  アドレスIのnバイトのスプライトを読み出し、スプライトとして(Vx, Vy)に描画する。スプライトは画面にXORする。このとき、消されたピクセルが一つでもある場合はVfに1、それ以外の場合は0をセットする。スプライトの一部が画面からはみ出る場合は、反対側から折り返す。
  */
  case 0xD:
    x := (opcode & 0x0f00) >> 8
    y := (opcode & 0x00f0) >> 4
    n := (opcode & 0x000f)

    start_x := state.regs[x]

    start_y := u16(state.regs[y])

    for i in 0 ..< n {
      byte := state.ram[state.I + i]
      bits_in_byte: i32 = 8
      byte_from_right := u32(state.dsp_w - bits_in_byte)
      byte_to_leftmost := u64(byte) << byte_from_right
      shifted_byte := byte_to_leftmost >> u32(start_x)

      if i32(start_x) > i32(byte_from_right) {
        // 横方向に折り返す
        num_bits_not_wrapped := u32(state.dsp_w - i32(start_x))
        shifted_byte |=
          (u64(byte) & (0xff >> num_bits_not_wrapped)) <<
          u32(state.dsp_w - (8 - i32(num_bits_not_wrapped)))
      }

      // 縦方向に折返す
      row := u16(i32(start_y + i) % state.dsp_h)

      // 衝突が起こったら、Vfに１をセット
      if (state.dsp[row] & shifted_byte) > 0 do state.regs[0xf] = 1

      state.dsp[row] ~= shifted_byte
    }

    draw_display_at(
      &state.dsp,
      state.dsp_w,
      state.dsp_h,
      state.scale,
      i32(start_y),
      i32(start_y + n),
      i32(start_x),
      i32(start_x + 8),
    )

  case 0xE:
    fst_byte := opcode & 0xff

    switch fst_byte {
    /* Ex9E - SKP Vx
    Vxが押された場合、次の命令をスキップする。
    キーボードををチェックし、Vxの値のキーが押されていればプログラムカウンタを2インクリメントする。
    */
    case 0x9e:
      x := (opcode & 0x0f00) >> 8
      key := state.regs[x]
      key = key < 10 ? key + 48 : key + 55

      if rl.IsKeyDown(rl.KeyboardKey(key)) {
        state.pc += 2
      }

    /* ExA1 - SKNP Vx
    Vxが押されてない場合、次の命令をスキップする。
    キーボードををチェックし、Vxの値のキーが押されていなければプログラムカウンタを2インクリメントする。
    */
    case 0xa1:
      x := (opcode & 0x0f00) >> 8
      key := state.regs[x]
      key = key < 10 ? key + 48 : key + 55

      if !rl.IsKeyDown(rl.KeyboardKey(key)) {
        state.pc += 2
      }
    }

  case 0xF:
    fst_byte := opcode & 0xff

    switch fst_byte {
    /* Fx0A - LD Vx, K
    押されたキーをVxにセットする。
    キーが入力されるまで全ての実行をストップする。キーが押されるとその値をVxにセットする。
    */
    case 0x0a:
      key := rl.GetKeyPressed()

      if key == rl.KeyboardKey.KEY_NULL {
        // キーが押されていない限り、この命令を繰り返す
        jumped = true
      } else {
        x := (opcode & 0x0f00) >> 8
        state.regs[x] = u8(int(key))
      }


    /* Fx1E - ADD I, Vx
    IにI + Vxをセットする
    */
    case 0x1e:
      x := (opcode & 0x0f00) >> 8

      state.I += u16(state.regs[x])

    /*Fx33 - LD B, Vx
    アドレスI, I+1、I+2にVxのBCDをセットする。
    アドレスIにVxの下位3桁目の値をセットする。I+1には下位2桁目の値をセットし、I+2には下位1桁目の値をセットする。
    */
    case 0x33:
      x := (opcode & 0x0f00) >> 8
      val := state.regs[x]

      state.ram[state.I + 2] = val % 10
      val /= 10
      state.ram[state.I + 1] = val % 10
      val /= 10
      state.ram[state.I] = val % 10

    /*Fx55 - LD [I], Vx
    V0からVxまでの値をIから始まるアドレスにセットする。
    */
    case 0x55:
      x := (opcode & 0x0f00) >> 8

      for i in 0 ..= x {
        state.ram[state.I + i] = state.regs[i]
      }

    /* Fx65 - LD Vx, [I]
    アドレスIから読んだ値をV0からVxにセットする。
    */
    case 0x65:
      x := (opcode & 0x0f00) >> 8

      for i in 0 ..= x {
        state.regs[i] = state.ram[state.I + i]
      }
    }
  }

  return jumped
}
