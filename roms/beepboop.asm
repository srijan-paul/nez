; PPU register mnemonics
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUADDR   = $2006
PPUDATA   = $2007
OAMADDR   = $2003
OAMDMA    = $4014


.segment "HEADER"

.byte $4e, $45, $53, $1a, $02, $01, $00, $00

.segment "ZEROPAGE"

nframes_per_color: .res 1
frames_passed: .res 1
color_1: .res 1
color_2: .res 1
current_color: .res 1

.CODE

.proc irq_handler
  RTI
.endproc


.proc nmi_handler
  INC frames_passed ;increment frame count
  LDA nframes_per_color 
  CMP frames_passed ;check if we've already spent enough frames in this color
  BNE skip
  
  ;If so, switch to the next color,
  ;and set frames passed to 0
  LDA #0
  STA frames_passed

  LDA current_color ; load the current color
  CMP color_1 ; compare it to the first color
  BEQ set_color_2 ; if it's the first color, set it to the second color

set_color_1:
  ; otherwise, set it to the first color
  LDA color_1
  STA current_color
  JMP load_color_to_ppu

set_color_2:
  LDA color_2
  STA current_color

load_color_to_ppu:
  LDX $2002 ; reset the address latch write toggle.

  LDX #$3f  ; point address latch to $3f00
  STX PPUADDR
  LDX #$00
  STX PPUADDR
  LDA current_color  ; write the color to the palette bg color addr.
  STA PPUDATA

skip:
  RTI
.endproc

PaletteData:
  .byte $0F,$31,$32,$33,$0F,$35,$36,$37,$0F,$39,$3A,$3B,$0F,$3D,$3E,$0F  ;background palette data
  .byte $0F,$1C,$15,$14,$0F,$02,$38,$3C,$0F,$1C,$15,$14,$0F,$02,$38,$3C  ;sprite palette data

.proc reset_handler
  SEI

  CLD


	LDA PPUSTATUS ; reset rw toggle
	LDA #$3F
	STA PPUADDR
	LDA #$00
	STA PPUADDR

  LDX #$00
	LoadPalettesLoop:
  LDA PaletteData, x

  STA PPUDATA
  INX
  CPX #$20
  BNE LoadPalettesLoop


  LDA #$39
  STA color_1
  STA current_color

  ; set the second color to blue
  LDA #$26
  STA color_2
  
  ; set the color duration to 60 frames (roughly 1 second) 
  LDA #60
  STA nframes_per_color
  
  ; set frames passed to 0
  LDA #0
  STA frames_passed

  LDX #%10000000
  STX $2000
  LDX #$00
  STX $2001

vblankwait:
  BIT PPUSTATUS
  BPL vblankwait

vblankwait2:
  BIT PPUSTATUS
  BPL vblankwait2

  JMP main
.endproc


.proc main
  LDX PPUSTATUS

  LDA #%00011110
  STA $2001
forever:
  JMP forever
.endproc


.segment "VECTORS"

.addr nmi_handler, reset_handler, irq_handler


.segment "CHARS"

.incbin "mario.chr"

.segment "STARTUP"
