package main

import "core:fmt"

State :: struct {
  pc:    u16, // 現在の実行アドレスを格納
  sp:    u8, // Stack Pointer, スタックの先頭のインデックスを表す
  regs:  [16]u8,
  stack: [16]u16,
  ram:   [4096]u8,
}

main :: proc() {
  // プログラムを取得
  // オペコードを解読し、実行する
  // binary := #load(path, []u8)
}

load_instructions :: proc(binary: []u8, state: ^State) {
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
  }
}
