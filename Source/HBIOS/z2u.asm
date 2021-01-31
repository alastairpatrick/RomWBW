;
;==================================================================================================
; Z280 UART DRIVER (Z280 BUILT-IN UART)
;==================================================================================================
;
;  SETUP PARAMETER WORD:
;  +-------+---+-------------------+ +---+---+-----------+---+-------+
;  |	   |RTS| ENCODED BAUD RATE | |DTR|XON|	PARITY	 |STP| 8/7/6 |
;  +-------+---+---+---------------+ ----+---+-----------+---+-------+
;    F	 E   D	 C   B	 A   9	 8     7   6   5   4   3   2   1   0
;	-- MSB (D REGISTER) --		 -- LSB (E REGISTER) --
;
; CONFIG ($FE__10):
; 7 6 5 4 3 2 1 0
; 1 1 0 0 0 0 1 0   DEFAULT VALUES
; | | | | | | | |
; | | | | | | | |
; | | | | | | | +-- LB:		LOOP BACK ENABLE
; | | | | | + +---- CR:		CLOCK RATE
; | | | | +-------- CS:		CLOCK SELECT
; | | | +---------- E/O:	EVEN/ODD
; | | +------------ P:		PARITY
; + +-------------- B/C:	BITS PER CHARACTER
;
; TRANSMITTER CONTROL/STATUS REGISTER ($FE__12)
; 7 6 5 4 3 2 1 0
; 1 0 0 0 0 0 0 0   DEFAULT VALUES
; | | | | | | | |
; | | | | | | | +-- BE:		BUFFER EMPTY
; | | | | | | +---- VAL:	VALUE
; | | | | | +------ FRC:	FORCE CHARACTER
; | | | | +-------- BRK:	SEND BREAK
; | | | +---------- SB:		STOP BITS
; | | +------------ 0:		RESERVED (SET TO 0)
; | +-------------- IE:		XMIT INT ENBABLE
; +---------------- EN:		TRANSMITTER ENABLE
;
; RECEIVER CONTROL/STATUS REGISTER ($FE__14)
; 7 6 5 4 3 2 1 0
; 1 0 0 0 0 0 0 0   DEFAULT VALUES
; | | | | | | | |
; | | | | | | | +-- ERR:	LOGICAL OR OF (OVE, PE, FE)
; | | | | | | +---- OVE:	OVERRUN ERROR
; | | | | | +------ PE:		PARITY ERROR
; | | | | +-------- FE:		FRAMING ERROR
; | | | +---------- CA:		RECEIVE CHAR AVAILABLE
; | | +------------ 0:		RESERVED (SET TO 0)
; | +-------------- IE:		RECEIVER INT ENBABLE
; +---------------- EN:		RECEIVER ENABLE
;
; INTERRUPT DRIVEN PROCESSING IS ONLY USED WHEN THE SYSTEM IS IN
; INTERRUPT MODE 3.  THIS IS BECAUSE THE BUILT-IN UART *ALWAYS* USES
; MODE 3 PROCESSING.  SINCE MODE 3 PROCESSING REQUIRES THE MODE 3
; INTERRUPT VECTOR TABLE WHICH IS LARGE AND WON'T FIT WELL IN HIGH
; RAM, IT IS IMPRACTICAL TO IMPLEMENT ANY INTERRUPT DRIVEN PROCESSING
; UNLESS FULL BLOWN INTERRUPT MODE 3 W/ NATIVE MEMORY MANAGEMENT
; IS BEING USED.
;
Z2U_BUFSZ	.EQU	32		; RECEIVE RING BUFFER SIZE
;
Z2U_NONE	.EQU	0		; NOT PRESENT
Z2U_PRESENT	.EQU	1		; PRESENT
;
;
;
Z2U_PREINIT:
;
; SETUP THE DISPATCH TABLE ENTRIES
; NOTE: INTS WILL BE DISABLED WHEN PREINIT IS CALLED AND THEY MUST REMAIN
; DISABLED.
;
	LD	B,Z2U_CFGCNT		; LOOP CONTROL
	XOR	A			; ZERO TO ACCUM
	LD	(Z2U_DEV),A		; CURRENT DEVICE NUMBER
	LD	IY,Z2U_CFG		; POINT TO START OF CFG TABLE
Z2U_PREINIT0:
	PUSH	BC			; SAVE LOOP CONTROL
	CALL	Z2U_INITUNIT		; HAND OFF TO GENERIC INIT CODE
	POP	BC			; RESTORE LOOP CONTROL
;
	LD	A,(IY+1)		; GET THE Z280 UART TYPE DETECTED
	OR	A			; SET FLAGS
	JR	Z,Z2U_PREINIT2		; SKIP IT IF NOTHING FOUND
;
	PUSH	BC			; SAVE LOOP CONTROL
	PUSH	IY			; CFG ENTRY ADDRESS
	POP	DE			; ... TO DE
	LD	BC,Z2U_FNTBL		; BC := FUNCTION TABLE ADDRESS
	CALL	NZ,CIO_ADDENT		; ADD ENTRY IF Z2U FOUND, BC:DE
	POP	BC			; RESTORE LOOP CONTROL
;
Z2U_PREINIT2:
	LD	DE,Z2U_CFGSIZ		; SIZE OF CFG ENTRY
	ADD	IY,DE			; BUMP IY TO NEXT ENTRY
	DJNZ	Z2U_PREINIT0		; LOOP UNTIL DONE
;
#IF (INTMODE == 3)
	; SETUP INT VECTORS AS APPROPRIATE
	LD	A,(Z2U_DEV)		; GET DEVICE COUNT
	OR	A			; SET FLAGS
	JR	Z,Z2U_PREINIT3		; IF ZERO, NO Z2U DEVICES, ABORT
;
	LD	HL,Z2U_INT		; GET INT VECTOR
	LD	(Z280_IVT+$36),HL	; SET IT
#ENDIF
;
Z2U_PREINIT3:
	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN
;
; Z280 UART INITIALIZATION ROUTINE
;
Z2U_INITUNIT:
	CALL	Z2U_DETECT		; DETERMINE Z280 UART TYPE
	LD	(IY+1),A		; SAVE IN CONFIG TABLE
	OR	A			; SET FLAGS
	RET	Z			; ABORT IF NOTHING THERE

	; UPDATE WORKING Z280 UART DEVICE NUM
	LD	HL,Z2U_DEV		; POINT TO CURRENT UART DEVICE NUM
	LD	A,(HL)			; PUT IN ACCUM
	INC	(HL)			; INCREMENT IT (FOR NEXT LOOP)
	LD	(IY),A			; UPDATE UNIT NUM
;
	; IT IS EASY TO SPECIFY A SERIAL CONFIG THAT CANNOT BE IMPLEMENTED
	; DUE TO THE CONSTRAINTS OF THE Z280 UART.  HERE WE FORCE A GENERIC
	; FAILSAFE CONFIG ONTO THE CHANNEL.  IF THE SUBSEQUENT "REAL"
	; CONFIG FAILS, AT LEAST THE CHIP WILL BE ABLE TO SPIT DATA OUT
	; AT A RATIONAL BAUD/DATA/PARITY/STOP CONFIG.
	CALL	Z2U_INITSAFE
;
	; SET DEFAULT CONFIG
	LD	DE,-1			; LEAVE CONFIG ALONE
	; CALL INITDEV TO IMPLEMENT CONFIG, BUT NOTE THAT WE CALL
	; THE INITDEVX ENTRY POINT THAT DOES NOT ENABLE/DISABLE INTS!
	JP	Z2U_INITDEVX		; IMPLEMENT IT AND RETURN
;
;
;
Z2U_INIT:
	LD	B,Z2U_CFGCNT		; COUNT OF POSSIBLE Z2U UNITS
	LD	IY,Z2U_CFG		; POINT TO START OF CFG TABLE
Z2U_INIT1:
	PUSH	BC			; SAVE LOOP CONTROL
	LD	A,(IY+1)		; GET Z2U TYPE
	OR	A			; SET FLAGS
	CALL	NZ,Z2U_PRTCFG		; PRINT IF NOT ZERO
	POP	BC			; RESTORE LOOP CONTROL
	LD	DE,Z2U_CFGSIZ		; SIZE OF CFG ENTRY
	ADD	IY,DE			; BUMP IY TO NEXT ENTRY
	DJNZ	Z2U_INIT1		; LOOP TILL DONE
;
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
; RECEIVE INTERRUPT HANDLER
;
#IF (INTMODE == 3)
;
; INT ENTRY POINT
;
Z2U_INT:
	; DISCARD REASON CODE
	INC	SP
	INC	SP
;
	; SAVE REGISTERS
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
;
	; START BY SELECTING I/O PAGE $FE
	LD	L,$FE			; Z280 UART REGISTERS AT I/O PAGE $FE
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	; CHECK TO SEE IF SOMETHING IS ACTUALLY THERE
	IN	A,(Z280_UARTRCTL)	; GET STATUS
	AND	$10			; ISOLATE CHAR AVAILABLE BIT
	JR	Z,Z2U_INTRCV4		; IF NOT, BAIL OUT
;
Z2U_INTRCV1:
	; RECEIVE CHARACTER INTO BUFFER
	IN	A,(Z280_UARTRECV)	; GET A BYTE
	LD	B,A			; SAVE BYTE READ
	LD	HL,Z2U0_RCVBUF		; SET HL TO START OF BUFFER STRUCT
	LD	A,(HL)			; GET COUNT
	CP	Z2U_BUFSZ		; COMPARE TO BUFFER SIZE
	JR	Z,Z2U_INTRCV4		; BAIL OUT IF BUFFER FULL, RCV BYTE DISCARDED
	INC	A			; INCREMENT THE COUNT
	LD	(HL),A			; AND SAVE IT
	CP	Z2U_BUFSZ / 2		; BUFFER GETTING FULL?
	JR	NZ,Z2U_INTRCV2		; IF NOT, BYPASS CLEARING RTS
	; THIS IS WHERE WE SHOULD DEASSERT RTS, BUT THE Z2U HAS NONE
Z2U_INTRCV2:
	INC	HL			; HL NOW HAS ADR OF HEAD PTR
	PUSH	HL			; SAVE ADR OF HEAD PTR
	LD	A,(HL)			; DEREFERENCE HL
	INC	HL
	LD	H,(HL)
	LD	L,A			; HL IS NOW ACTUAL HEAD PTR
	LD	(HL),B			; SAVE CHARACTER RECEIVED IN BUFFER AT HEAD
	INC	HL			; BUMP HEAD POINTER
	POP	DE			; RECOVER ADR OF HEAD PTR
	LD	A,L			; GET LOW BYTE OF HEAD PTR
	SUB	Z2U_BUFSZ+4		; SUBTRACT SIZE OF BUFFER AND POINTER
	CP	E			; IF EQUAL TO START, HEAD PTR IS PAST BUF END
	JR	NZ,Z2U_INTRCV3		; IF NOT, BYPASS
	LD	H,D			; SET HL TO
	LD	L,E			; ... HEAD PTR ADR
	INC	HL			; BUMP PAST HEAD PTR
	INC	HL
	INC	HL
	INC	HL			; ... SO HL NOW HAS ADR OF ACTUAL BUFFER START
Z2U_INTRCV3:
	EX	DE,HL			; DE := HEAD PTR VAL, HL := ADR OF HEAD PTR
	LD	(HL),E			; SAVE UPDATED HEAD PTR
	INC	HL
	LD	(HL),D

	; CHECK FOR MORE PENDING...
	IN	A,(Z280_UARTRCTL)	; GET STATUS
	AND	$10			; ISOLATE CHAR AVAILABLE BIT
	JR	NZ,Z2U_INTRCV1
;
Z2U_INTRCV4:
	; RESTORE I/O PAGE TO $00
	LD	L,$00			; NORMAL I/O REG IS $00
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	; RESTORE REGISTERS
	POP	HL
	POP	DE
	POP	BC
	POP	AF
;
	.DB	$ED,$55			; RETIL
#ENDIF
;
; DRIVER FUNCTION TABLE
;
Z2U_FNTBL:
	.DW	Z2U_IN
	.DW	Z2U_OUT
	.DW	Z2U_IST
	.DW	Z2U_OST
	.DW	Z2U_INITDEV
	.DW	Z2U_QUERY
	.DW	Z2U_DEVICE
#IF (($ - Z2U_FNTBL) != (CIO_FNCNT * 2))
	.ECHO	"*** INVALID Z2U FUNCTION TABLE ***\n"
#ENDIF
;
#IF (INTMODE < 3)
;
Z2U_IN:
	CALL	Z2U_IST			; CHECK FOR CHAR READY
	JR	Z,Z2U_IN		; IF NOT, LOOP
;
	; START BY SELECTING I/O PAGE $FE
	LD	L,$FE			; Z280 UART REGISTERS AT I/O PAGE $FE
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	; GET CHAR
	IN	A,(Z280_UARTRECV)	; GET A BYTE
	LD	E,A			; PUT IN E FOR RETURN
;	
	; RESTORE I/O PAGE TO $00
	LD	L,$00			; NORMAL I/O REG IS $00
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
#ELSE
;
Z2U_IN:
	CALL	Z2U_IST			; SEE IF CHAR AVAILABLE
	JR	Z,Z2U_IN		; LOOP UNTIL SO
	HB_DI				; AVOID COLLISION WITH INT HANDLER
	LD	L,(IY+6)		; SET HL TO
	LD	H,(IY+7)		; ... START OF BUFFER STRUCT
	LD	A,(HL)			; GET COUNT
	DEC	A			; DECREMENT COUNT
	LD	(HL),A			; SAVE UPDATED COUNT
	; THIS IS WHERE WE SHOULD ASSERT RTS, BUT THE Z2U HAS NONE
Z2U_IN1:
	INC	HL			; HL := ADR OF TAIL PTR
	INC	HL			; "
	INC	HL			; "
	PUSH	HL			; SAVE ADR OF TAIL PTR
	LD	A,(HL)			; DEREFERENCE HL
	INC	HL
	LD	H,(HL)
	LD	L,A			; HL IS NOW ACTUAL TAIL PTR
	LD	C,(HL)			; C := CHAR TO BE RETURNED
	INC	HL			; BUMP TAIL PTR
	POP	DE			; RECOVER ADR OF TAIL PTR
	LD	A,L			; GET LOW BYTE OF TAIL PTR
	SUB	Z2U_BUFSZ+2		; SUBTRACT SIZE OF BUFFER AND POINTER
	CP	E			; IF EQUAL TO START, TAIL PTR IS PAST BUF END
	JR	NZ,Z2U_IN2		; IF NOT, BYPASS
	LD	H,D			; SET HL TO
	LD	L,E			; ... TAIL PTR ADR
	INC	HL			; BUMP PAST TAIL PTR
	INC	HL			; ... SO HL NOW HAS ADR OF ACTUAL BUFFER START
Z2U_IN2:
	EX	DE,HL			; DE := TAIL PTR VAL, HL := ADR OF TAIL PTR
	LD	(HL),E			; SAVE UPDATED TAIL PTR
	INC	HL			; "
	LD	(HL),D			; "
	LD	E,C			; MOVE CHAR TO RETURN TO E
	HB_EI				; INTERRUPTS OK AGAIN
	XOR	A			; SIGNAL SUCCESS
	RET				; AND DONE
;
#ENDIF
;
;
;
Z2U_OUT:
	CALL	Z2U_OST			; CHECK IF OUTPUT REGISTER READY
	JR	Z,Z2U_OUT		; LOOP UNTIL SO
;
	; START BY SELECTING I/O PAGE $FE
	LD	L,$FE			; Z280 UART REGISTERS AT I/O PAGE $FE
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	; WRITE CHAR
	LD	A,E			; BYTE TO A
	OUT	(Z280_UARTXMIT),A	; SEND IT
;	
	; RESTORE I/O PAGE TO $00
	LD	L,$00			; NORMAL I/O REG IS $00
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;	
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
;
;
#IF (INTMODE < 3)
;
Z2U_IST:
;
	; START BY SELECTING I/O PAGE $FE
	LD	L,$FE			; Z280 UART REGISTERS AT I/O PAGE $FE
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	; GET RECEIVE STATUS
	IN	A,(Z280_UARTRCTL)	; GET STATUS
	AND	$10			; ISOLATE CHAR AVAILABLE BIT
;	
	; RESTORE I/O PAGE TO $00
	LD	L,$00			; NORMAL I/O REG IS $00
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	OR	A			; SET FLAGS
	JP	Z,CIO_IDLE		; NOT READY, RETURN VIA IDLE PROCESSING
	RET
;
#ELSE
;
Z2U_IST:
	LD	L,(IY+6)		; GET ADDRESS
	LD	H,(IY+7)		; ... OF RECEIVE BUFFER
	LD	A,(HL)			; BUFFER UTILIZATION COUNT
	OR	A			; SET FLAGS
	JP	Z,CIO_IDLE		; NOT READY, RETURN VIA IDLE PROCESSING
	RET				; DONE
;
#ENDIF
;
;
;
Z2U_OST:
;
	; START BY SELECTING I/O PAGE $FE
	LD	L,$FE			; Z280 UART REGISTERS AT I/O PAGE $FE
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	; GET TRANSMIT STATUS
	IN	A,(Z280_UARTXCTL)	; GET STATUS
;
	; RESTORE I/O PAGE TO $00
	LD	L,$00			; NORMAL I/O REG IS $00
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	; CHECK FOR CHAR AVAILABLE
	AND	$01			; ISOLATE CHAR AVAILABLE BIT
	JP	Z,CIO_IDLE		; NOT READY, RETURN VIA IDLE PROCESSING
	RET				; DONE
;
; AT INITIALIZATION THE SETUP PARAMETER WORD IS TRANSLATED TO THE FORMAT
; REQUIRED BY THE Z2U AND STORED IN A PORT/REGISTER INITIALIZATION TABLE,
; WHICH IS THEN LOADED INTO THE Z2U.
;
; NOTE THAT THERE ARE TWO ENTRY POINTS.	 INITDEV WILL DISABLE/ENABLE INTS
; AND INITDEVX WILL NOT.  THIS IS DONE SO THAT THE PREINIT ROUTINE ABOVE
; CAN AVOID ENABLING/DISABLING INTS.
;
Z2U_INITDEV:
	HB_DI				; DISABLE INTS
	CALL	Z2U_INITDEVX		; DO THE WORK
	HB_EI				; INTS BACK ON
	RET				; DONE
;
Z2U_INITSAFE:
	LD	E,%11000010		; 8N0, DIV 16, NO C/T
	JR	Z2U_INITDEV2		; YES, DO IT
;
Z2U_INITDEVX:
;
	LD	A,D			; HIWORD OF CONFIG
	AND	$1F			; ISOLATE BAUD RATE
	PUSH	AF
;
	LD	DE,Z2UOSC >> 16		; BAUD OSC HI WORD
	LD	HL,Z2UOSC & $FFFF	; BAUD OSC LO WORD
	LD	C,75			; BAUD RATE ENCODE CONSTANT
	CALL	ENCODE			; C = ENCODED OSC
	POP	DE			; D = UART OSC
	JR	NZ,Z2U_INITFAIL		; HANDLE ENCODE FAILURE
	LD	A,C			; TO A
	SUB	D			; DIV W/ SUB OF SQUARES
;
	LD	E,%11000010		; 8N0, DIV 16, NO C/T
	CP	4			; DIV 16?
	JR	Z,Z2U_INITDEV2		; YES, DO IT
	LD	E,%11000100		; 8N0, DIV 32, NO C/T
	CP	5			; DIV 32?
	JR	Z,Z2U_INITDEV2		; YES, DO IT
	LD	E,%11000110		; 8N0, DIV 64, NO C/T
	CP	6			; DIV 64?
	JR	Z,Z2U_INITDEV2		; YES, DO IT
;
Z2U_INITFAIL:
	OR	$FF			; SIGNAL ERROR
	RET				; AND DONE
;
Z2U_INITDEV2:
	; START BY SELECTING I/O PAGE $FE
	LD	L,$FE			; Z280 UART REGISTERS AT I/O PAGE $FE
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
	; SETUP
	;LD	A,%11000010		; 8N0, DIV 16, NO C/T
	LD	A,E			; CONFIG VALUE
	OUT	(Z280_UARTCFG),A	; SET CONFIG REGISTER
	LD	A,%10000000		; ENABLE, NO INTS, 1 STOP BITS
	OUT	(Z280_UARTXCTL),A	; SET CONFIG REGISTER
#IF (INTMODE == 3)
	LD	A,%11000000		; ENABLE W/ INTS
#ELSE
	LD	A,%10000000		; ENABLE, NO INTS
#ENDIF
	OUT	(Z280_UARTRCTL),A	; SET CONFIG REGISTER
;	
	; RESTORE I/O PAGE TO $00
	LD	L,$00			; NORMAL I/O REG IS $00
	LD	C,Z280_IOPR		; REG C POINTS TO I/O PAGE REGISTER
	.DB	$ED,$6E			; LDCTL	(C),HL
;
#IF (INTMODE == 3)
;
	; RESET THE RECEIVE BUFFER
	LD	E,(IY+6)
	LD	D,(IY+7)		; DE := _CNT
	XOR	A			; A := 0
	LD	(DE),A			; _CNT = 0
	INC	DE			; DE := ADR OF _HD
	PUSH	DE			; SAVE IT
	INC	DE
	INC	DE
	INC	DE
	INC	DE			; DE := ADR OF _BUF
	POP	HL			; HL := ADR OF _HD
	LD	(HL),E
	INC	HL
	LD	(HL),D			; _HD := _BUF
	INC	HL
	LD	(HL),E
	INC	HL
	LD	(HL),D			; _TL := _BUF
;
#ENDIF
;
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
;
;
Z2U_QUERY:
	LD	E,(IY+4)		; FIRST CONFIG BYTE TO E
	LD	D,(IY+5)		; SECOND CONFIG BYTE TO D
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
;
;
Z2U_DEVICE:
	LD	D,CIODEV_Z2U		; D := DEVICE TYPE
	LD	E,(IY)			; E := PHYSICAL UNIT
	LD	C,$00			; C := DEVICE TYPE, 0x00 IS RS-232
	LD	H,0			; H := 0, DRIVER HAS NO MODES
	LD	L,(IY+3)		; L := BASE I/O ADDRESS
	XOR	A			; SIGNAL SUCCESS
	RET
;
; Z280 UART DETECTION ROUTINE
; ALWAYS PRESENT, JUST SAY SO.
;
Z2U_DETECT:
	LD	A,Z2U_PRESENT		; PRESENT
	RET
;
;
;
Z2U_PRTCFG:
	; ANNOUNCE PORT
	CALL	NEWLINE			; FORMATTING
	PRTS("Z2U$")			; FORMATTING
	LD	A,(IY)			; DEVICE NUM
	CALL	PRTDECB			; PRINT DEVICE NUM
	PRTS(": IO=0x$")		; FORMATTING
	LD	A,(IY+3)		; GET BASE PORT
	CALL	PRTHEXBYTE		; PRINT BASE PORT
;
	; ALL DONE IF NO Z2U WAS DETECTED
	LD	A,(IY+1)		; GET Z2U TYPE BYTE
	OR	A			; SET FLAGS
	RET	Z			; IF ZERO, NOT PRESENT
;
	PRTS(" MODE=$")			; FORMATTING
	LD	E,(IY+4)		; LOAD CONFIG
	LD	D,(IY+5)		; ... WORD TO DE
	CALL	PS_PRTSC0		; PRINT CONFIG
;
	XOR	A
	RET
;
; WORKING VARIABLES
;
Z2U_DEV	.DB	0			; DEVICE NUM USED DURING INIT
;
#IF (INTMODE < 3)
;
Z2U0_RCVBUF	.EQU	0
;
#ELSE
;
; RECEIVE BUFFERS
;
Z2U0_RCVBUF:
Z2U0_BUFCNT	.DB	0		; CHARACTERS IN RING BUFFER
Z2U0_HD		.DW	Z2U0_BUF	; BUFFER HEAD POINTER
Z2U0_TL		.DW	Z2U0_BUF	; BUFFER TAIL POINTER
Z2U0_BUF	.FILL	32,0		; RECEIVE RING BUFFER
Z2U0_BUFEND	.EQU	$		; END OF BUFFER
Z2U0_BUFSZ	.EQU	$ - Z2U0_BUF	; SIZE OF RING BUFFER
;
#ENDIF
;
; Z2U PORT TABLE
;
Z2U_CFG:
;
Z2U0_CFG:
	; Z2U CONFIG
	.DB	0			; DEVICE NUMBER (SET DURING INIT)
	.DB	0			; Z280 UART TYPE (SET DURING INIT)
	.DB	0			; MODULE ID
	.DB	Z2U0BASE		; BASE PORT
	.DW	Z2U0CFG			; LINE CONFIGURATION
	.DW	Z2U0_RCVBUF		; POINTER TO RCV BUFFER STRUCT
;
Z2U_CFGSIZ	.EQU	$ - Z2U_CFG	; SIZE OF ONE CFG TABLE ENTRY
;
Z2U_CFGCNT	.EQU	($ - Z2U_CFG) / Z2U_CFGSIZ
