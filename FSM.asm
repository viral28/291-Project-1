$NOLIST
$MODLP52
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 500     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

BOOT_BUTTON   equ P4.5
SOUND_OUT     equ P3.7
UPDOWN        equ P0.0

; Reset vector
org 0000H
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0003H
	reti

; Timer/Counter 0 overflow interrupt vector
org 000BH
	reti

; External interrupt 1 vector (not used in this code)
org 0013H
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 001BH
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0023H 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 002BH
	ljmp Timer2_ISR

dseg at 30h
Count1ms:     	ds 2 ; Used to determine when half second has passed
CURRENT_STATE:	ds 1 ;current state 
SEC:			ds 1 ;timer
TEMP:			ds 1 ;temperature

bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed

cseg 
;PWM 			EQU P0.0
START_BUTTON 	EQU P0.3

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

Timer2_Init:
	mov T2CON, #0 ; Stop timer.  Autoreload mode.
	; One millisecond interrupt
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Set the 16-bit variable Count1ms to zero
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
    setb EA   ; Enable Global interrupts
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically in ISR
	cpl P3.6 ; To check the interrupt rate with oscilloscope. It must be a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(500), Timer2_ISR_done
	mov a, Count1ms+1
	cjne a, #high(500), Timer2_ISR_done
	
	; 500 milliseconds have passed.  Set a flag so the main program knows
	setb half_seconds_flag ; Let the main program know half second had passed
	cpl TR1 ; This line makes a beep-silence-beep-silence sound
	; Reset the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Increment the BCD counter
	mov a, SEC
	jnb UPDOWN, Timer2_ISR_decrement
	add a, #0x01
	sjmp Timer2_ISR_da
Timer2_ISR_decrement:
	add a, #0x99
Timer2_ISR_da:
	da a
	mov SEC, a
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
main:
	; Initialization
    mov SP, #7FH
    mov PMOD, #0 ; Configure all ports in bidirectional mode
    lcall Timer2_Init
    lcall LCD_4BIT
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
    setb half_seconds_flag
	mov SEC, #0x00
	
	; After initialization the program stays in this 'forever' loop
forever:
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	jnb BOOT_BUTTON, $		; wait for button release
	; A clean press of the 'BOOT' button has been detected, reset the BCD counter.
	; But first stop the timer and reset the milli-seconds counter, to resync everything.
	clr TR0
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Now clear the BCD counter
	mov SEC, #0x00
	setb TR0                ; Re-enable the timer
	sjmp loop_b             ; Display the new value
loop_a:
	jnb half_seconds_flag, forever
loop_b:
    clr half_seconds_flag ; We clear this flag in the main forever, but it is set in the ISR for timer 0


		mov a, CURRENT_STATE
STATE0:
		cjne a, #0, STATE1
		mov PWM, #0
		jb START_BUTTON, STATE0_DONE
		lcall Wait_Milli_Seconds(#50); debounce time
		jb START_BUTTON, STATE0_DONE
		jnb START_BUTTON, $ ; Wait for key release
		mov CURRENT_STATE, #1
STATE0_DONE:
		ljmp forever
STATE1:
		cjne a, #1, STATE2
		mov PWM, #100
		mov SEC, #0
		mov a, #150
		clr c
		subb a, TEMP
		jnc STATE1_DONE
		mov CURRENT_STATE, #2
STATE1_DONE:
		ljmp forever
STATE2:
		cjne a, #2, STATE3
		mov PWM, #20
		mov a, #60
		clr c
		subb a, SEC ;need interrupts
		jnc STATE2_DONE
		mov CURRENT_STATE, #3
STATE2_DONE:
		ljmp forever

;NEW CODE

STATE3:
		cjne a, #3, STATE4
		mov PWM, #100
		mov SEC, #0
		mov a, #220
		clr c
		subb a, TEMP
		jnc STATE3_DONE
		mov CURRENT_STATE, #4
STATE3_DONE:
		ljmp forever

STATE4:
		cjne a, #4, STATE5
		mov PWM, #20
		mov a, #45
		clr c
		subb a, SEC ;need interrupts
		jnc STATE4_DONE
		mov CURRENT_STATE, #5
STATE4_DONE:
		ljmp forever

STATE5:
		cjne a, #5, forever
		mov PWM, #0
		mov SEC, #0
		mov a, #60
		clr c
		subb a, TEMP
		jnc STATE5_DONE
		mov CURRENT_STATE, #0
STATE5_DONE:
		ljmp forever