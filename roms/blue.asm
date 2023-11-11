.segment "HEADER"

.byte $4e, $45, $53, $1a, $02, $01, $00, $00

.segment "CODE"

.proc irq_handler
  RTI
.endproc


.proc nmi_handler
  RTI
.endproc


.proc reset_handler
  SEI

  CLD

  LDX #$00

  STX $2000

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
