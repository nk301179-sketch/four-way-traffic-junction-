.include "m328pdef.inc"

; ============================================================
; SMART TRAFFIC JUNCTION CONTROLLER - FINAL CODE
; Arduino Uno / ATmega328P
; ============================================================
;
; TRAFFIC LIGHTS
;
; D8  / PB0 = North + South RED
; D9  / PB1 = North + South YELLOW
; D10 / PB2 = North + South GREEN
;
; D11 / PB3 = East + West RED
; D12 / PB4 = East + West YELLOW
; D13 / PB5 = East + West GREEN
;
;
; PEDESTRIAN
;
; D2 / PD2 = Push button / INT0
;
; D3 = Countdown LED 1
; D4 = Countdown LED 2
; D5 = Countdown LED 3
; D6 = Countdown LED 4
; D7 = Countdown LED 5
;
;
; LIGHT SENSOR
;
; A0 / ADC0 = LDR
;
; Calibrated threshold:
;
; ADC < 15  = DARK
; ADC >= 15 = BRIGHT
;
;
; NORMAL MODE TIMINGS
;
; Green   = 5 seconds
; Yellow  = 2 seconds
; All Red = 1 second
;
;
; NIGHT MODE
;
; Yellow ON  = 0.5 sec
; Yellow OFF = 0.5 sec
;
; Complete flash cycle = 1 second = 1 Hz
;
; Exit Night Mode only after
; 5 consecutive bright seconds
;
; Pedestrian button is ignored during Night Mode
;
; ============================================================


.cseg


; ============================================================
; INTERRUPT VECTOR TABLE
; ============================================================

.org 0x0000
    rjmp RESET


.org INT0addr
    rjmp BUTTON_ISR


; Keep program away from vector table

.org 0x0100



; ============================================================
; RESET / INITIALIZATION
; ============================================================

RESET:

    ; --------------------------------------------------------
    ; Stack pointer
    ; --------------------------------------------------------

    ldi r16, HIGH(RAMEND)
    out SPH, r16

    ldi r16, LOW(RAMEND)
    out SPL, r16



    ; --------------------------------------------------------
    ; TRAFFIC LEDs
    ;
    ; PB0-PB5 = outputs
    ; D8-D13
    ; --------------------------------------------------------

    ldi r16, 0b00111111
    out DDRB, r16


    ; Initially all traffic LEDs OFF

    clr r16
    out PORTB, r16



    ; --------------------------------------------------------
    ; PEDESTRIAN PINS
    ;
    ; PD2     = input
    ; PD3-PD7 = countdown outputs
    ; --------------------------------------------------------

    ldi r16, 0b11111000
    out DDRD, r16


    ; PD2 internal pull-up enabled
    ;
    ; Countdown LEDs initially OFF

    ldi r16, 0b00000100
    out PORTD, r16



    ; --------------------------------------------------------
    ; PEDESTRIAN REQUEST FLAG
    ;
    ; r20 = 0 ? no request
    ; r20 = 1 ? pedestrian request waiting
    ; --------------------------------------------------------

    clr r20



    ; --------------------------------------------------------
    ; INT0 SETUP
    ;
    ; D2 / PD2
    ;
    ; Falling edge interrupt
    ;
    ; Not pressed = HIGH
    ; Pressed     = LOW
    ; --------------------------------------------------------

    ldi r16, (1<<ISC01)
    sts EICRA, r16


    ; Clear old interrupt flag

    ldi r16, (1<<INTF0)
    out EIFR, r16


    ; Enable INT0

    ldi r16, (1<<INT0)
    out EIMSK, r16



    ; --------------------------------------------------------
    ; ADC SETUP
    ;
    ; A0 = ADC0
    ;
    ; AVcc reference
    ; Left-adjusted result
    ; --------------------------------------------------------

    ldi r16, (1<<REFS0) | (1<<ADLAR)
    sts ADMUX, r16


    ; Enable ADC
    ; Prescaler = 128

    ldi r16, (1<<ADEN) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0)
    sts ADCSRA, r16



    ; --------------------------------------------------------
    ; TIMER1 SETUP
    ;
    ; Arduino Uno clock = 16 MHz
    ;
    ; Prescaler = 256
    ;
    ; OCR1A = 31249
    ;
    ; approximately 0.5 second
    ; --------------------------------------------------------

    clr r16
    sts TCCR1A, r16


    ldi r16, HIGH(31249)
    sts OCR1AH, r16


    ldi r16, LOW(31249)
    sts OCR1AL, r16


    ; CTC mode
    ; Prescaler 256

    ldi r16, (1<<WGM12) | (1<<CS12)
    sts TCCR1B, r16



    ; Enable global interrupts

    sei



; ============================================================
; NORMAL MODE
; ============================================================

NORMAL_MODE:



; ============================================================
; PHASE 1
;
; NORTH + SOUTH = GREEN
; EAST + WEST   = RED
;
; D10 / PB2 = N/S GREEN
; D11 / PB3 = E/W RED
; ============================================================

    ldi r16, 0b00001100
    out PORTB, r16


    ; Stay green for 5 seconds

    ldi r18, 5
    rcall NORMAL_DELAY



    ; Check if darkness detected

    cpi r22, 1
    brne AFTER_NS_GREEN_CHECK

    rjmp ENTER_NIGHT


AFTER_NS_GREEN_CHECK:



; ============================================================
; NORTH + SOUTH = YELLOW
; EAST + WEST   = RED
;
; D9 / PB1  = N/S YELLOW
; D11 / PB3 = E/W RED
; ============================================================

    ldi r16, 0b00001010
    out PORTB, r16


    ; Yellow for 2 seconds

    ldi r18, 2
    rcall NORMAL_DELAY



    cpi r22, 1
    brne AFTER_NS_YELLOW_CHECK

    rjmp ENTER_NIGHT


AFTER_NS_YELLOW_CHECK:



; ============================================================
; ALL RED CLEARANCE
;
; N/S RED = PB0
; E/W RED = PB3
; ============================================================

    ldi r16, 0b00001001
    out PORTB, r16


    ; All-red for 1 second

    ldi r18, 1
    rcall NORMAL_DELAY



    cpi r22, 1
    brne AFTER_NS_RED_CHECK

    rjmp ENTER_NIGHT


AFTER_NS_RED_CHECK:



    ; --------------------------------------------------------
    ; Check pedestrian request
    ;
    ; Request is only handled AFTER:
    ;
    ; Green finished
    ; Yellow finished
    ; All-red finished
    ; --------------------------------------------------------

    cpi r20, 1
    brne START_EW_PHASE


    rcall PEDESTRIAN_MODE



; ============================================================
; PHASE 2
; ============================================================

START_EW_PHASE:



; ============================================================
; NORTH + SOUTH = RED
; EAST + WEST   = GREEN
;
; PB0 + PB5
; ============================================================

    ldi r16, 0b00100001
    out PORTB, r16


    ; Green for 5 seconds

    ldi r18, 5
    rcall NORMAL_DELAY



    cpi r22, 1
    brne AFTER_EW_GREEN_CHECK

    rjmp ENTER_NIGHT


AFTER_EW_GREEN_CHECK:



; ============================================================
; NORTH + SOUTH = RED
; EAST + WEST   = YELLOW
;
; PB0 + PB4
; ============================================================

    ldi r16, 0b00010001
    out PORTB, r16


    ; Yellow for 2 seconds

    ldi r18, 2
    rcall NORMAL_DELAY



    cpi r22, 1
    brne AFTER_EW_YELLOW_CHECK

    rjmp ENTER_NIGHT


AFTER_EW_YELLOW_CHECK:



; ============================================================
; ALL RED CLEARANCE
; ============================================================

    ldi r16, 0b00001001
    out PORTB, r16


    ; All-red 1 second

    ldi r18, 1
    rcall NORMAL_DELAY



    cpi r22, 1
    brne AFTER_EW_RED_CHECK

    rjmp ENTER_NIGHT


AFTER_EW_RED_CHECK:



    ; --------------------------------------------------------
    ; Check pedestrian request
    ; --------------------------------------------------------

    cpi r20, 1
    brne RETURN_TO_NS


    rcall PEDESTRIAN_MODE



RETURN_TO_NS:

    rjmp NORMAL_MODE



; ============================================================
; PEDESTRIAN MODE
; ============================================================

PEDESTRIAN_MODE:


    ; --------------------------------------------------------
    ; Consume current pedestrian request
    ; --------------------------------------------------------

    clr r20



    ; --------------------------------------------------------
    ; Disable INT0
    ;
    ; Any button presses during countdown are ignored.
    ; --------------------------------------------------------

    clr r16
    out EIMSK, r16



    ; --------------------------------------------------------
    ; ALL VEHICLE DIRECTIONS RED
    ; --------------------------------------------------------

    ldi r16, 0b00001001
    out PORTB, r16



; ============================================================
; COUNTDOWN = 5
; ============================================================

    ; All 5 countdown LEDs ON

    ldi r16, 0b11111100
    out PORTD, r16


    rcall WAIT_ONE_SECOND



; ============================================================
; COUNTDOWN = 4
; ============================================================

    ldi r16, 0b01111100
    out PORTD, r16


    rcall WAIT_ONE_SECOND



; ============================================================
; COUNTDOWN = 3
; ============================================================

    ldi r16, 0b00111100
    out PORTD, r16


    rcall WAIT_ONE_SECOND



; ============================================================
; COUNTDOWN = 2
; ============================================================

    ldi r16, 0b00011100
    out PORTD, r16


    rcall WAIT_ONE_SECOND



; ============================================================
; COUNTDOWN = 1
; ============================================================

    ldi r16, 0b00001100
    out PORTD, r16


    rcall WAIT_ONE_SECOND



; ============================================================
; COUNTDOWN = 0
;
; Countdown LEDs OFF
; Keep PD2 pull-up enabled
; ============================================================

    ldi r16, 0b00000100
    out PORTD, r16



    ; --------------------------------------------------------
    ; IMPORTANT FIX
    ;
    ; A button press during the countdown may have set
    ; the hardware INT0 flag even though INT0 was disabled.
    ;
    ; Clear that flag so the old press is completely ignored.
    ; --------------------------------------------------------

    ldi r16, (1<<INTF0)
    out EIFR, r16



    ; --------------------------------------------------------
    ; RE-ENABLE BUTTON NOW
    ;
    ; Therefore:
    ;
    ; button press during countdown = ignored
    ;
    ; but once next vehicle GREEN starts,
    ; new button presses are accepted.
    ; --------------------------------------------------------

    ldi r16, (1<<INT0)
    out EIMSK, r16



    ret



; ============================================================
; PEDESTRIAN BUTTON INTERRUPT
;
; IMPORTANT:
;
; Button DOES NOT immediately change traffic.
;
; It only remembers the pedestrian request.
; ============================================================

BUTTON_ISR:


    ; Save r16

    push r16


    ; Save SREG

    in r16, SREG
    push r16



    ; --------------------------------------------------------
    ; Set pedestrian request flag
    ; --------------------------------------------------------

    ldi r20, 1



    ; Restore SREG

    pop r16
    out SREG, r16


    ; Restore r16

    pop r16


    reti



; ============================================================
; NORMAL DELAY
;
; INPUT:
;
; r18 = number of seconds
;
;
; During Normal Mode the LDR is checked once every second.
;
;
; OUTPUT:
;
; r22 = 0 ? continue Normal Mode
; r22 = 1 ? darkness detected
;
; ============================================================

NORMAL_DELAY:


    clr r22



NORMAL_DELAY_LOOP:


    ; Wait one second

    rcall WAIT_ONE_SECOND



    ; Read LDR

    rcall READ_ADC



    ; --------------------------------------------------------
    ; DARK THRESHOLD
    ;
    ; ADC < 15 = dark
    ; --------------------------------------------------------

    cpi r17, 15

    brlo NORMAL_DARK_FOUND



    ; One second completed

    dec r18


    brne NORMAL_DELAY_LOOP



    ret



NORMAL_DARK_FOUND:


    ; Set darkness flag

    ldi r22, 1


    ret



; ============================================================
; ENTER NIGHT MODE
; ============================================================

ENTER_NIGHT:


    ; --------------------------------------------------------
    ; Pedestrian requests are ignored during Night Mode
    ; --------------------------------------------------------

    clr r20



    ; Disable pedestrian interrupt

    clr r16
    out EIMSK, r16



    ; Turn countdown LEDs OFF
    ;
    ; Keep PD2 pull-up ON

    ldi r16, 0b00000100
    out PORTD, r16



    ; --------------------------------------------------------
    ; r24 = consecutive bright seconds
    ; --------------------------------------------------------

    clr r24



; ============================================================
; NIGHT MODE LOOP
; ============================================================

NIGHT_LOOP:



; ============================================================
; ALL FOUR YELLOW LEDs ON
;
; PB1 = N/S yellow
; PB4 = E/W yellow
; ============================================================

    ldi r16, 0b00010010
    out PORTB, r16



    ; ON for 0.5 sec

    rcall HALF_SECOND



; ============================================================
; ALL TRAFFIC LEDs OFF
; ============================================================

    clr r16
    out PORTB, r16



    ; OFF for 0.5 sec

    rcall HALF_SECOND



    ; --------------------------------------------------------
    ; One full ON/OFF cycle = 1 second
    ;
    ; Therefore flash frequency = 1 Hz
    ; --------------------------------------------------------



    ; Read ambient light

    rcall READ_ADC



    ; --------------------------------------------------------
    ; Is it still dark?
    ; --------------------------------------------------------

    cpi r17, 15

    brsh NIGHT_BRIGHT



    ; --------------------------------------------------------
    ; DARK
    ;
    ; Reset bright counter
    ; --------------------------------------------------------

    clr r24


    rjmp NIGHT_LOOP



; ============================================================
; BRIGHT DETECTED DURING NIGHT MODE
; ============================================================

NIGHT_BRIGHT:


    ; One consecutive bright second

    inc r24



    ; --------------------------------------------------------
    ; Need 5 consecutive bright seconds
    ; --------------------------------------------------------

    cpi r24, 5

    brsh EXIT_NIGHT



    ; Not yet 5 seconds

    rjmp NIGHT_LOOP



; ============================================================
; EXIT NIGHT MODE
; ============================================================

EXIT_NIGHT:


    ; Reset counter

    clr r24



    ; All traffic LEDs OFF momentarily

    clr r16
    out PORTB, r16



    ; --------------------------------------------------------
    ; Clear pedestrian requests generated during Night Mode
    ; --------------------------------------------------------

    clr r20



    ; Clear pending INT0 hardware flag

    ldi r16, (1<<INTF0)
    out EIFR, r16



    ; Re-enable pedestrian button

    ldi r16, (1<<INT0)
    out EIMSK, r16



    ; --------------------------------------------------------
    ; Resume Normal Mode safely from N/S GREEN
    ; --------------------------------------------------------

    rjmp NORMAL_MODE



; ============================================================
; READ ADC0 / A0
;
; Result:
;
; r17 = 8-bit ADC value
; ============================================================

READ_ADC:


    ; Read ADCSRA

    lds r16, ADCSRA



    ; Start ADC conversion

    ori r16, (1<<ADSC)


    sts ADCSRA, r16



ADC_WAIT:


    ; Wait until conversion finishes

    lds r16, ADCSRA


    sbrc r16, ADSC
    rjmp ADC_WAIT



    ; Read upper 8 bits

    lds r17, ADCH


    ret



; ============================================================
; WAIT ONE SECOND
;
; 0.5 sec + 0.5 sec
; ============================================================

WAIT_ONE_SECOND:


    rcall HALF_SECOND

    rcall HALF_SECOND


    ret



; ============================================================
; HALF SECOND DELAY
;
; TIMER1 CTC
; ============================================================

HALF_SECOND:


    ; --------------------------------------------------------
    ; Reset Timer1
    ; --------------------------------------------------------

    clr r23


    sts TCNT1H, r23
    sts TCNT1L, r23



    ; --------------------------------------------------------
    ; Clear previous Compare Match A flag
    ; --------------------------------------------------------

    ldi r23, (1<<OCF1A)

    out TIFR1, r23



HALF_SECOND_WAIT:


    ; Wait for compare match

    in r23, TIFR1


    sbrs r23, OCF1A

    rjmp HALF_SECOND_WAIT



    ; Clear compare flag

    ldi r23, (1<<OCF1A)

    out TIFR1, r23


    ret