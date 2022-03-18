;-------------------------------------------------------;
; R21:R20 - REGISTERS USED TO DISPLAY DIGITS            ;      
;-------------------------------------------------------;
; ROWS: PB[0:3] - ROW[1:4]                              ;
; COLUMNS: PC[0:3] - COL[1:4]                           ;
;-------------------------------------------------------;
.def counter_low = r20          ; lower byte of counter
.def counter_high = r21         ; upper byte of counter
.def interrupt_flag = r22       ; checks if interrupt occoured
.def interrupt_validator = r23  ; prevents performing interrupt routine twice
.def start_flag = r24           ; checks start button
.def keyboard_value = r25       ; contains binary value 
.def comparator = r26           ; to compare registers with (mostly) constant value
.def keypad_block = r27         ; used during countdown to disable incrementing/decrementing
.def reset_flag = r30           ; checks if reset is needed
.include "m328pbdef.inc"
;-------------------------------------------------------------------------------------
; Memory setup
;-------------------------------------------------------------------------------------
.cseg
.org 0x00 
                jmp prog_start 
.org PCINT1addr 
                jmp keypad_ISR       ; Keypad External Interrupt Request
.org 0x32 digit:
.db 0x7e, 0x30, 0x6d, 0x79, 0x33, 0x5b, 0x5f, 0x70, 0x7f, 0x7b, 0x77, 0x1f, 0x4e, 0x3d, 0x4f, 0x47
.org 0x100
;-------------------------------------------------------------------------------------
;                                          Main
;-------------------------------------------------------------------------------------

prog_start:
                  ; stack initialization
                  ldi r16, high(ramend)
                  out sph, r16
                  ldi r16, low(ramend)
                  out spl, r16
                  
                  ; setting display ports
                  ldi r16, 0xff
                  out ddrd, r16
                  out ddre, r16
                  
                  ; portc columns as inputs
                  ldi r16, 0x00
                  out ddrc, r16
                  ldi r16, 0x0f
                  out portc, r16
                  
                  ; portb rows as outputs
                  ldi r16, 0x0f
                  out ddrb, r16
                  
                  ; interrupt initialization
                  ldi counter_low, (1<<pcint8)|(1<<pcint9)|(1<<pcint10)|(1<<pcint11)
                  sts pcmsk1, r16
                  ldi r16, (1<<pcie1)
                  sts pcicr, r16
                  
digit_start:
                  ldi ZL, low(2*digit)
                  ldi ZH, high(2*digit)
                  sei
                  
initial_state:    ; init all values
                  ldi comparator, 0x01 
                  ldi interrupt_validator, 0x2 
                  ldi interrupt_flag, 0x0
                  ldi reset_flag, 0x00
                  ldi start_flag, 0x00
                  ldi counter_high, 0x0
                  ldi counter_low, 0x0
                  ldi keypad_block, 0x0
                  
;-------------------------------------------------------------------------------------
;                                      Loop
;-------------------------------------------------------------------------------------

setup_loop:
                  call display
 
                  cp start_flag, comparator                           ; checks if s13 was pressed
                  breq start_countdown                                ; if yes - starts counting down
                  rjmp setup_loop
                  
start_countdown:
                  push r16                                            ; check if counter value == 0 
                  ldi r16, 0x00
                  cp counter_low, r16
                  brne countdown_100_percent
                  cp counter_high, r16
                  brne countdown_100_percent
                  pop r16
                  jmp prog_start                                      ; if counter value == 0 => go to prog_start
                  
countdown_100_percent: ; start counting for sure
                  pop r16
                  ldi comparator, 0xff                                ; set comparator to 0xff and use it in countdown
                  loop
                  ldi reset_flag, 0xfe
                  call countdown
                  rjmp initial_state                                  ; or jmp prog_start 
                  
;-------------------------------------------------------------------------------------
;                                   INTERRUPT
;-------------------------------------------------------------------------------------

/* ----- begin interrupt ----- */
keypad_ISR:
                  dec interrupt_validator
                  brne dont_jmp_pass
                  jmp pass
dont_jmp_pass: 
                  inc interrupt_flag
                  
/*----- decode ----- */
decode:
                  ;Set rows as inputs and columns as outputs 
                  ldi r28, 0x0 
                  out ddrb, r28
                  ldi r28, 0x0f
                  out ddrc, r28
                  
                  ;Set rows to high (pull ups) and columns to low 
                  ldi r28, 0x0f 
                  out portb, r28
                  ldi r28, 0x0
                  out portc, r28
                  
                  in keyboard_value, pinb
                  andi keyboard_value, 0x0f
                  
                  swap keyboard_value
                  
                  ;Set rows as outputs and columns as inputs 
                  ldi r28, 0x0f 
                  out ddrb, r28
                  ldi r28, 0x0
                  out ddrc, r28
                  
                  ;Set columns to high (pull ups) and rows to low 
                  ldi r28, 0x0f
                  out portc, r28
                  ldi r28, 0x0
                  out portb, r28
                  
                  ;Read Port C. Columns code in low nibble 
                  in r29, pinc
                  andi r29, 0x0f
                  or keyboard_value, r29
                  ; r17 b0:b3 contains column number, b4:b7 contains row number 
                  ; save column and row number (one hot)
                  push r16
                  push r17
                  push r18
                  push r19
                  
                  cp keypad_block, comparator                  ; if keypad_block == comparator => don't
                                                               ; incement or decrement, allow reset only
                  brne s1_check                                ; if keypad_block != comparator => allow
                                                               ; interrupt execution 
                  jmp s16_check 
                  
s1_check:
                  ldi r16, 0b00010001
                  cp keyboard_value, r16                       ; checks if the nubmer is s1
                  brne s2_check                                ; if not, check s2, else jump to s1 routine
                  jmp s1                                       ; same for other "cp"
                  
s2_check:
                  ldi r16, 0b00010010
                  cp keyboard_value, r16                       ; checks if the nubmer is s2
                  brne s3_check
                  jmp s2

s3_check:
                  ldi r16, 0b00010100
                  cp keyboard_value, r16                       ; checks if the nubmer is s3
                  brne s4_check
                  jmp s3
                  
s4_check:
                  ldi r16, 0b00011000
                  cp keyboard_value, r16                        ; checks if the nubmer is s4
                  brne s5_check
                  jmp s4
                  
s5_check:
                  ldi r16, 0b00100001
                  cp keyboard_value, r16                        ; checks if the nubmer is s5
                  brne s6_check
                  jmp s5
                  
s6_check:
                  ldi r16, 0b00100010
                  cp keyboard_value, r16 ; checks if the nubmer is s6
                  brne s7_check
                  jmp s6
                  
s7_check:
                  ldi r16, 0b00100100
                  cp keyboard_value, r16                       ; checks if the nubmer is s7
                  brne s8_check
                  jmp s7
                  
s8_check:
                  ldi r16, 0b00101000
                  cp keyboard_value, r16                       ; checks if the nubmer is s8
                  brne s13_check
                  jmp s8
                  
s13_check:
                  ldi r16, 0b10000001
                  cp keyboard_value, r16                       ; checks if the nubmer is s13
                  brne s16_check
                  jmp s13
                  
s16_check:
                  ldi r16, 0b10001000
                  cp keyboard_value, r16                       ; checks if the nubmer is s16
                  brne others
                  jmp s16
                  
others:
                  rjmp end                                     ; if s[9:12] or s[14:15] do nothing
                  
/* ----- after you know which button was pressed ----- */
s1:
                  ldi r17, 0x10                                ; load 0b00010000 to r17
                  ldi r18, 0xf0                                ; load 0b11110000 mask to r18
                  mov r19, counter_high                        ; copy counter_high value to r19
                  and r19, r18                                 ; r19 = ????0000
                  cp r19, r18                                  ; if r19 == 0xf0, do not add value
                  breq end
                  add counter_high, r17                        ; else add 0xf0 to counter_high
                  rjmp end                                     ; SIMILARLY OTHER BUTTONS
                  
s2:
                  ldi r17, 0x01
                  ldi r18, 0x0f
                  mov r19, counter_high
                  and r19, r18
                  cp r19, r18
                  breq end
                  add counter_high, r17
                  rjmp end
                  
s3:
                  ldi r17, 0x10
                  ldi r18, 0xf0
                  mov r19, counter_low
                  and r19, r18
                  cp r19, r18
                  breq end
                  add counter_low, r17
                  rjmp end
s4:
                  ldi r17, 0x01
                  ldi r18, 0x0f
                  mov r19, counter_low
                  and r19, r18
                  cp r19, r18
                  breq end
                  add counter_low, r17
                  rjmp end
                  
s5:
                  ldi r17, 0x10
                  ldi r18, 0x00
                  mov r19, counter_high
                  andi r19, 0xf0
                  cp r19, r18
                  breq end
                  sub counter_high, r17
                  rjmp end
                  
s6:
                  ldi r17, 0x01
                  ldi r18, 0x00
                  mov r19, counter_high
                  andi r19, 0x0f
                  cp r19, r18
                  breq end
                  sub counter_high, r17
                  rjmp end
                  
s7:
                  ldi r17, 0x10
                  ldi r18, 0x00
                  mov r19, counter_low
                  andi r19, 0xf0
                  cp r19, r18
                  breq end
                  sub counter_low, r17
                  rjmp end
                  
s8:
                  ldi r17, 0x01
                  ldi r18, 0x00
                  mov r19, counter_low
                  andi r19, 0x0f
                  cp r19, r18
                  breq end
                  sub counter_low, r17
                  rjmp end
                  
s13:
                  inc start_flag                            ; start countdown subroutine
                  ldi keypad_block, 0xff                    ; 0xff because comparator during countdown is equal to 0xff       
                  
                  rjmp end
                  
s16: 
                  jmp prog_start                            ; RESET
end:
                  ldi interrupt_flag, 0x00                  ; don't compare after subroutine 
                  pop r19
                  pop r18
                  pop r17
                  pop r16
                  rjmp return
                  
pass:                                                       ; if switch goes from pushed to unpushed
                  ldi interrupt_validator, 0x02
                  ldi interrupt_flag, 0x00
return:
                  reti
                  
;-------------------------------------------------------------------------------------
;                                       SUBROUTINES
;-------------------------------------------------------------------------------------

/* ------------- display subroutine ---------------- */
display:
                 push r16
                 push r17
                 
                 ; 4th number logic
                 ldi ZL, low(2*digit)
                 push counter_low
                 andi counter_low,0x0f
                 add zl, counter_low
                 pop counter_low
                 
                 ldi r17, 0x08                               ; pick 4th number
                 com r17
                 lpm r16, z
                 com r16
                 out porte, r17
                 out portd, r16
                 call wait_1_20
                 
                  ; 3rd number logic
                  ldi ZL, low(2*digit)
                  push counter_low
                  swap counter_low
                  andi counter_low, 0x0f
                  add zl,counter_low
                  pop counter_low
                  
                  ldi r17, 0x04                             ; pick 3rd number
                  com r17
                  lpm r16, z
                  com r16
                  out porte, r17
                  out portd, r16
                  call wait_1_20
                  
                  ; 2nd number logic
                  ldi ZL, low(2*digit)
                  push counter_high
                  andi counter_high, 0x0f
                  add zl, counter_high
                  pop counter_high
                  
                  ldi r17, 0x02                             ; pick 2nd number
                  com r17
                  lpm r16, z
                  com r16
                  out porte, r17
                  out portd, r16
                  call wait_1_20
                  
                  ; 1st number logic
                  ldi ZL, low(2*digit)
                  push counter_high
                  swap counter_high
                  andi counter_high, 0x0f
                  add zl, counter_high
                  pop counter_high
                    
                  ldi r17, 0x01 ; pick 1st number
                  com r17
                  lpm r16, z
                  com r16
                  out porte, r17
                  out portd, r16
                  call wait_1_20
                  pop r17
                  pop r16
                  ret
                  
/* -------- subroutine that makes 1/20s delay --------- */

wait_1_20:
                  push r17
                  push r18
                  ldi r17, 255
                  
w20_second_loop: 
                  ldi r18, 255
                  
w20_first_loop:
                  dec r18
                  brne w20_first_loop                       ; repeat 250 times
                  dec r17
                  brne w20_second_loop                      ; repeat 200 times
                  pop r17
                  pop r18
                  ret                                       ; return to "call wait_1_20"
                  
/* ------------- countdown subroutine --------------------- */

countdown:
                  call display
                  call display
                  call display
                  call display
                  
                  dec counter_low                           ; decrement lower bit
                  breq dec_counter_high                     ; if lower bit == 0 => decrement upper bit 
                  
                  rjmp countdown                            ; else decrement lower bit again
                  
dec_counter_high:
                  dec counter_high                          ; decrement upper bit
                  cp counter_high, comparator               ; if upper bit == 0xff => end counting
                  breq countdown_return
                  rjmp countdown
                  
countdown_return:
                  ret
