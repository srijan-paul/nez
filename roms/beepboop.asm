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
  STX $2006 
  LDX #$00
  STX $2006
  LDA current_color  ; write the color to the palette bg color addr.
  STA $2007

skip:
  RTI
.endproc


.proc reset_handler
  SEI

  CLD

  ; set the first color to green.
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
  BIT $2002
  BPL vblankwait

vblankwait2:
  BIT $2002
  BPL vblankwait2

  JMP main
.endproc


.proc main
  LDX $2002
  LDX #$3f
  STX $2006
  LDX #$00
  STX $2006

  LDA #$1C
  STA $2007

  LDA #%00011110
  STA $2001

forever:
  JMP forever
.endproc


.segment "VECTORS"

.addr nmi_handler, reset_handler, irq_handler


.segment "CHARS"

.res 8192

.segment "STARTUP"
