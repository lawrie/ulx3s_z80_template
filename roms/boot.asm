	ORG 0000h	; start at 0x0000

RST00:  di		; disable interrupts
	jp bootstrap
	nop
	nop
	nop
	nop		; pad to address 0x0008

RST08:	jp TX
	nop
	nop
	nop
	nop
	nop

RST10:	jp getc
	nop
	nop
	nop
	nop
	nop

RST18:	jp pollc
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

RST38:	reti

TX:	push af
;txbusy:	in a,($80)	; read serial status
;	bit 1,a		; check status bit 1
;	jr z, txbusy	; loop if zero (serial is busy)
	pop af
	out ($81), a	; transmit the character
	ret

bootstrap:  
	ld hl,$FFF9	; stack initialization
	ld sp,hl

	ld a, $96	; Initialize ACIA
	out ($80),a

	di

	jp start		


;@ Follows additional functions to interact with rc2014 hardware
;@
;@---------------------------------------------------------------------
;@ getc
;@
;@  wait for system UART and return the received character in HL
;@
;@---------------------------------------------------------------------
getc:
	push af
waitch:     in a, ($80)
	bit 0, a
	jr z, waitch
	in a, ($81)
	ld h, 0
	ld l, a
	pop af
	ret


;@---------------------------------------------------------------------
;@ putc
;@
;@ output the byte in register L to system UART
;@
;@---------------------------------------------------------------------
putc:
	ld a, l
	rst $08
	ret


;@---------------------------------------------------------------------
;@ pollc
;@
;@ polls the uart receive buffer status and
;@ returns the result in the register L:
;@   L=0 : no data available
;@   L=1 : data available
;@
;@---------------------------------------------------------------------
pollc:
	ld l, 0
	in a, ($80)
	bit 0, a
	ret z
	ld l, 1
	ret


;@---------------------------------------------------------------------
;@ inp
;@
;@ reads a byte from port l and returns the results in l
;@
;@---------------------------------------------------------------------
inp:
	push bc
	ld c, l
	in b, (c)
	ld l, b
	pop bc
	ret


;@---------------------------------------------------------------------
;@ inp
;@
;@ writes register l to port h
;@
;@---------------------------------------------------------------------
outp:
	push bc
	ld c, h
	ld b, l
	out (c), b
	pop bc
	ret

start:
	;ld l,'H'
	;call putc
	ld hl, msg
	call print_string
	ld bc, $0FFF
	call delay
	;ld a, 'H'
	;rst $08
	jp start

print_string:
        ld a, (hl)
        cp 255
        ret z
        inc hl
        rst $08
        jp print_string

delay:
	dec bc
	ld a, b
	or c
	ret z
	jr delay

msg:
        db 'Z80 monitor', 13, 10, 255

