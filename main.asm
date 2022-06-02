;----system reset interrupt----
org 0000H
ajmp prog_start
;----system reset interrupt end----

;----external 0 interrupt----
org 0003H
ajmp external_0_interrupt
;----external 0 interrupt end----

;----timer 0 interrupt----
org 000BH
ajmp timer_0_interrupt
;----timer 0 interrupt end----

;----timer 1 interrupt----
org 001BH
ajmp timer_1_interrupt
;----timer 1 interrupt end----

;----timer 2 interrupt----
org 002BH
ajmp timer_2_interrupt
;----timer 2 interrupt end----

;----main segment start----
org 0080H
prog_start:
;init device
lcall init_device

;stop buzzer from making noise
clr buzzer

;reset stack top
mov SP,#initial_stack_top

;start pseudo countdown thread
;setb TR0

;start pseudo display thread
mov progress_bit_state,#progress_start
setb TR1

;display initial prompt
acall display_end_prompt

;reset time input
mov time_input,#0
mov time_left,#0

setb allow_key_test
setb key_up

;disable led array
clr countdown_started

main_loop:
jnb allow_key_test,main_loop
acall get_keyboard_input
mov R7,keyboard_input
cjne R7,#false_input,keydown
setb key_up
sjmp main_loop

keydown:
clr buzzer
jnb key_up,main_loop
clr key_up
clr allow_key_test
mov button_test_stage_1,keyboard_input
setb TR2
sjmp main_loop
;----main segment end----

;----pin configuration definitions----
number_display_a bit P0.6
number_display_b bit P0.7
led_array_clock bit P3.4
led_array_data bit P3.3
buzzer bit P3.1
indicator_led bit P0.0
pause_button bit P0.1
;----pin configuration definitions end----

;----global constant definitions----
using 0

initial_stack_top equ 30H

;timer 1
frame_timer_initial equ 0H

;timer 0
;63802cycles -> 1s
countdown_timer_initial_high equ 06H
countdown_timer_initial_low equ 0C6H

;timer 2
button_detector_initial_high equ 0FFH
button_detector_initial_low equ 07H

number_display_0 equ 50H
number_display_1 equ 51H
number_display_2 equ 52H
number_display_3 equ 53H
number_display_state equ 54H
letter_P equ 10
letter_A equ 11
letter_U equ 12
letter_S equ 13
empty_display equ 14
end_display_0 equ 15
end_display_1 equ 16
end_display_2 equ 17
progress_start equ 18
progress_end equ 23
letter_E equ 25
letter_r equ 26
exclaimation_mark equ 27
pause_mark equ 28

time_input equ 55H
time_left equ 56H

led_array_state equ 57H

button_test_stage_1 equ 58H
pause equ 30H

false_input equ 21H

progress_bit_state equ 59H

keyboard_input equ 5AH

allow_key_test bit 02H
key_up bit 03H
	
countdown_started bit 04H
;----global constant definitions end----

;----sub: initialize----
$include (c8051f310.inc)
public init_device

init segment code
rseg init

pca_init:
mov PCA0MD,#000H
ret

port_io_init:
mov P0MDOUT,#0C1H
mov P1MDOUT,#0FFH
mov P3MDOUT,#1AH
mov XBR1,#40H
ret

timer_init:
mov TMOD,#021H
mov CKCON,#002H

mov TL0,#countdown_timer_initial_low
mov TH0,#countdown_timer_initial_high

mov TL1,#frame_timer_initial
mov TH1,#frame_timer_initial

mov TMR2L,#button_detector_initial_low
mov TMR2H,#button_detector_initial_high
mov TMR2RLL,#button_detector_initial_low
mov TMR2RLH,#button_detector_initial_high
ret

interrupts_init:
mov IE,#0ABH
mov IP,#28H
setb IT0
ret

init_device:
acall pca_init
acall port_io_init
acall timer_init
acall interrupts_init
ret
;----initialize end----

;----sub: display number state----
display_number_step:
push PSW
push AR0
push AR1
push ACC

mov R0,#number_display_state

display_number_step_state_0:
cjne @R0,#0,display_number_step_state_1
inc @R0
clr number_display_b
clr number_display_a
mov R1,#number_display_0
sjmp display_number_step_set_number

display_number_step_state_1:
cjne @R0,#1,display_number_step_state_2
inc @R0
clr number_display_b
setb number_display_a
mov R1,#number_display_1
sjmp display_number_step_set_number

display_number_step_state_2:
cjne @R0,#2,display_number_step_state_3
inc @R0
setb number_display_b
clr number_display_a
mov R1,#number_display_2
sjmp display_number_step_set_number

display_number_step_state_3:
mov @R0,#0
setb number_display_b
setb number_display_a
mov R1,#number_display_3

display_number_step_set_number:
mov DPTR,#display_number_step_number_dictionary
mov A,@R1
movc A,@A+DPTR
mov P1,A

pop ACC
pop AR1
pop AR0
pop PSW
ret

display_number_step_number_dictionary:
db 11111100B ;0
db 01100000B ;1
db 11011010B ;2
db 11110010B ;3
db 01100110B ;4
db 10110110B ;5
db 10111110B ;6
db 11100000B ;7
db 11111110B ;8
db 11110110B ;9
db 11001110B ;P
db 11101110B ;A
db 01111100B ;U
db 10110110B ;S
db 00000000B ;[empty]
db 10011100B ;[
db 10010000B ;=
db 11110000B ;]
db 10000000B ;[progress 1]
db 01000000B ;[progress 2]
db 00100000B ;[progress 3]
db 00010000B ;[progress 4]
db 00001000B ;[progress 5]
db 00000100B ;[progress 6]
db 00000000B ;[skipped byte]
db 10011110B ;E
db 00001010B ;r
db 01000001B ;!
db 00000010B ;[pause mark]
nop
;----sub end----

;----sub: set led array----
display_led_array:
push PSW
push AR0
push ACC
push B

jnb countdown_started,display_led_array_all_clear

mov R0,#time_input
cjne @R0,#15,display_led_array_test
sjmp display_led_array_non_overflow
display_led_array_test:
jnc display_led_array_overflow

display_led_array_non_overflow:
mov A,time_left
mov B,#8
mul AB

mov B,time_input
div AB

sjmp display_led_array_test_countdown

display_led_array_overflow:
mov B,#8
mov A,time_input
div AB

mov B,A
mov A,time_left
div AB

inc A
cjne A,#9,display_led_array_test_countdown
mov A,#8

display_led_array_test_countdown:
mov R0,#time_left
cjne @R0,#0,display_led_array_output_start
mov R0,#8
ajmp display_led_array_set_loop

display_led_array_output_start:
mov R0,A
mov A,#8

display_led_array_clear_loop:
clr led_array_clock
clr led_array_data
setb led_array_clock
dec A

djnz R0,display_led_array_clear_loop

mov R0,A
cjne R0,#0,display_led_array_set_loop
sjmp display_led_array_end

display_led_array_set_loop:
clr led_array_clock
setb led_array_data
setb led_array_clock

djnz R0,display_led_array_set_loop

sjmp display_led_array_end

display_led_array_all_clear:
mov R0,#8
setb led_array_data
display_led_array_all_clear_loop:
clr led_array_clock
setb led_array_clock
djnz R0,display_led_array_all_clear_loop

display_led_array_end:
pop B
pop ACC
pop AR0
pop PSW
ret
;----sub end----

;----sub: set display number to time left----
display_time_left:
push PSW
push AR0
push ACC
push B

mov A,time_left

mov B,#10
div AB
mov number_display_0,B

mov B,#10
div AB
mov number_display_1,B

mov B,#10
div AB
mov number_display_2,B

mov R0,#number_display_2
cjne @R0,#0,display_time_left_progress_bit
mov number_display_2,#empty_display

mov R0,#number_display_1
cjne @R0,#0,display_time_left_progress_bit
mov number_display_1,#empty_display

mov R0,#number_display_0
cjne @R0,#0,display_time_left_progress_bit
mov number_display_0,#empty_display

display_time_left_progress_bit:
jb countdown_started,display_time_left_progress_bit_run
mov number_display_3,#end_display_1
sjmp display_time_left_end

display_time_left_progress_bit_run:
mov R0,#progress_bit_state
cjne @R0,#progress_end,display_time_left_progress_continue
mov progress_bit_state,#progress_start
sjmp display_time_left_progress_end

display_time_left_progress_continue:
inc progress_bit_state

display_time_left_progress_end:
mov number_display_3,progress_bit_state

display_time_left_end:
pop B
pop ACC
pop AR0
pop PSW
ret
;----sub end----

;----sub: start countdown----
start_countdown:
push AR0

mov R0,#time_input
cjne @R0,#0,start_countdown_confirm
acall display_error_prompt
sjmp start_countdown_end

start_countdown_confirm:
clr allow_key_test
setb TR0
setb indicator_led
setb countdown_started
clr buzzer
mov number_display_3,progress_bit_state

start_countdown_end:
pop AR0
ret
;----sub end----

;----sub: stop countdown----
stop_countdown:
setb allow_key_test
clr TR0
clr indicator_led
clr countdown_started
acall display_end_prompt
setb buzzer
mov time_input,#0
mov time_left,#0
ret
;----sub end----

;----sub: pause countdown----
pause_countdown:
setb allow_key_test
clr TR0
clr indicator_led
mov number_display_3,#pause_mark
ret
;----sub end----

;----sub: resume countdown----
resume_countdown:
clr allow_key_test
setb TR0
setb indicator_led
acall display_time_left
ret
;----end sub----

;----sub: display pause prompt----
display_pause_prompt:
mov number_display_3,#letter_P
mov number_display_2,#letter_A
mov number_display_1,#letter_U
mov number_display_0,#letter_S
ret
;----sub end----

;----sub: display end propmt----
display_end_prompt:
mov number_display_0,#end_display_2
mov number_display_1,#end_display_1
mov number_display_2,#end_display_1
mov number_display_3,#end_display_0
ret
;----sub end----

;----sub: display error propmt----
display_error_prompt:
mov number_display_3,#letter_E
mov number_display_2,#letter_r
mov number_display_1,#letter_r
mov number_display_0,#exclaimation_mark
ret
;----sub end----

;----sub: append a new digit to the end of current time input----
append_digit:
push PSW

jnb countdown_started,append_digit_start
clr countdown_started
mov time_input,#0
mov time_left,#0

append_digit_start:
clr OV
mov A,time_input
mov B,#10
mul AB
jb OV,append_digit_error

add A,keyboard_input
jc append_digit_error

mov time_left,A
mov time_input,A
acall display_time_left
sjmp append_digit_end

append_digit_error:
mov time_input,#0
mov time_left,#0
acall display_error_prompt

append_digit_end:
pop PSW
ret
;----sub end----

;----sub: get keyboard input----
get_keyboard_input:
push PSW
push AR0
push AR1
push AR2
push ACC
push B

mov R2,#00000001B

mov R0,#0
get_keyboard_input_outer_loop:
mov A,R2
xrl A,#11111111B
mov P2,A
mov A,R2
rl A
mov R2,A

mov A,P2
mov R1,#4
get_keyboard_input_inner_loop:
rlc A
jnc get_keyboard_input_found_key
djnz R1,get_keyboard_input_inner_loop

inc R0
cjne R0,#4,get_keyboard_input_outer_loop
sjmp get_keyboard_input_invalid

get_keyboard_input_found_key:
dec R1
mov A,R1
mov B,#4
mul AB

add A,R0
mov keyboard_input,A
sjmp get_keyboard_input_end

get_keyboard_input_invalid:
mov keyboard_input,#false_input

get_keyboard_input_end:
pop B
pop ACC
pop AR2
pop AR1
pop AR0
pop PSW
ret
;----sub end----

;----interrupt handler: external 0----
external_0_interrupt:
clr EX0
setb TR2
mov button_test_stage_1,#pause
reti
;----interrupt handler end----

;----interrupt handler: timer 0----
timer_0_interrupt:
push PSW
push AR0
mov TL0,#countdown_timer_initial_low
mov TH0,#countdown_timer_initial_high

mov R0,#time_left
dec time_left
cjne @R0,#0,timer_0_interrupt_not_finished
acall stop_countdown
sjmp timer_0_interrupt_end

timer_0_interrupt_not_finished:
acall display_time_left

timer_0_interrupt_end:
pop AR0
pop PSW
reti
;----interrupt handler end----

;----interrupt handler: timer 1----
timer_1_interrupt:
acall display_number_step
acall display_led_array
reti
;----interrupt handler end----

;----interrupt handler: timer 2----
timer_2_interrupt:
push PSW
push AR0
push ACC

clr TR2
clr TF2H
clr TF2L

mov R0,#button_test_stage_1
;button == pause
cjne @R0,#pause,timer_2_interrupt_not_pause
setb EX0
jb pause_button,timer_2_interrupt_end
jnb countdown_started,timer_2_interrupt_start_countdown
jnb TR0,timer_2_interrupt_resume_countdown
acall pause_countdown
sjmp timer_2_interrupt_end

;resume countdown
timer_2_interrupt_resume_countdown:
mov R0,#time_left
cjne @R0,#0,timer_2_interrupt_resume_countdown_not_ended
sjmp timer_2_interrupt_end

timer_2_interrupt_resume_countdown_not_ended:
acall resume_countdown
sjmp timer_2_interrupt_end

timer_2_interrupt_start_countdown:
acall start_countdown
sjmp timer_2_interrupt_end

;button != pause
timer_2_interrupt_not_pause:
setb allow_key_test
mov A,keyboard_input
cjne A,button_test_stage_1,timer_2_interrupt_end

cjne A,#10,timer_2_interrupt_test
sjmp timer_2_interrupt_end
timer_2_interrupt_test:
jnc timer_2_interrupt_end

;valid input
acall append_digit

sjmp timer_2_interrupt_end

timer_2_interrupt_end:
mov button_test_stage_1,#false_input

pop ACC
pop AR0
pop PSW
reti
;----interrupt handler end----

end
