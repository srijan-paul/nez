# Nez

An emulator for the Nintendo Entertainment System made using zig and raylib.
The emulation is cycle accurate (as accurate as I could make it),
and the code well commented and avoids any clever optimizations.
The project is  meant to serve as an example to anyone wanting to write their own. 

<div style="display: flex; gap: 10px;">
    <img src="./screens/pacman.png" alt="pacman home screen" width="300px"/>
    <img src="./screens/donkey-kong.png" alt="donkey kong gameplay" width="300px"/>
</div>

## Components

### The CPU: Ricoh-2A03

An 8-bit CPU used in a wide variety of game consoles,
the most prominent of them being the NES.

It is a derivative of the MOS-6502 (almost an identical clone), without support for decimal mode.

Resources:

- [Famicom party](https://famicom.party/book/) - This book helped me write my own homebrew ROMs to test.
- [The Obelisk 6502 instruction set reference](https://www.nesdev.org/obelisk-6502-guide/reference.html)
- [Masswerk - 6502 instruction set](https://www.masswerk.at/6502/6502_instruction_set.html)
- [The ultimate 6502 reference](https://www.pagetable.com/c64ref/6502/?tab=2#)

Things to watch out for:
- Zero page wrap around for instructions that use the zero page addressing mode.
- RMW (Read-modify-write) instructions like `ROR` will first write the unmodified byte
  to the memory location, and *then* write the modified byte. This can make a difference
  with some mappers.
- The CPU and PPU must run in sync. For a single CPU cycle, the PPU executes (roughly) three clock cycles.
  A good way to emulate this is to use the delta time between two frames, and then figure out how many cycles
  each chip should execute based on their respective clockspeeds.

If you're feeling adventurous,
and want to write a cycle stepped emulator,
then [this datasheet](https://www.princeton.edu/~mae412/HANDOUTS/Datasheets/6502.pdf) can prove to be useful.

### The PPU: The Ricoh-2C02

Resources:
- [PPU - Nesdev wiki](https://www.nesdev.org/wiki/PPU)
    - You'll have to go over the documents dozens of times before things start making sense.
      There is a lot of information to take in.
- [NES PPU Notes](https://github.com/pjhades/tolarian-academy/blob/master/nes-ppu.md)
- [Austin Morlan - NES rendering overview](https://austinmorlan.com/posts/nes_rendering_overview/)
- [Famicom party](https://famicom.party/book/)

### Bus, Cartridge, Mapper, and other miscellany

Every game comes in a cartridge that contains the game code, assets, and sometimes
extra hardware and battery.

A mapper is a blanket term that describes all kinds of extra hardware present in the circuit that extend the capabilities of the game console.

The **Bus** connects the CPU, PPU, and the Cart, allowing separate components to communicate with each other.

## Building and testing

Clone the repository, then clone all submdoules, and use the zig build command

```sh
zig build run
```

The CPU has about ~10k test cases for each instruction, coming from [this awesome test repository](https://github.com/TomHarte/ProcessorTests/tree/main/nes6502).
To run the CPU tests, use `zig test src/cpu.zig`.

## TODO

- [x] Support vertical scrolling
- [ ] Sprite overflow detection
- [ ] Support horizontal scrolling
- [ ] Support split scrolling
- [ ] Add support for the controller
- [ ] Support more mappers
    - [ ] CNROM
    - [ ] UnROM
    - [ ] MMC1
    - [ ] MMC3
    - [ ] MMC5
- [ ] Add support for the APU.

## Motivation

I started out wanting to write a fantasy console,
but didn't want to invent another programming language, compiler, assembler, and then
write ROMs in those.
