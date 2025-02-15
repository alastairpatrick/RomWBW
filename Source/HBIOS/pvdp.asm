.MODULE PVDP

; Display RAM bank A layout
; Word address  Nibble address  Pages   Description
; $0000-$17FF   $0000-$BFFF     0-11    192 line scroll area
; $1800-$197F   $C000-$CBFF     12      192 scanlines
; $1C00-$1C00   $E000-$E007     14      4 color palette

; Blitter RAM layout
; Word address          Description
; $0000-$00FF           blitter FIFO
; $0100-$02FF           256 character bitmaps

#define USEFONT6X8

; Configuration
TERMENABLE      	.SET	TRUE
_WIDTH                  .EQU    80              ; 42, 64 or 80
_KEY_BUF_SIZE           .EQU    16
_ENABLE_FIFO            .EQU    1
_CURSOR_BLINK_PERIOD    .EQU    8

; Not configuration
_HEIGHT                 .EQU    24
_SCAN_WORDS             .EQU    32
_SCAN_LINES             .EQU    _HEIGHT*8

_PORT_RSEL              .EQU    $B1
_PORT_RDAT              .EQU    $B0
_PORT_BLIT              .EQU    $B2

_REG_FIFO_WRAP          .EQU    $40
_REG_LEDS               .EQU    $08
_REG_LINES_PG           .EQU    $20
_REG_KEY_ROWS           .EQU    $80
_REG_SPRITE_BM          .EQU    $30
_REG_SPRITE_RGB         .EQU    $2F
_REG_SPRITE_X           .EQU    $2B
_REG_SPRITE_Y           .EQU    $2C
_REG_START_LINE         .EQU    $22
_REG_WRAP_LINE          .EQU    $23

_BCMD_BSTREAM           .EQU    $D0
_BCMD_DCLEAR            .EQU    $84
_BCMD_DDCOPY            .EQU    $AA
_BCMD_DSTREAM           .EQU    $90
_BCMD_IMAGE             .EQU    $BF
_BCMD_NOP               .EQU    $1F
_BCMD_RECT              .EQU    $8C
_BCMD_SET_COUNT         .EQU    $03
_BCMD_SET_CLIP          .EQU    $06
_BCMD_SET_COLORS        .EQU    $05
_BCMD_SET_DST_ADDR      .EQU    $00
_BCMD_SET_SRC_ADDR      .EQU    $01
_BCMD_SET_DPITCH        .EQU    $0A
_BCMD_SET_FLAGS         .EQU    $04
_BCMD_SET_GUARD         .EQU    $0D


_FONT_SIZE              .EQU    $800

PVDP_FNTBL:
	.DW	PVDP_INIT
	.DW	PVDP_QUERY
	.DW	PVDP_RESET
	.DW	PVDP_DEVICE
	.DW	PVDP_SET_CURSOR_STYLE
	.DW	PVDP_SET_CURSOR_POS
	.DW	PVDP_SET_CHAR_ATTR
	.DW	PVDP_SET_CHAR_COLOR
	.DW	PVDP_WRITE_CHAR
	.DW	PVDP_FILL
	.DW	PVDP_COPY
	.DW	PVDP_SCROLL
	.DW	PVDP_KEYBOARD_STATUS
	.DW	PVDP_KEYBOARD_FLUSH
	.DW	PVDP_KEYBOARD_READ
#IF (($ - PVDP_FNTBL) != (VDA_FNCNT * 2))
	.ECHO	"*** INVALID PVDP FUNCTION TABLE ***\n"
#ENDIF

; Entry:
;  E: Video Mode
; Exit:
;  A: 0

PVDP_INIT:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        ; No idea what this does
        LD	IY, PVDP_IDAT

        ; Wait until VDP completes reset.
_READY_LOOP:
        LD      A, _REG_LEDS
        OUT     (_PORT_RSEL), A

        LD      A, $55
        OUT     (_PORT_RDAT), A
        IN      A, (_PORT_RDAT)
        CP      $55
        JR      NZ, _READY_LOOP

        LD      A, $AA
        OUT     (_PORT_RDAT), A
        IN      A, (_PORT_RDAT)
        CP      $AA
        JR      NZ, _READY_LOOP

#IF _ENABLE_FIFO
        ; Initialize blitter FIFO
        LD      D, 8
        LD      C, _REG_FIFO_WRAP
        CALL    _SET_REG_D
#ENDIF

        CALL    PVDP_RESET

        ; Add to VDA dispatch table
        LD      BC, PVDP_FNTBL
        LD      DE, PVDP_IDAT
        CALL    VDA_ADDENT

#IF TERMENABLE
        ; Initialize terminal emulation
        LD      C, A
        LD      DE, PVDP_FNTBL
        LD      HL, PVDP_IDAT
        CALL    TERM_ATTACH
#ENDIF

        POP     HL
        POP     DE
        POP     BC
        XOR     A
        RET

; Exit:
;  A: 0
;  C: Video Mode (0)
;  D: Row Count
;  E: Column Count
;  HL: 0

PVDP_QUERY:
        LD      C, 0
        LD      D, _HEIGHT
        LD      E, _WIDTH
        LD      HL, 0
        XOR     A
        RET


; Exit:
;  A: 0

PVDP_RESET:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        CALL    _INIT_LINES
        CAll    _COPY_FONT
        
        ; Copy palette.
        LD      DE, $E000
        LD      HL, _PALETTE
        LD      BC, _PALETTE_END - _PALETTE
        LD      A, _BCMD_DSTREAM
        CALL    _BLIT_COPY
        
        ; Lines start in page 12
        LD      C, _REG_LINES_PG
        LD      D, 12
        CALL    _SET_REG_D
        
        ; Line wraps back to 0 at 192
        LD      C, _REG_WRAP_LINE
        LD      D, 192
        CALL    _SET_REG_D

        ; Initialize LINE_START
        XOR     A
        LD      (_SCROLL), A
        CALL    _UPDATE_LINE_START

        ; Initialize cursor sprite
        LD      D, $FF
        LD      C, _REG_SPRITE_RGB
        CALL    _SET_REG_D
        
        ; Clear display area
        LD      DE, 0
        LD      C, _BCMD_SET_DST_ADDR
        CALL    _BLIT_CMD_DE

        LD      DE, $C000
        LD      C, _BCMD_SET_COUNT
        CALL    _BLIT_CMD_DE

        LD      DE, $0000       ; clear color
        LD      C, _BCMD_SET_COLORS
        CALL    _BLIT_CMD_DE

        LD      C, _BCMD_DCLEAR
        CALL    _BLIT_CMD

        ; Initial VDA state
        LD      D, $0F
        CALL    PVDP_SET_CURSOR_STYLE

        LD      E, $0F
        CALL    PVDP_SET_CHAR_COLOR

        LD      DE, $0000
        CALL    PVDP_SET_CURSOR_POS
        
        CALL    PVDP_KEYBOARD_FLUSH
        CALL    _INIT_BLIT_REGS
        CALL    _BLIT_FLUSH

        POP     HL
        POP     DE
        POP     BC
        XOR     A
        RET

_INIT_LINES:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        ; Disable display bank memory protection.
        LD      DE, $0000
        LD      C, _BCMD_SET_GUARD
        CALL    _BLIT_CMD_DE

        ; Initialize lines.
        LD      DE, $C000
        LD      C, _BCMD_SET_DST_ADDR
        CALL    _BLIT_CMD_DE

        LD      DE, _SCAN_LINES*16
        LD      C, _BCMD_SET_COUNT
        CALL    _BLIT_CMD_DE

        LD      C, _BCMD_DSTREAM
        CALL    _BLIT_CMD

        LD      HL, 0
        LD      B, _SCAN_LINES
_LINE_LOOP:
        CALL    _BLIT_SYNC

        XOR     A               ; palette word address
        OUT     (_PORT_BLIT), A
        LD      A, $1C
        OUT     (_PORT_BLIT), A

        LD      A, L            ; pixel word addr = line_idx * _SCAN_WORDS
        OUT     (_PORT_BLIT), A
        LD      A, H            
        OUT     (_PORT_BLIT), A
        
        CALL    _BLIT_SYNC

#IF (_WIDTH == 80) | (_WIDTH == 64)
        ; HIRES4 mode
        LD      A, $72
#ELSE
        ; LORES16 mode
        LD      A, $76
#ENDIF
        OUT     (_PORT_BLIT), A
        LD      A, $0F
        OUT     (_PORT_BLIT), A

        LD      A, $00
        OUT     (_PORT_BLIT), A
        OUT     (_PORT_BLIT), A

        LD      DE, _SCAN_WORDS
        ADD     HL, DE
        LD      A, H
        CP      _SCAN_WORDS * 192 / 256
        JR      NZ, _NO_LINE_WRAP
        LD      H, 0
_NO_LINE_WRAP:
        DJNZ    _LINE_LOOP

        POP     HL
        POP     DE
        POP     BC
        RET
        
_COPY_FONT:
        PUSH    BC
        PUSH    DE
        PUSH    HL

#IF USELZSA2
        ; Allocate buffer on stack
        LD      HL, -_FONT_SIZE
        ADD     HL, SP
	LD	SP, HL
        PUSH    HL

        ; Decompress font bitmaps
	EX	DE, HL
	LD	HL, FONT6X8
	CALL	DLZSA2

	POP	HL
#ELSE
	LD	HL, FONT6X8		; START OF FONT DATA
#ENDIF

        ; Copy font to blitter RAM.
        LD      DE, $0100
        LD      BC, $_FONT_SIZE
        LD      A, _BCMD_BSTREAM
        CALL    _BLIT_COPY

#IF USELZSA2
        ; Free stack buffer
        LD      HL, $_FONT_SIZE
        ADD     HL, SP
	LD	SP, HL
#ENDIF

        POP     HL
        POP     DE
        POP     BC
        RET

_UPDATE_LINE_START:
        PUSH    BC
        PUSH    DE

        LD      C, _REG_START_LINE
        LD      A, (_SCROLL)
        SLA     A
        SLA     A
        SLA     A
        LD      D, A
        CALL    _SET_REG_D

        POP     DE
        POP     BC
        RET

_INIT_BLIT_REGS:
        PUSH    DE

        ; Enable display bank memory protection.
        LD      DE, $F000
        LD      C, _BCMD_SET_GUARD
        CALL    _BLIT_CMD_DE

        ; PITCH = _SCAN_WORDS*8
        LD      DE, _SCAN_WORDS*8
        LD      C, _BCMD_SET_DPITCH
        CALL    _BLIT_CMD_DE

#IF (_WIDTH == 80) | (_WIDTH == 64)
        ; Width is in nibbles so 8 pixels @ 2bpp = 4 nibbles
        ; COUNTS = $0804
        LD      DE, $0804
#ELSE
        LD      DE, $0808
#ENDIF
        LD      C, _BCMD_SET_COUNT
        CALL    _BLIT_CMD_DE

#IF (_WIDTH == 80)
        ; CLIP = $0400
        LD      DE, $0400
#ENDIF
#IF (_WIDTH == 64)
        ; CLIP = $0400
        LD      DE, $0400
#ENDIF
#IF (_WIDTH == 42)
        ; CLIP = $0600
        LD      DE, $0600
#ENDIF
        ; 
        LD      C, _BCMD_SET_CLIP
        CALL    _BLIT_CMD_DE

#IF (_WIDTH == 80) | (_WIDTH == 64)
        ; UNPACK_8_16
        LD      DE, $0100
#ELSE
        ; UNPACK_8_32
        LD      DE, $0200
#ENDIF
        LD      C, _BCMD_SET_FLAGS
        CALL    _BLIT_CMD_DE

        POP     DE
        RET

_BLIT_FLUSH:
        PUSH    BC

        LD      C, _BCMD_NOP
        CALL    _BLIT_CMD
        CALL    _BLIT_CMD
        CALL    _BLIT_CMD

        POP     BC
        RET


; Exit
;  A: 0
;  D: Device Type
;  E: Device Number (0)

PVDP_DEVICE:
        LD      D, $77  ; TODO
        LD      E, 0
        XOR     A
        RET


; Entry:
;  D: Start (top nibble) / End (bottom nibble) Pixel Row
;  E: Style (undefined)
; Exit:
;  A: 0

PVDP_SET_CURSOR_STYLE:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      A, D
        AND     $0F
        LD      L, A

        SRL     D
        SRL     D
        SRL     D
        SRL     D
        LD      H, D

        LD      B, 7
        LD      C, _REG_SPRITE_BM+15

_CURSOR_LOOP:
        LD      A, B
        CP      H
        JP      M, _CLEAR_CURSOR_LINE
        LD      A, B
        CP      L
        JP      P, _CLEAR_CURSOR_LINE

        LD      D, $FF
        JR      _APPLY_CURSOR_LINE

_CLEAR_CURSOR_LINE:
        LD      D, $00
_APPLY_CURSOR_LINE:
        CALL    _SET_CURSOR_LINE

        DEC     B
        JP      P, _CURSOR_LOOP

        XOR     A
        POP     HL
        POP     DE
        POP     BC
        RET

_SET_CURSOR_LINE:
#IF _WIDTH == 42
        LD      A, $0F
        AND     D
        LD      E, A
        CALL    _SET_REG_E
#ENDIF
        DEC     C
#IF _WIDTH == 80
        LD      A, $3F
#ENDIF
#IF _WIDTH == 64
        LD      A, $FF
#ENDIF
#IF _WIDTH == 42
        LD      A, $FF
#ENDIF
        AND     D
        LD      E, A
        CALL    _SET_REG_E
        DEC     C
        RET

; Entry:
;  D: Row (0 indexed)
;  E: Column (0 indexed)
; Exit:
;  A: 0

PVDP_SET_CURSOR_POS:
        LD      (_POS), DE
        XOR     A
        RET


; Entry:
;  E: Character Attribute
; Exit
;  A: 1

PVDP_SET_CHAR_ATTR:
        LD      A, 1
        RET


; Entry:
;  E: Foreground Color (bottom nibble), Background Color (top nibble)
; Exit:
;  A: 0

PVDP_SET_CHAR_COLOR:
        PUSH    BC
        PUSH    DE

#IF (_WIDTH == 80) | (_WIDTH == 64)
        ; Reduce to 2-bit intensities in form FfFfBbBb
        LD      A, E
        AND     $C0             ; mask Bb
        RLC     A
        RLC     A               ; 000000Bb
        LD      D, A
        SLA     D
        SLA     D               ; 0000Bb00
        OR      D               ; 0000BbBb
        LD      D, A
        LD      A, E
        AND     $0C             ; mask Ff
        SLA     A
        SLA     A               ; 00Ff0000
        LD      E, A
        SLA     E
        SLA     E               ; Ff000000
        OR      E               ; FfFf0000
        OR      D               ; FfFfBbBb
        LD      E, A
#ELSE
        ; Swap nibbles of E
        RLC     E
        RLC     E
        RLC     E
        RLC     E
#ENDIF

        ; Store in COLORS
        LD      D, 0
        LD      C, _BCMD_SET_COLORS
        CALL    _BLIT_CMD_DE

        POP     DE
        POP     BC
        
        XOR     A
        RET


; Entry:
;  E: Character
; Exit:
;  A: 0

PVDP_WRITE_CHAR:
        CALL    _WRITE_CHAR
        CALL    _BLIT_FLUSH
        XOR     A
        RET

_WRITE_CHAR:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      HL, (_POS)
        CALL    _CALC_DADDR
        LD      C, _BCMD_SET_DST_ADDR
        CALL    _BLIT_CMD_HL

        ; LADDR = char * 2 + $100
        SLA     E
        LD      D, 1
        LD      C, _BCMD_SET_SRC_ADDR
        CALL    _BLIT_CMD_DE

        LD      C, _BCMD_IMAGE
        CALL    _BLIT_CMD

        CALL    _ADVANCE_POS

        POP     HL
        POP     DE
        POP     BC
        RET


; Entry:
;  HL: character position
; Exit:
;  HL: DADDR nibble address in display RAM, accounting for scroll

_CALC_DADDR:
        LD      A, (_SCROLL)
        ADD     A, H
        CP      _HEIGHT
        JP      M, _NO_CALC_DADDR_WRAP
        ADD     A, -_HEIGHT
_NO_CALC_DADDR_WRAP:
        LD      H, A
        SLA     H
        SLA     H
        SLA     H

#IF (_WIDTH == 80) | (_WIDTH == 42)
        ; DADDR = (row + scroll) * _SCAN_WORDS * 8 * _CHAR_HEIGHT + col * 6/2
        LD      A, L
        ADD     A, L
        ADD     A, L
#IF (_WIDTH == 42)
        SLA     A
#ELSE
        ADD     A, 8
#ENDIF
        LD      L, A
#ELSE
        ; DADDR = (row + scroll) * _SCAN_WORDS * 8 * _CHAR_HEIGHT + col * 8/2
        SLA     L
        SLA     L
#ENDIF

        RET

_ADVANCE_POS
        ; Advance character position
        LD      A, (_POS)
        INC     A
        CP      _WIDTH
        JR      NZ, _WC_SKIP_NEWLINE
        LD      A, (_POS+1)
        INC     A
        LD      (_POS+1), A
        XOR     A
_WC_SKIP_NEWLINE:
        LD      (_POS), A
        RET


; Entry:
;  E: Character
;  HL: Count
; Exit
;  A: 0

PVDP_FILL:
        PUSH    HL

        JR      _FILL_TEST
_FILL_LOOP:
        CALL    _WRITE_CHAR
        DEC     HL
_FILL_TEST:
        LD      A, H
        OR      L
        JR      NZ, _FILL_LOOP

        CALL    _BLIT_FLUSH

        POP     HL
        XOR     A
        RET


; Entry:
;  D: Source Row
;  E: Source Column
;  L: Count
; Exit:
;  A: 0

PVDP_COPY:
        PUSH    BC
        PUSH    DE

        LD      B, L
_COPY_LOOP
        CALL    _COPY_1_CHAR
        CALL    _ADVANCE_POS

        ; Advance source position
        INC     E
        LD      A, E
        CP      _WIDTH
        JR      NZ, _COPY_NO_WRAP
        LD      E, 0
        INC     D

_COPY_NO_WRAP:
        DJNZ    _COPY_LOOP

        CALL    _BLIT_FLUSH

        POP     DE
        POP     BC
        XOR     A
        RET

_COPY_1_CHAR:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      HL, (_POS)
        CALL    _CALC_DADDR
        LD      C, _BCMD_SET_DST_ADDR
        CALL    _BLIT_CMD_HL

        EX      DE, HL
        CALL    _CALC_DADDR
        LD      C, _BCMD_SET_SRC_ADDR
        CALL    _BLIT_CMD_HL

        LD      C, _BCMD_DDCOPY
        CALL    _BLIT_CMD

        POP     HL
        POP     DE
        POP     BC
        RET


; Entry
;  E: Scroll Distance (signed)
; Exit:
;  A: 0

PVDP_SCROLL:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      B, E
        BIT     7, E
        JP      NZ, _NEG_SCROLL

_FORWARD_LOOP:
        PUSH    BC
        CALL    _SCROLL_FORWARD
        POP     BC
        DJNZ    _FORWARD_LOOP
        JR      _SCROLL_DONE

_NEG_SCROLL
        LD      A, 0
        SUB     B
        LD      B, A

_BACKWARD_LOOP:
        PUSH    BC
        CALL    _SCROLL_BACKWARD
        POP     BC
        DJNZ    _BACKWARD_LOOP

_SCROLL_DONE:

        CALL    _UPDATE_LINE_START
        CALL    _INIT_BLIT_REGS
        CALL    _BLIT_FLUSH

        POP     HL
        POP     DE
        POP     BC
        XOR     A
        RET

_SCROLL_FORWARD:
        ; Update _SCROLL
        LD      A, (_SCROLL)
        INC     A
        CP      _HEIGHT
        JR      NZ, _NO_SCROLL_FORWARD_WRAP
        XOR     A
_NO_SCROLL_FORWARD_WRAP:        
        LD      (_SCROLL), A

        ; Bottom row
        LD      HL, (_HEIGHT-1)*256
        JR      _SCROLL_CLEAR

_SCROLL_BACKWARD:
        ; Update SCROLL
        LD      A, (_SCROLL)
        DEC     A
        JP      P, _NO_SCROLL_BACKWARD_WRAP
        LD      A, _HEIGHT-1
_NO_SCROLL_BACKWARD_WRAP:
        LD      (_SCROLL), A

        ; Top row
        LD      HL, 0

_SCROLL_CLEAR:
        CALL    _CALC_DADDR
        LD      C, _BCMD_SET_DST_ADDR
        CALL    _BLIT_CMD_HL

#IF (_WIDTH == 80)
        LD      DE, $08F0
#ENDIF
#IF (_WIDTH == 64)
        LD      DE, $0800
#ENDIF
#IF (_WIDTH == 42)
        LD      DE, $08FC
#ENDIF
        LD      C, _BCMD_SET_COUNT
        CALL    _BLIT_CMD_DE

        LD      C, _BCMD_RECT
        CALL    _BLIT_CMD

        RET


; Exit:
;  A: 0

PVDP_KEYBOARD_FLUSH:
        XOR     A
        LD      (_KEY_BUF_BEGIN), A
        LD      (_KEY_BUF_END), A
        RET


; Exit:
;  A: Count

PVDP_KEYBOARD_STATUS:
        PUSH    DE

        CALL    _GET_MODIFIER_KEYS
        CALL    _SCAN_ROWS

        LD      A, (_KEY_BUF_BEGIN)
        LD      D, A
        LD      A, (_KEY_BUF_END)
        SUB     D
        AND     _KEY_BUF_SIZE-1
        SRL     A
        SRL     A

        POP     DE
        JP      Z, CIO_IDLE
        RET


; Exit:
;  A: 0
;  C: AT Scancode
;  D: Modifier State
;  E: ASCII Code

PVDP_KEYBOARD_READ:
        PUSH    HL

        ; Keep scanning until a key is available in the buffer
        LD      HL, -_CURSOR_BLINK_PERIOD
_KEYBOARD_READ_EMPTY:
        CALL    _GET_MODIFIER_KEYS
        CALL    _SCAN_ROWS

        LD      A, (_KEY_BUF_BEGIN)
        LD      E, A
        LD      A, (_KEY_BUF_END)
        CP      E
        JR      NZ, _KEYBOARD_READ_NOT_EMPTY

        LD      DE, _CURSOR_BLINK_PERIOD
        ADD     HL, DE
        LD      A, H
        AND     A
        JP      M, _CURSOR_HIDDEN

        CALL    _SHOW_CURSOR
        JR      _KEYBOARD_READ_EMPTY

_CURSOR_HIDDEN:
        CALL    _HIDE_CURSOR
        JR      _KEYBOARD_READ_EMPTY

_KEYBOARD_READ_NOT_EMPTY:

        ; Advance buffer begin pointer
        LD      HL, _KEY_BUF
        LD      D, 0
        ADD     HL, DE
        LD      A, E
        ADD     A, 4
        AND     _KEY_BUF_SIZE-1
        LD      (_KEY_BUF_BEGIN), A

        ; Get ASCII code, modifier state and AT scan code from buffer
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        INC     HL
        LD      C, (HL)

        CALL    _HIDE_CURSOR

        XOR     A
        POP     HL
        RET

_SHOW_CURSOR:
        PUSH    BC
        PUSH    DE
        
        LD      DE, (_POS)

        ; SPRITE_Y = row*8
        SLA     D
        SLA     D
        SLA     D
        LD      C, _REG_SPRITE_Y
        CALL    _SET_REG_D

#IF (_WIDTH == 80) | (_WIDTH == 42)
        ; SPRITE_X = col*3+8 or SPRITE_X = col*6
        LD      A, E
        ADD     A, E
        ADD     A, E
#IF (_WIDTH == 42)
        SLA     A
#ELSE
        ADD     A, 8
#ENDIF
        LD      D, A
#ELSE
        ; SPRITE_X = col*4
        SLA     E
        SLA     E
        LD      D, E
#ENDIF

        LD      C, _REG_SPRITE_X
        CALL    _SET_REG_D

        POP     DE
        POP     BC
        RET

_HIDE_CURSOR:
        PUSH    BC
        PUSH    DE

        LD      D, 255
        LD      C, _REG_SPRITE_Y
        CALL    _SET_REG_D

        POP     DE
        POP     BC
        RET

_GET_MODIFIER_KEYS:
        PUSH    BC

        ; All modifier keys are on row 6
        LD      C, _REG_KEY_ROWS+6
        CALL    _GET_REG

        ; Rotate SHIFT, CTRL, ALT into C
        SRL     A
        RR      C
        SRL     A
        RR      C
        SRL     A
        RR      C

        ; Skip CAPS
        SRL     A

        ; Rotate ALT into C
        SRL     A
        RR      C

        ; Rotate C into place
        SRL     C
        SRL     C
        SRL     C
        SRL     C

        LD      A, (_MODIFIER_KEYS)
        AND     $F0     ; keep lock keys, zero rest
        OR      C
        LD      (_MODIFIER_KEYS), A

        POP     BC
        RET

_SCAN_ROWS:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      B, 10
        LD      HL, _LAST_KEY_STATE+11
_SCAN_ROWS_LOOP:
        ; Get current row state
        LD      A, B
        ADD     A, _REG_KEY_ROWS
        LD      C, A
        CALL    _GET_REG
        LD      E, A

        ; Get last row state
        DEC     HL
        LD      D, (HL)
        LD      (HL), E

        ; Find newly pressed keys
        XOR     D
        AND     E
        LD      D, A
        CALL    NZ, _SCAN_COLS

        DEC     B
        JP      P, _SCAN_ROWS_LOOP

        POP     HL
        POP     DE
        POP     BC
        RET

; Entry:
;  B: Row
;  D: Newly pressed keys
; Exit:
;  A: Mask with one bit set corresponding to buffered key
_SCAN_COLS:
        PUSH    BC
        PUSH    DE

        LD      C, 0
_SCAN_ROW_LOOP:
        SRL     D
        CALL    C, _INSERT_KEY
        INC     C
        LD      A, D
        AND     A
        JR      NZ, _SCAN_ROW_LOOP

        POP     DE
        POP     BC
        RET

; Entry:
;  B: Row
;  C: Column
_INSERT_KEY:
        CALL    _MSX_CODE_TO_ASCII
        AND     A
        RET     Z

        PUSH    DE
        PUSH    HL

        PUSH    BC
        LD      C, A

        ; Advance END ptr if no overflow
        LD      A, (_KEY_BUF_END)
        LD      E, A
        ADD     A, 4
        AND     _KEY_BUF_SIZE-1
        LD      D, A

        LD      A, (_KEY_BUF_BEGIN)
        CP      D
        JR      Z, _KEY_PRESSED_DONE

        LD      A, D
        LD      (_KEY_BUF_END), A
        LD      HL, _KEY_BUF
        LD      D, 0
        ADD     HL, DE

        ; Insert ASCII into buffer
        LD      A, C
        LD      (HL), A

        ; Add keypad modifier - keypad is rows 9 & 10
        LD      A, B
        POP     BC
        CP      9
        LD      A, (_MODIFIER_KEYS)
        JP      M, _NOT_KEYPAD
        OR      $80
_NOT_KEYPAD:

        ; Insert modifiers into buffer
        INC     HL
        LD      (HL), A

        ; Insert AT scan code into buffer
        CALL    _MSX_CODE_TO_AT
        INC     HL
        LD      (HL), A

_KEY_PRESSED_DONE:
        POP     HL
        POP     DE
        RET

_MSX_CODE_TO_ASCII:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        ; Col in bits 0-2
        ; Row in bits 3-6
        SLA     B
        SLA     B
        SLA     B
        LD      A, C
        OR      B
        LD      E, A

        ; Toggle CAPS? (row 6 col 3)
        CP      6*8+3
        CALL    Z, _TOGGLE_CAPS_LOCK_KEY

        ; SHIFT state in bit 1 of modifiers
        LD      HL, _ASCII_LOWER
        LD      A, (_MODIFIER_KEYS)
        AND     $01
        JR      Z, _IS_LOWER
        LD      HL, _ASCII_UPPER
_IS_LOWER:
        LD      D, 0
        ADD     HL, DE
        LD      A, (HL)
        LD      D, A
        
        ; Check for letter
        AND     $DF     ; to upper case
        CP      'A'
        JP      M, _RETURN_ASCII
        CP      'Z'+1
        JP      P, _RETURN_ASCII

        ; Check for CTRL code
        LD      A, (_MODIFIER_KEYS)
        AND     $02
        JR      Z, _CHECK_CAPS_LOCK

        ; Retain only low 5-bits of ASCII code, yielding 0-26.
        LD      A, D
        AND     $1F
        LD      D, A
        JR      _RETURN_ASCII

_CHECK_CAPS_LOCK:
        ; Check caps lock is enabled
        LD      A, (_MODIFIER_KEYS)
        AND     $40
        JR      Z, _RETURN_ASCII

        ; Swap case
        LD      A, D
        XOR     $20
        LD      D, A

_RETURN_ASCII:
        LD      A, D
        POP     HL
        POP     DE
        POP     BC
        RET


_MSX_CODE_TO_AT:
        PUSH    DE
        PUSH    HL

        ; TODO: this doesn't work!
        LD      HL, _AT_CODES
        LD      D, 0
        ADD     HL, DE
        LD      A, (HL)

        POP     HL
        POP     DE
        RET


_TOGGLE_CAPS_LOCK_KEY:
        PUSH    BC
        PUSH    DE

        LD      A, (_MODIFIER_KEYS)
        XOR     $40
        LD      (_MODIFIER_KEYS), A

        ; Update the LEDs.
        LD      D, A
        LD      C, _REG_LEDS
        CALL    _SET_REG_D

        POP     DE
        POP     BC
        RET

_GET_REG
        LD      A, C
        OUT     (_PORT_RSEL), A
        IN      A, (_PORT_RDAT)
        RET

_SET_REG_D:
        LD      A, C
        OUT     (_PORT_RSEL), A
        LD      A, D
        OUT     (_PORT_RDAT), A
        RET

_SET_REG_E:
        LD      A, C
        OUT     (_PORT_RSEL), A
        LD      A, E
        OUT     (_PORT_RDAT), A
        RET

_BLIT_SYNC:
        IN      A, (_PORT_BLIT)
        AND     A
        RET     NZ
        JR      _BLIT_SYNC

_BLIT_CMD:
        IN      A, (_PORT_BLIT)
        AND     A
        JR      Z, _BLIT_CMD
        LD      A, C
        OUT     (_PORT_BLIT), A
        RET

_BLIT_CMD_D:
        IN      A, (_PORT_BLIT)
        AND     A
        JR      Z, _BLIT_CMD_D
        LD      A, C
        LD      C, _PORT_BLIT
        OUT     (C), A
        OUT     (C), D
        RET

_BLIT_CMD_DE:
        IN      A, (_PORT_BLIT)
        AND     A
        JR      Z, _BLIT_CMD_DE
        LD      A, C
        LD      C, _PORT_BLIT
        OUT     (C), A
        OUT     (C), E
        OUT     (C), D
        RET

_BLIT_CMD_HL:
        IN      A, (_PORT_BLIT)
        AND     A
        JR      Z, _BLIT_CMD_HL
        LD      A, C
        LD      C, _PORT_BLIT
        OUT     (C), A
        OUT     (C), L
        OUT     (C), H
        RET

; Entry:
;  A: blitter cmd
;  BC: byte count >=4, multiple of 4 
;  DE: destination address (of nibble)
;  HL: source ptr
_BLIT_COPY:
        PUSH    DE

        PUSH    AF

        PUSH    BC
        LD      C, _BCMD_SET_DST_ADDR
        CALL    _BLIT_CMD_DE
        POP     BC

        ; Set COUNT
        PUSH    BC
        LD      D, B
        LD      E, C
        SLA     E
        RL      D
        LD      C, _BCMD_SET_COUNT
        CALL    _BLIT_CMD_DE
        POP     BC

        POP     AF

        PUSH    BC
        LD      C, A
        CALL    _BLIT_CMD
        POP     BC        

        CALL    _BLIT_WRITE

        POP     DE
        RET


; Entry:
;  HL: source ptr
;  BC: byte count >=4, multiple of 4 

_BLIT_WRITE:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      D, B
        LD      B, C
        LD      A, C
        AND     A
        JR      Z, _BLIT_WRITE_SKIP
        INC     D
_BLIT_WRITE_SKIP:
        LD      C, _PORT_BLIT
_BLIT_WRITE_LOOP:
        CALL    _BLIT_SYNC
        OUTI
        OUTI
        OUTI
        OUTI
        JR      NZ, _BLIT_WRITE_LOOP
        DEC     D
        JR      NZ, _BLIT_WRITE_LOOP

        POP     HL
        POP     DE
        POP     BC
        RET


_KEY_BUF_BEGIN:         .DB     0
_KEY_BUF_END:           .DB     0
_MODIFIER_KEYS:         .DB     0
_LAST_KEY_STATE:        .FILL   11, 0
_KEY_BUF:               .FILL   _KEY_BUF_SIZE, 0

_POS                    .DW     0
_SCROLL                 .DB     0

; ASCII codes >=E0 are assigned as in RomWBW Architecture doc.
_ASCII_LOWER:           .DB     "01234567"                                      ; row 0
                        .DB     "89-=\\[];"                                     ; row 1
                        .DB     $27, $60, $2C, $2E, "/", $F3, "ab"              ; row 2
                        .DB     "cdefghij"                                      ; row 3
                        .DB     "klmnopqr"                                      ; row 4
                        .DB     "stuvwxyz"                                      ; row 5
                        .DB     $00, $00, $00, $00, $00, $E0, $E1, $E2          ; row 6
                        .DB     $E3, $E4, $1B, $09, $F5, $08, $F4, $0D          ; row 7
                        .DB     $20, $F2, $F0, $F1, $F8, $F6, $F7, $F9          ; row 8
                        .DB     "*+/01234"                                      ; row 9
                        .DB     "56789-,."                                      ; row 10

_ASCII_UPPER:           .DB     ")!@#$%^&"                                      ; row 0
                        .DB     "*(_+|{}:"                                      ; row 1
                        .DB     "\"~<>?", $F3, "AB"                             ; row 2
                        .DB     "CDEFGHIJ"                                      ; row 3
                        .DB     "KLMNOPQR"                                      ; row 4
                        .DB     "STUVWXYZ"                                      ; row 5
                        .DB     $00, $00, $00, $00, $00, $E0, $E1, $E2          ; row 6
                        .DB     $E3, $E4, $1B, $09, $F5, $08, $F4, $0D          ; row 7
                        .DB     $20, $F2, $F0, $F1, $F8, $F6, $F7, $F9          ; row 8
                        .DB     "*+/01234"                                      ; row 9
                        .DB     "56789-,."                                      ; row 10

                        ;       0    1    2    3    4    5    6    7    
_AT_CODES:              .DB     $45, $16, $1E, $26, $25, $2E, $36, $3D          ; row 0
                        .DB     $3E, $46, $4E, $55, $5D, $54, $5B, $4C          ; row 1
                        .DB     $76, $0E, $41, $49, $4A, $69, $1C, $32          ; row 2
                        .DB     $21, $23, $24, $2B, $34, $33, $43, $3B          ; row 3
                        .DB     $42, $4B, $3A, $31, $44, $4D, $15, $2D          ; row 4
                        .DB     $1B, $2C, $3C, $2A, $1D, $22, $35, $1A          ; row 5
                        .DB     $00, $00, $00, $00, $00, $05, $06, $04          ; row 6
                        .DB     $0C, $03, $76, $0D, $7A, $66, $7D, $5A          ; row 7
                        .DB     $29, $6C, $70, $71, $6B, $75, $72, $74          ; row 8
                        .DB     $7C, $79, $4A, $70, $69, $72, $7A, $6B          ; row 9
                        .DB     $73, $74, $6C, $75, $7D, $7B, $41, $71          ; row 10

_PALETTE:
#IF (_WIDTH == 80) | (_WIDTH == 64)
                        .DB     %00000000
                        .DB     %10101101
                        .DB     %01010010
                        .DB     %11111111
#ELSE
                        .DB     %00000000
                        .DB     %00000011
                        .DB     %00011000
                        .DB     %00100011
                        .DB     %10000000
                        .DB     %10100000
                        .DB     %10000100
                        .DB     %11101101
                        .DB     %01010010
                        .DB     %01010110
                        .DB     %01110010
                        .DB     %00111111
                        .DB     %11010010
                        .DB     %11010111
                        .DB     %11111011
                        .DB     %11111111
#ENDIF
_PALETTE_END:

PVDP_IDAT:
        .DB     _PORT_RSEL
        .DB     _PORT_RDAT
        .DB     _PORT_BLIT
