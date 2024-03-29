;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; tu58v3.asm
;
; DEC TU-58 tape system emulator
;  Created: 06/12/2019
;   Author: Joseph C. Lang
;   Copyright (C) 2019
;   Released to the public domain
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Storage is on a single CF card
; This code is for the version 3 board
; Version 3 changed to the ATmega32A processor
; it has a parallel interface to the CF card
; Eliminating the SPI interface used in V1 and V2
; Version 3 also has config jumpers to select baud rate
;
; AVR Fuses: L=0xE0 h=0xB9
;
        .DSEG
;
;SRAM locations:
;
	.ORG $100	;skip past register space
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;CF card read/write buffer (512 bytes)
;the buffer is loaded/unloaded 128 bytes at a time (RSP protocol)
;the var BUFSEG selects the 128 byte area currently used
;
BUFFER:	.BYTE 512	;cf card read/write buffer
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;command/response packet storage
;some addresses are duplicated
;since command and response use
;some fields differently
;the values are in the same order as
;defined in the RSP packet
;
PK_FLAG:	.BYTE  1      ;flag
PK_CMDCT:	.BYTE  1      ;count
PK_OPCD:	.BYTE  1      ;op code
;
PK_MOD:			      ;modifyer
PK_SUCC:	.BYTE  1      ;success code
;
PK_UNIT:	.BYTE  1      ;unit
PK_SWIT:	.BYTE  1      ;switches
PK_SEQL:	.BYTE  1      ;sequence low (unused)
PK_SEQH:	.BYTE  1      ;sequence hi (unused)
PK_CNTL:	.BYTE  1      ;byte count low
PK_CNTH:	.BYTE  1      ;byte count hi
;
PK_BLKL:		      ;block number low
PK_SUMSL:	.BYTE  1      ;summary status low
;
PK_BLKH:		      ;block number high
PK_SUMSH:	.BYTE  1      ;summary status hi
;
PK_CHKL:	.BYTE  1      ;packet check low
PK_CHKH:	.BYTE  1      ;packet check high
;
;data packet storage
BF_FLAG:	.BYTE  1      ;response type
BF_DATCT:	.BYTE  1      ;response byte count
BF_DATA:	.BYTE  128    ;response data
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;SRAM variables
CUR_BL:		.BYTE  1      ;current block low
CUR_BH:		.BYTE  1      ;current block high
BYT_DONL:	.BYTE  1      ;transfered count
BYT_DONH:	.BYTE  1      ;transfered count
SUCCES:		.BYTE  2      ;success code
SUMST:		.BYTE  1      ;summary status
FL_BOOT:	.BYTE  1      ;boot flag
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;register variables
.def BUFSEG	= r1	;current buffer segment
.def CHKLO	= r8	;calculated checksum low
.def CHKHI	= r9	;calculated checksum hi
.def FL_GO	= r10	;flag GO
.def FL_XOFF	= r11	;xoff flag
.def FL_TOG	= r12	;checksum byte toggle
;r16 accumulator
;r17 temp value
.def STATEL	= r19	;current state low
.def STATEH	= r20	;current state high
.def COUNT	= r21	;counter
.def BYTCNTL	= r22   ;byte counter low (to go)
.def BYTCNTH	= r23   ;byte counter hi
; r26,r27 rx data pointer
; r28,r29 sram pointer
; r30,r31 buffer pointer
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;packet flag bytes
.equ DATACH	= 1	;paket flag=data
.equ CMDCH	= 2	;packet flag=command
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;character constants
.equ INITCH	= 4	;init character
.equ BOOTCH	= 8	;boot character
.equ CONTIN	= $10	;xon continue character
.equ XOFFCH	= $13	;xoff stop character
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;port A:
; bidirectional data bus connection to
; CF card
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;port B pins:
;outputs to control CF card
;0 A0
;1 A1
;2 A2
;3 rd-
;4 wr-
;5 unused
;6 cs-
;7 always 1 (CS3XX- on CF card not used)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;port D pins: (inputs)
;
;0 USART RX
;1 USART TX
;interface to CF card (port D input): 
;2 irq
;3 drq
;4 cfg 0
;5 cfg 1
;6 cfg 2
;7 unused
;
; config jumpers
; U unused
; I in
; O out
;
;	0 1 2   BAUD RATE
;	U O O	9600
;	U I O	19200
;	U O I	38400
;	U I I	115200
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;port C: (outputs)
;
;0 cf ack- (unused always hi)
;1 unused
;2-5 JTAG
;6 unused
;7 cf rst-
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;bit patterns for CF card control on port B:
;  wr- and rd- set high (inactive) for later strobe
;  sel- low (active)
;  sbi cbi used to assert and negate read- and write-
;
;   7 6  5  4   3   2  1  0
;   1 CS 1  wr  rd  A2 A1 A0 
;
.equ CF_data	= $B8	;cf card data register
.equ CF_feat	= $B9	;cf card feature register
.equ CF_err		= $B9	;cf card error register
.equ CF_count	= $BA	;cf sector count
.equ CF_lba0	= $BB	;cf lbn bits 0-7
.equ CF_lba1	= $BC	;cf lbn bits 8-15
.equ CF_lba2	= $BD	;cf lbn bits 16-24
.equ CF_lba3	= $BE	;cf lbn/drive 
.equ CF_cmd		= $BF	;cf command register
.equ CF_stat	= $BF	;cf status register
.equ CF_nsel	= $40	;cf card select bit
;
;individual port B bits:
;for use with cbi sbi instructions
.equ CF_wr		= 4	;write- bit
.equ CF_rd		= 3	;read- bit
.equ CF_csel	= 6	;cs0- bit
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;CF card status register bits
.equ CF_busy	= 7	;CF busy bit
.equ CF_drq		= 3	;CF data request
.equ CF_errb	= 0	;error bit
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;CF card commands/bits
.equ CF_8bit	= 1	;set 8bit feature
.equ CF_drv0	= $e0	;drive 0+lba mode
.equ CF_drv1	= $f0	;drive 1+lba mode
.equ CF_dread	= $20	;read command
.equ CF_dwrite	= $30	;write command
.equ CF_sfeat	= $ef	;set features command
;
;
        .CSEG
        .ORG 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;power on reset
;reset/interrupt vectors
;most are not used
	jmp	tugo	;1 reset
	jmp	dummy	;2 int0
	jmp	dummy	;3 int1
	jmp	dummy	;4 int2
	jmp	dummy	;5 t2cmp
	jmp	dummy	;6 t2ovf
	jmp	dummy	;7 t1cap
	jmp	dummy	;8 t1cmpa
	jmp	dummy	;9 t1cmpb
	jmp	dummy	;10 t1ovf
	jmp	dummy	;11 t0cmp
	jmp	dummy	;12 t0ovf
	jmp	dummy	;13 spi
	jmp	rx_in	;14 rxc
	jmp	dummy	;15 udre
	jmp	dummy	;16 txc
	jmp	dummy	;17 adc
	jmp	dummy	;18 eerdy
	jmp	dummy	;19 anacmp
	jmp	dummy	;20 twi
	jmp	dummy	;21 spmrdy

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;fatal IRQ error
;unexpected IRQ lands here
;
dummy:	cli		;turn off IRQ
here:	jmp	here	;fatal error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;Cold start
;
tugo:
	cli
	ldi r16,low(RAMEND)	;set stack
	out SPL,r16
	ldi r16,high(RAMEND)
	out SPH,r16
;
;set protocol state to idle
	ldi STATEL,low(st_idle)
	ldi STATEH,high(st_idle)
;
;initialize system
	call hard_init		;init hardware
	ldi r16,0x00
	sts pk_swit,r16		;init switch
	call soft_init		;init software
	sei			;allow irq
;
	;send init characters
	rjmp send_init		;spew init characters

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;USART character in interrupt
;
rx_in:
	push r16	;save register
	in r16,SREG	;get sreg
	push r16	;save SREG
;
;if framing error goto init_loop
;else fall through to protocol handler
;
	in r16,UCSRA	;get status
	sbrc r16,FE		;skip next if not framing error
	rjmp rx_in01	;jump to break handler

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;get RX chararacter
;goto protocol handler
;
	in r16,UDR	;get serial data
;
;jump to current state handler
	push STATEL	;push current state
	push STATEH	;on the stack
	ret		;return to it

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; got framing error so restart protocol
;
rx_in01:
	in r16,UDR	;get serial data
	ldi COUNT,5	;retry count
	jmp init_loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;common handler return
;
com_rtn:
	pop r16		;recover flags
	out SREG,r16
	pop r16		;recover r16
	reti

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;boot handler
;save unit number
;read block zero
;send block to host (no RSP)
;set state to idle
;goto idle loop
;
st_boot:
	sts PK_UNIT,r16		;set unit
	clr r16
	sts CUR_BL,r16		;clear block number
	sts CUR_BH,r16
	mov FL_XOFF,r16		;clear xoff flag
	call cf_read		;read block
	ldi r28,low(buffer)	;point to buffer
	ldi r29,high(buffer)
	ldi r17,128		;loop count
st_bo1:
	ld r16,Y+		;get byte
	call out_chr		;send it
	ld r16,Y+		;repeat
	call out_chr
	ld r16,Y+
	call out_chr
	ld r16,Y+
	call out_chr
	dec r17
	brne st_bo1
;
;set state back to idle
	ldi STATEL,low(st_idle)	;idle is next
	ldi STATEH,high(st_idle)
	rjmp idle_loop		;done
;
;set state to st_boot
boot_nxt:
	ldi STATEL,low(st_boot)	;boot is next
	ldi STATEH,high(st_boot)
	rjmp com_rtn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;state: idle
;decode character
;handle init,boot,xoff,contin
;if cmd or data set buffer pointer
;and next state=count
;
st_idle:
	cpi r16,INITCH	;init?
	breq to_goti
	cpi r16,BOOTCH	;boot?
	breq boot_nxt
	cpi r16,XOFFCH	;xoff
	brne st_id01
	clr FL_XOFF
	com FL_XOFF
;
;return with same state
	rjmp com_rtn
;
st_id01:
	cpi r16,CONTIN	;continue?
	brne st_id02
	clr FL_XOFF	;then clear flag
;
;return with same state
	rjmp com_rtn
;
;must be data, cmd or error;
st_id02:
	tst FL_GO		;already got a packet?
	brne st_id04		;then error restart
	sts PK_FLAG,r16		;save packet type
	mov CHKLO,r16		;init chksum
	cpi r16,CMDCH		;is packet comand?
	brne st_id03
	ldi r26,low(PK_OPCD)	;point to command buffer
	ldi r27,high(PK_OPCD)
	rjmp st_id05
;
st_id03:
	cpi r16,DATACH		;is packet data?
	brne st_id04		;fatal error
	ldi r26,low(BF_DATA)	;point to data buffer
	ldi r27,high(BF_DATA)
	rjmp st_id05
;
;protocol error restart
st_id04:
	rjmp pro_err
;
;return with new state
st_id05:
	ldi STATEL,low(st_count)	;count is next
	ldi STATEH,high(st_count)
	rjmp com_rtn
;
;branch extender
to_goti:
	rjmp got_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;state: count
;save packet count
;init checksum and FL_TOG
;set next state=data in
;
st_count:
	sts PK_CMDCT,r16	;save count character
	mov COUNT,r16		;save for count down
	mov CHKHI,r16		;preset checksum
	cpi r16,$81		;count too big?
	brcc st_id04		;
	clr FL_TOG
	com FL_TOG		;set toggle
	ldi STATEL,low(st_data)	;data is next state
	ldi STATEH,high(st_data)
	rjmp com_rtn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;state: data in
;save byte
;update checksum
;dec count
;if count=0 next state=checksum1
;
st_data:
	st X+,r16		;save data character
	call add2chk
	dec	COUNT
	brne st_dat1		;exit in same state
	ldi STATEL,low(st_chk1)	;checksum is next state
	ldi STATEH,high(st_chk1)
st_dat1:
	rjmp com_rtn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;state: checksum1
;if chksum error goto pro_err
;next state=checksum2
;
st_chk1:
	cp r16,CHKLO		;checksum match?
	breq st_cknx		;then check next
	rjmp pro_err		;else fatal error
st_cknx:
	ldi STATEL,low(st_chk2)	;checksum 2 is next state
	ldi STATEH,high(st_chk2)
	rjmp com_rtn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;state: checksum2
;if chksum error goto protocol error (pro_err)
;next state=idle
;set fl_go
;
st_chk2:
	cp r16,CHKHI		;checksum match?
	breq st_ckok		;then set go flag
	rjmp pro_err		;else fatal error
st_ckok:
	clr FL_GO
	com FL_GO		;set go flag
	ldi STATEL,low(st_idle)	;set next state
	ldi STATEH,high(st_idle)
	rjmp com_rtn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;got init character
;
got_init:
	ldi r16,low(RAMEND)	;reset stack
	out SPL,r16
	ldi r16,high(RAMEND)
	out SPH,r16
	call soft_init		;reset state
	call send_cont		;send continue
	rjmp idle_loop		;goto idle loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;init loop
;mask off serial irq
;loop: get char
;if not init goto loop
;reset protocol
;fall through to idle loop
;
init_loop:
	cli			;turn off irq
	ldi r16,low(RAMEND)	;reset stack
	out SPL,r16
	ldi r16,high(RAMEND)
	out SPH,r16
init_lp1:
	in r16,UCSRA		;get UART status
	sbrs r16,RXC		;rx data rdy?
	rjmp init_lp1		;loop if not
	dec COUNT		;too many tries?
	brne init_lp2
	rjmp pro_err
init_lp2:
	in r16,UDR		;get char
	cpi r16,INITCH		;init?
	brne init_lp1		;loop if not
	call soft_init		;reset protocol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;idle loop
;RSP commands return here when done
; reset stack
; reset flags
; enable serial irq
;
idle_loop:
;
;reset stack
	cli
	ldi r16,low(RAMEND)
	out SPL,r16
	ldi r16,high(RAMEND)
	out SPH,r16
;
	clr r16
	sts PK_SWIT,r16		;clear switch
	mov FL_GO,r16		;clear go
	sts succes,r16		;clear error
	sts succes+1,r16
	sts byt_donl,r16	;clear count
	sts byt_donh,r16
	sei			;allow irq
;
;goto command loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;command loop
;loop till fl_go sets
;if packet!=cmd goto pro_err
;jump to command handler
;
cmd_loop:
;	call switches		;poll front panel
	tst FL_GO		;valid packet recieved?
	breq cmd_loop	;loop if not
	lds r16,PK_FLAG
	cpi r16,CMDCH		;expecting command
	breq cmd_l01
	rjmp pro_err		;fatal error if not cmd
;
cmd_l01:
	lds r16,PK_OPCD		;get cmd byte
	cpi r16,$b		;in range?
	brlo cmd_l02
	ldi r16,$d0		;error bad opcode
	rjmp set_succ
;
cmd_l02:
	lsl r16			;mult by size of entry
	andi r16,$1e	;mask off unused bits
	ldi r17,low(cmd_tbl)
	add r16,r17		;index into table
	push r16		;push offset low
	ldi r16,high(cmd_tbl)
	brcc cmd_l03
	inc r16		;carry into hi byte
cmd_l03:
	push r16		;push offset high
	ret			;go to routine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;op code jump table
;
cmd_tbl:
	jmp op_noop
	jmp op_init
	jmp op_read
	jmp op_write
	jmp op_noop
	jmp op_pos 
	jmp op_noop
	jmp op_diag
	jmp op_stat
	jmp op_noop
	jmp op_noop
	jmp op_noop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;soft init
;reset state and variables
;
soft_init:
	cli
	lds r16,PK_SWIT
	andi r16,0x08		;leave mrsp bit alone
	sts PK_SWIT,r16
	clr FL_XOFF
;
;set next state to idle
clr_state:
	ldi STATEL,low(st_idle)
	ldi STATEH,high(st_idle)
	sei
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;hardware init
;
hard_init:
;
;set up USART
;8 bit, 1 stop, no parity
;
;setup port D
	ldi r17,0xff	;set bits hi
	out PORTD,r17	;turn on pull ups
	ldi r17,0x00
	out DDRD,r17	;ports to input
;
;select baud rate
	in r16,PIND		;read config
	andi r16,0x60	;mask to config bits
;
	cpi r16,0x00	;115k
	brne chk38k
	ldi r17,0x00
	ldi r16,0x05
	jmp set_br
;
chk38k:
	cpi r16,0x20	;38.4k
	brne chk19k
	ldi r17,0x00
	ldi r16,0x11
	jmp set_br
;
chk19k:
	cpi r16,0x40	;19.2k
	brne set9600
	ldi r17,0x00
	ldi r16,0x23
	jmp set_br
;
set9600:
	ldi r17,0x00	;9600
	ldi r16,0x47	;9600
;
set_br:
	out UBRRH,r17		;set baud rate
	out UBRRL,r16
;
;enable USART
; 8 bits 1 stop no parity
	ldi r16,(1<<RXEN)|(1<<TXEN)|(1<<RXCIE)
	out UCSRB,r16		;set uart enable
	ldi r16,(1<<URSEL|3<<UCSZ0)
	out UCSRC,r16		;set word length
;
;init port B
	ldi r17,0xff		;outputs
	out PORTB,r17		;set bits hi
	out DDRB,r17		;set port to out
;
;init port C
	ldi r17,0x01		;bit 0 hi
	out PORTC,r17
	ldi R17,0x81		;set direction
	out DDRC,r17
;
;CF reset is low so kill some time
	nop
	nop
	nop
	nop
	nop
;
;set reset hi kill more time
	sbi PORTC,7
	nop
	nop
	nop
	nop
	nop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;initalize CF card
;
CF_init:
	call	not_bsy		;wait for CF ready
;
;select CF drive 0
	ldi	r17,CF_lba3	;select drive/lba
	ldi	r16,CF_drv0	;lba+drive 0
	call put_reg		;write register
;
;set 8 bit mode
	ldi	r17,CF_feat	;select feature
	ldi	r16,CF_8bit	;8 bit mode
	call put_reg		;write register
;
	ldi	r17,CF_cmd	;select cmd register
	ldi	r16,CF_sfeat	;set features
	call put_reg		;write register
;
	call not_bsy		;read status
	sbi	PORTB,CF_csel	;deselect CF card
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;wait for CF card not busy
;return status in r16
;
not_bsy:
	ldi	r17,CF_stat	;point to status reg
not_by1:
	call	get_reg		;get status
	sbrc	r16,CF_busy	;mask to busy bit
	rjmp	not_by1		;loop if busy
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;send byte to CF card
; r16 data to send (destroyed)
; r17 CF register (preserved)
; output address bits (r17)
; output data bits (r16)
; assert write,delay,negate write
;
put_reg:
	out PORTB,r17		;select CF register
	out PORTA,r16		;set data out
	ldi r16,0xff		;port A to output
	out DDRA,r16		;set direction=out
	nop					;settle
;
	cbi PORTB,CF_wr		;assert write-
	nop
	nop
	nop
	nop
	sbi PORTB,CF_wr		;remove write
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;get byte from CF card
; r17 CF register (preserved)
; r16 returned data
; output address bits (r17)
; assert read,delay,negate read
; input data (r16)
;
get_reg:
	out PORTB,r17		;set CF register address
	nop
	nop			;settle address
;
;set port A to input
	ldi r16,0x00
	out DDRA,r16	;set port direction=in
;
;load CF data
	cbi PORTB,CF_rd		;assert read-
	nop
	nop
	nop
	nop			;access delay
	in r16,PINA		;read data
	sbi PORTB,CF_rd		;remove read
;
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;add r16 to checksum
;FL_TOG is hi/low byte
;flip FL_TOG
;
add2chk:
	clc
	tst FL_TOG	;test hi/low
	breq add_hi
add_lo:
	adc CHKLO,r16	;add to low
	brcc add_ex	;done if no carry
	ldi r16,0	;add 0+carry to hi
add_hi:
	adc CHKHI,r16	;add to high
	brcc add_ex	;done if no carry
	ldi r16,0	;add 0+carry to lo
	rjmp add_lo
add_ex:
	com FL_TOG	;flip flag for next
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;send character in r16 to serial port
;wait for fl_xoff to clear
;then send polled IO
;
out_chr:
	push r16	;save character
outch1:
	tst FL_XOFF	;wait for continue
	brne outch1
;
	in r16,UCSRA	;get tx status
	sbrs r16,UDRE	;skip if tx empty
	rjmp outch1	;loop till tx ready
	pop r16		;recover character
	out UDR,r16	;send it
	lds r16,PK_SWIT	;test for slow mode
	andi r16,0x08	;MRSP mode
	breq outch2
	clr FL_XOFF
	com FL_XOFF	;then set XOFF flag
outch2:
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;protocol error
;reset protocol
;fall through to send init
;
pro_err:
;
;reset stack
	cli 
	ldi r16,low(RAMEND)	;set stack
	out SPL,r16
	ldi r16,high(RAMEND)
	out SPH,r16
;
;reset state to idle
	ldi STATEL,low(st_idle)	;set state
	ldi STATEH,high(st_idle)
;
;reset protocol variables
	call soft_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;send init (exit via interrupt)
;send init char
;loop forever
;
send_init:
	ldi r16,INITCH
	call out_chr	;send character
	ldi r17,5	;delay a bit...
	call delayl
	rjmp  send_init	;loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;send continue and return
;
send_cont:
	ldi r16,CONTIN
	rjmp  out_chr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;send data packet
;set pointer Y to data
;set packet type=data
;send packet
;
snd_data:
	ldi r28,low(BF_FLAG)	;point to data buffer
	ldi r29,high(BF_FLAG)
	ldi r16,DATACH		;set type=data
	st Y,r16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;send packet
; Y= pointer to packet header
;
snd_rsp:
	ldd COUNT,Y+1	;get packet count
	inc COUNT	;count+2
	inc COUNT
;
;reset checksum state
	clr CHKLO	;clear checksum
	clr CHKHI
	clr FL_TOG
	com FL_TOG	;preset toggle
;
snd_r01:
	ld r16,Y	;get char
	call add2chk	;add to checksum
	ld r16,Y+	;get again
	call out_chr	;send it
	dec COUNT
	brne snd_r01	;loop till done
	mov r16,CHKLO	;get check low
	call snd_cksum	;send it
	mov r16,CHKHI	;get check hi
	call snd_cksum
;
	ldi r16,0x50	;short delay
	call delay
	ret
	;
snd_cksum:
	push r16
	ldi r16,0x50	;delay a bit...
	call delay
	pop r16
	call out_chr	;send character
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; really short delay
; about 3us.
kil_tim:
	call kil_tim2
	call kil_tim2
;
kil_tim2:
	nop
	nop
	nop
	nop
	nop
	nop
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;short delay
; aprox 15 us per loop
; r16 = loop count
;
delay:
	call kil_tim
	call kil_tim
	call kil_tim
	call kil_tim
	dec r16
	brne delay
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;long delay
; aprox 1.5 ms per loop
;r17 = loop count
;
delayl:
	ldi r16,$60
	call delay
	dec r17
	brne delayl
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;calculate remaining bytes
; carry set=last packet
; R16=count for this packet
;
; if count >128 return cc and R16=128 
; if count=128 return cs and R16=128
; else (0...127) return cs and R16=remaining count
;
remain:
	mov r16,BYTCNTL		;save in case of underflow
	subi BYTCNTL,128	;subtract packet size
	sbci BYTCNTH,0
	brcs rem_ufl		;less than 128 to go?
	mov r16,BYTCNTL		;get low count
	or r16,BYTCNTH		;or in hi count
	ldi r16,128		;then send 128 bytes
	breq rem_ufl	;exactly 128 to go?
;
;return with carry clear and r16=128
;full size packet and more to go
	ret
;
;return with carry set and r16=bytes to go
;packet size 1...128 and last one 
rem_ufl:
	sec		;set carry (last flag)
	ret			;else send BYTCNTL bytes

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;add transfer count to bytes done
;r16=transfer count
;
add_don:
	lds r17,BYT_DONL
	add r17,r16		;add transfer to bytes done
	sts BYT_DONL,r17
	brcc adddon1		;carry?
	lds r17,BYT_DONH
	inc r17			;inc hi byte
	sts BYT_DONH,r17
adddon1:
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;set starting block
;reset segment number to zero
;clear bytes done
;set bytes to go
;
set_blk:
	clr r16
	mov BUFSEG,r16		;clear segment
	sts BYT_DONL,r16	;clear bytes done
	sts BYT_DONH,r16
;
	lds r16,PK_CNTL
	mov BYTCNTL,r16		;set bytes to go
	lds r16,PK_CNTH
	mov BYTCNTH,r16
;
;special addressing mode goes here (to do)
	lds r16,PK_BLKL		;set block number
	sts CUR_BL,r16
	lds r16,PK_BLKH
	sts CUR_BH,r16
	ret
;
;test for valid unit number
	lds r16,PK_UNIT		;get unit number
	andi r16,0xfe		;mask to 0,1
	breq set_bl1
	ldi r16,0xf8
	jmp set_succ		;return with error
;
set_bl1:
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;cf card read
;setup task file
;issue read command
;wait for drq or not busy
;move data to buffer
;wait for not busy
;test error bit
;
cf_read:
	call set_task		;set task registers
;
;block interrupt while doing CF io
	cli
	ldi r17,CF_cmd		;point to cmd reg
	ldi r16,CF_dread
	call put_reg		;send read command
;
;wait for drq or not busy
rd_wait:
	ldi r17,CF_stat		;point to status reg
	call get_reg		;get status
	sbrc r16,CF_drq		;test DRQ bit
	rjmp rd_drq		;drq set?
	sbrc r16,CF_busy	;test BUSY bit
	rjmp rd_wait		;busy set?
;
;busy cleared so check error
rd_done:
	sbi PORTB,CF_csel	;deselect CF card
	sei			;irq ok now
	sbrs r16,CF_errb	;error set?
	ret
	ldi r16,$ef		;data error
	rjmp set_succ
;
;move data to buffer
;4 bytes per loop
rd_drq:
	ldi COUNT,128		;loop counter
	ldi r17,CF_data		;point to data reg
	ldi r28,low(buffer)	;point to CF buffer
	ldi r29,high(buffer)
;
cf_rdlp:
	call get_reg		;get byte
	st  Y+,r16		;save byte
	call get_reg		;repeat
	st  Y+,r16
	call get_reg	
	st  Y+,r16
	call get_reg	
	st  Y+,r16
	dec COUNT
	brne cf_rdlp		;loop till done
	call not_bsy		;wait for not busy
	rjmp rd_done		;check status

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;cf card write
;
cf_write:
	call set_task		;set task registers
;
;block interrupts while doing CF I/O
	cli
	ldi r17,CF_cmd		;point to cmd reg
	ldi r16,CF_dwrite
	call put_reg		;issue write cmd
;
;wait for drq or not busy
wr_wait:
	ldi r17,CF_stat		;point to status reg
	call get_reg		;get status
	sbrc r16,CF_drq
	rjmp wr_drq		;drq set?
	sbrc r16,CF_busy
	rjmp wr_wait		;loop if busy set
;
;error check
wr_eck:
	sbi PORTB,CF_csel	;deselect CF card
	sei			;irq ok now
	sbrs r16,CF_errb	;error set?
	ret			;good exit
	ldi r16,$ef		;data error
	rjmp set_succ		;bad exit
;
;move data to CF card (4 bytes per loop)
wr_drq:
	ldi COUNT,128		;loop counter
	ldi r17,CF_data		;point to data reg
	ldi r28,low(buffer)	;point to CF buffer
	ldi r29,high(buffer)
;
cf_wrlp:
	ld  r16,Y+		;get byte
	call put_reg		;put byte
	ld  r16,Y+		;repeat
	call put_reg
	ld  r16,Y+
	call put_reg
	ld  r16,Y+
	call put_reg
	dec COUNT
	brne cf_wrlp
;
;wait for not busy
	call not_bsy
	rjmp wr_eck

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;set task file
;wait for not busy
;load CF  card registers
;
set_task:
	call not_bsy		;wait for CF ready
;
	ldi r17,CF_count	;set sector count
	ldi r16,1
	call put_reg
;
	ldi r17,CF_lba0		;set lba0 
	lds r16,CUR_BL
	call put_reg
;
	ldi r17,CF_lba1		;set lba1
	lds r16,CUR_BH
	call put_reg
;
	ldi r17,CF_lba2		;set lba2
	lds r16,PK_UNIT
	call put_reg

	ldi r17,CF_lba3		;set lba3 
	ldi r16,CF_drv0
	call put_reg
;
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;zero out buffer
;
zero_buf:
	ldi r28,low(buffer)	;point to CF buffer
	ldi r29,high(buffer)
	ldi r16,0		;fill byte
	ldi r17,0		;count
zero_b0:
	st Y+,r16		;clear a word
	st Y+,r16
	dec r17			;dec word count
	brne zero_b0		;loop till done
	ret
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;copy from buffer to packet
;copy 128 bytes from CF buffer 
;to packet buffer
;
buf2pak:
	call buf2ptr	;setup pointers
	ldi r17,128	;size of move
buf2p1:
	ld r16,Z+	;copy byte
	st Y+,r16
	dec r17
	brne buf2p1	;loop till done
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;setup pointers for block move
;Y=data packet pointer
;Z=buffer pointer
;
buf2ptr:
	ldi r28,low(bf_data)	;point to packet
	ldi r29,high(bf_data)
	ldi r30,low(buffer)	;point to CF buffer
	ldi r31,high(buffer)
	mov r16,BUFSEG		;get buffer segment
buf21:
	tst r16
	breq buf22
	dec r16			;dec segment
	ldi r17,128		;add 128 to pointer
	add r30,r17
	brcc buf21		;no carry?
	inc r31			;inc hi address
	rjmp buf21		;and loop
;
buf22:
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;copy from packet to buffer
;copy 128 bytes from packet buffer
;to CF buffer
;
pak2buf:
	call buf2ptr	;setup pointers
	ldi r17,128	;count
pak2b1:
	ld r16,Y+	;move byte
	st Z+,r16
	dec r17		;dec count
	brne pak2b1	;loop
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;get data packet for write
;
get_wpkt:
	clr FL_GO
	call send_cont	;prompt host for data
gp_wait:
	tst fl_go
	breq gp_wait	;loop till go sets
	lds r17,PK_FLAG
	cpi r17,DATACH	;type=data?
	breq gp_exit
	rjmp pro_err	;fatal error
gp_exit:
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;command processors
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;command: no-operation
;set up response packet and send
;goto idle loop
;
op_noop:
	ldi r16,$02
	sts PK_FLAG,r16		;set type
;
	ldi r16,$0a
	sts PK_CMDCT,r16	;set count
;
	ldi r16,$40
	sts PK_OPCD,r16		;set response code
;
	lds r16,SUCCES
	sts PK_SUCC,r16		;set status
;
	clr r16
	sts PK_SUMSL,r16	;set summary status
	lds r16,SUMST
	sts PK_SUMSH,r16
;
	lds r16,byt_donl
	sts PK_CNTL,r16		;set bytes done
	lds r16,byt_donh
	sts PK_CNTH,r16
;
	ldi r17,5
	call delayl		;kill time
;
	ldi r28,low(PK_FLAG)	;point to packet
	ldi r29,high(PK_FLAG)
	call snd_rsp		;send it
	rjmp idle_loop		;done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;set success (error) code
;
set_succ:
	sts SUCCES,r16		;set success code
	ldi r16,0x80
	sts SUMST,r16		;set error bit
;
	ldi r16,low(RAMEND)	;reset stack
	out SPL,r16
	ldi r16,high(RAMEND)
	out SPH,r16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;command: init
;
op_init:
	call clr_state
	rjmp op_noop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;command: read block(s)
;
op_read:
	call set_blk	;set pointers
	rjmp rd_lop2	;goto read loop
rd_lop1:
	ldi r17,4
	inc BUFSEG	;point to next 
	cp BUFSEG,r17	;last segment?
	brne rd_loop	;skip increment
	clr BUFSEG	;zero segment
;
	lds r17,CUR_BL
	inc r17		;inc block number
	sts CUR_BL,r17
;
	brcc rd_lop2
;
	lds r17,CUR_BH
	inc r17		;inc hi byte
	sts CUR_BH,r17
rd_lop2:
	call cf_read	;read block
rd_loop:
	call buf2pak	;move data to packet
	call remain	;calc remaining bytes
	brcs rd_fin	;lt or eq to 128 to go?
;
;more packets to go
	sts BF_DATCT,r16	;set packet size
	call add_don	;add to bytes sent
	call snd_data	;send block
	rjmp rd_lop1	;loop for more
;
;last packet
rd_fin:
	cpi r16,0	;zero to go?
	breq rd_fin1
	sts BF_DATCT,r16	;set packet size
	call add_don	;add to bytes sent
	call snd_data	;send block 
;
rd_fin1:
	rjmp op_noop	;send end packet

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;command: write block(s)
;
op_write:
	call set_blk	;set starting block
	call zero_buf	;zero data
	rjmp op_wri1
;
;inc segment,block and write to CF
;if it advances to next block
op_wnxt:
	ldi r17,4
	inc BUFSEG	;point to next 
	cp BUFSEG,r17	;last segment?
	brne op_wri1	;skip writeback
	call cf_write	;write to CF card
	call zero_buf	;clear buffer
	clr BUFSEG	;zero segment
;
	lds r17,CUR_BL
	inc r17	;inc block number
	sts CUR_BL,r17
	brcc op_wri1
	lds r17,CUR_BH
	inc r17		;inc block number
	sts CUR_BH,r17	
;
;ask for data
op_wri1:
;
;wait for data packet
	call get_wpkt	;get data from host
	call pak2buf	;copy data to CF buffer
	lds r16,PK_CMDCT
	call add_don	;add bytes to done
	call remain	;calc bytes to go
	brcc op_wnxt	;>128 so loop for more
;
;last packet in buffer so write it
wr_done:
	call cf_write	;flush the buffer
	rjmp op_noop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;command: position tape 
;not much to do in an emulator
;set block number
;goto no op
;
op_pos:
	call set_blk
	rjmp op_noop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;command: diagnostics
;move along nothing to see here
;goto no op 
;
op_diag:
	rjmp op_noop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;command: get status
;goto no op
;
op_stat:
	rjmp op_noop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;end
