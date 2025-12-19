package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:prof/spall"
import "core:sync"
import "core:time"
import rl "vendor:raylib"

State :: struct {
  I:               u16,
  sp:              u8, // Stack Pointer, スタックの先頭のインデックスを表す
  pc:              u16, // 現在の実行アドレスを格納
  regs:            [16]u8,
  delay_timer:     u8,
  // NOTE: delay_timer は秒単位で更新されるが、メインループの更新は早すぎて
  // 秒単位だと時間のデルタは切り捨てられてしまう
  // そうならないように、マイクロ秒単位の変化を蓄積する
  // （ミリ秒でも切り捨てられていた）
  delay_timer_mus: u32,
  sound_timer:     u8,
  sound_timer_mus: u32,
  stack:           [16]u16,
  // HACK: RAMの最大の大きさは4096のはずだが、これじゃ
  // Quirks テストは収まらないから倍にした
  ram:             [8192]u8,
  dsp:             [32]u64,
  dsp_w:           i32,
  dsp_h:           i32,
  scale:           i32,
}
spall_ctx: spall.Context
@(thread_local)
spall_buffer: spall.Buffer

main :: proc() {
  spall_ctx = spall.context_create("trace_test.spall")
  defer spall.context_destroy(&spall_ctx)

  buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
  defer delete(buffer_backing)

  spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
  defer spall.buffer_destroy(&spall_ctx, &spall_buffer)

  run()
}

run :: proc() {
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
  rl.InitWindow(state.dsp_w * state.scale, state.dsp_h * state.scale, "Chip 8 Test")
  rl.SetTargetFPS(60)

  start := time.tick_now()

  for !rl.WindowShouldClose() {
    fst_byte := u16(state.ram[state.pc])
    snd_byte := u16(state.ram[state.pc + 1])
    opcode: u16 = fst_byte << 8 + snd_byte

    jumped := execute_opcode(opcode, &state)

    // HACK: fixes rendering issues that occurred after decoupling opcode execution from draw cycle.
    // Somehow, beginning draw every time we loop around fixed those.
    rl.BeginDrawing()
    if fst_byte & 0xf0 != 0xd0 {
      // NOTE: usually done inside EndDrawing
      rl.PollInputEvents()
    } else {
      rl.EndDrawing()
    }

    if !jumped do state.pc += 2

    // decrease delay timer at a rate of 60Hz
    delta_T := time.tick_since(start)
    delta_mus := time.duration_microseconds(delta_T)
    start = time.tick_now()

    if state.delay_timer > 0 {
      state.delay_timer_mus = max(0, state.delay_timer_mus - u32(delta_mus * 60))
      state.delay_timer = u8(state.delay_timer_mus / 1000_000)
    }

    if state.sound_timer > 0 {
      state.sound_timer_mus = max(0, state.sound_timer_mus - u32(delta_mus * 60))
      state.sound_timer = u8(state.sound_timer_mus / 1000_000)
    }
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
  for y in start_y ..< end_y {
    yy := y % HEIGHT
    row := display[yy]
    for x in start_x ..< end_x {
      xx := x % WIDTH
      xx_from_left := WIDTH - xx - 1
      set := (row & (1 << u32(xx_from_left))) > 0

      if set do rl.DrawRectangle(xx * scale, yy * scale, scale, scale, rl.WHITE)
      else do rl.DrawRectangle(xx * scale, yy * scale, scale, scale, rl.BLACK)
    }
  }
}

load_instructions_in_ram :: proc(binary: ^[]u16, state: ^State, start_addr: u16) -> u16 {
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

      rl.ClearBackground(rl.BLACK)

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

  /* Bnnn - JP V0, addr
  nnn + V0のアドレスにジャンプする。つまり、プログラムカウンタにnnn + V0をセットする
  */
  case 0xB:
    addr := opcode & 0x0fff
    // NOTE: Super-Chip quirk!
    // nnn + Vxのアドレスのジャンプ（x = 上位桁目）
    x := (opcode & 0x0f00) >> 8
    state.pc = addr + u16(state.regs[x])
    jumped = true

  /* Cxkk - RND Vx, byte
  Vxに0~255の乱数 AND kkをセットする。
  */
  case 0xC:
    x := (opcode & 0x0f00) >> 8
    kk := u8(opcode & 0x00ff)
    state.regs[x] = u8(rand.int31_max(256)) & kk

  case 0xD:
    DRW(opcode, state)

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
    /* Fx07 - LD Vx, DT
    VxにDelay timerの値dtをセットする。
    */
    case 0x07:
      x := (opcode & 0x0f00) >> 8
      state.regs[x] = state.delay_timer

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


    /* Fx15 - LD DT, Vx
    Delay timer dtにVxをセットする。
    */
    case 0x15:
      x := (opcode & 0x0f00) >> 8
      state.delay_timer = state.regs[x]
      state.delay_timer_mus = u32(state.regs[x]) * 1000_000

    /* Fx18 - LD ST, Vx
    Sound timer stにVxをセットする。
    */
    case 0x18:
      x := (opcode & 0x0f00) >> 8
      state.sound_timer = state.regs[x]
      state.sound_timer_mus = u32(state.regs[x]) * 1000_000

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

  case:
    fmt.printfln("Opcode not implemented: %4x", opcode)
  }

  return jumped
}

/*
Dxyn - DRW Vx, Vy, nibble
アドレスIのnバイトのスプライトを(Vx, Vy)に描画する。Vfにはcollision(後述)をセットする。
アドレスIのnバイトのスプライトを読み出し、スプライトとして(Vx, Vy)に描画する。スプライトは画面にXORする。このとき、消されたピクセルが一つでもある場合はVfに1、それ以外の場合は0をセットする。スプライトの一部が画面からはみ出る場合は、反対側から折り返す。
*/
DRW :: proc(opcode: u16, state: ^State) {
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
        (u64(byte) & (0xff >> num_bits_not_wrapped)) << u32(state.dsp_w - (8 - i32(num_bits_not_wrapped)))
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
}

// Automatic profiling of every procedure:

@(instrumentation_enter)
spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
  spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
}

@(instrumentation_exit)
spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
  spall._buffer_end(&spall_ctx, &spall_buffer)
}
