;###############################################################################
;# S12CForth - FOUTER - Forth outer interpreter                                #
;###############################################################################
;#    Copyright 2011-2014 Dirk Heisswolf                                       #
;#    This file is part of the S12CForth framework for Freescale's S12C MCU    #
;#    family.                                                                  #
;#                                                                             #
;#    S12CForth is free software: you can redistribute it and/or modify        #
;#    it under the terms of the GNU General Public License as published by     #
;#    the Free Software Foundation, either version 3 of the License, or        #
;#    (at your option) any later version.                                      #
;#                                                                             #
;#    S12CForth is distributed in the hope that it will be useful,             #
;#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
;#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
;#    GNU General Public License for more details.                             #
;#                                                                             #
;#    You should have received a copy of the GNU General Public License        #
;#    along with S12CForth.  If not, see <http://www.gnu.org/licenses/>.       #
;###############################################################################
;# Description:                                                                #
;#    This module implements the outer interpreter of the S12CForth            #
;#    environment.                                                             #
;#                                                                             #
;#    The outer interpreter uses these registers:                              #
;#           BASE = Number conversion radix                                    #
;#     NUMBER_TIB = Number of chars in the TIB                                 #
;#          TO_IN = In-pointer of the TIB (>IN)	       			       #
;#       	    (TIB_START+TO_IN) points to the next character	       #
;#                                                                             #
;###############################################################################
;# Version History:                                                            #
;#    February 5, 2013                                                         #
;#      - Initial release                                                      #
;###############################################################################
;# Required Modules:                                                           #
;#    BASE - S12CBase framework                                                #
;#    FPS    - Forth parameter stack                                           #
;#    FRS    - Forth return stack                                              #
;#    FCOM   - Forth communication interface                                   #
;#    FINNER - Forth inner interpreter                                         #
;#    FEXCPT - Forth Exception Handler                                         #
;#                                                                             #
;# Requirements to Software Using this Module:                                 #
;#    - none                                                                   #
;###############################################################################
;        
;                         +--------------+--------------+        
;        RS_TIB_START, -> |              |              | |          
;           TIB_START     |       Text Input Buffer     | | [NUMBER_TIB]
;                         |              |              | |	       
;                         |              v              | <	       
;                     -+- | --- --- --- --- --- --- --- | 	       
;          TIB_PADDING |  .                             . <- [TIB_START+NUMBER_TIB] 
;                     -+- .                             .            
;                         | --- --- --- --- --- --- --- |            
;                         |              ^              | <- [RSP]
;                         |              |              |
;                         |        Return Stack         |
;                         |              |              |
;                         +--------------+--------------+
;             RS_EMPTY, ->                                 
;           RS_TIB_END
;
;Shell state transitions:
; INTERACTIVE: STATE=0, IP_SUSP=0, IP=0
; COMPILE:     STATE>0, IP_SUSP=0, IP=0
; SUSPEND:              IP_SUSP>0, IP=0
; EXECUTE:                         IP>0
;
	
;###############################################################################
;# Configuration                                                               #
;###############################################################################
;Safety distance to return stack
#ifndef TIB_PADDING
TIB_PADDING		EQU	4 		;default is 4 bytes
#endif
	
;###############################################################################
;# Constants                                                                   #
;###############################################################################
;Text input buffer 
TIB_START		EQU	RS_TIB_START

;Default line width 
DEFAULT_LINE_WIDTH	EQU	80

;###############################################################################
;# Variables                                                                   #
;###############################################################################
#ifdef FOUTER_VARS_START_LIN
			ORG 	FOUTER_VARS_START, FOUTER_VARS_START_LIN
#else
			ORG 	FOUTER_VARS_START
FOUTER_VARS_START_LIN	EQU	@
#endif	
			ALIGN	1	
BASE			DS	2 		;number conversion radix

STATE			DS	2 		;interpreter state (0:iterpreter, -1:compile)
NUMBER_TIB  		DS	2		;number of chars in the TIB
TO_IN  			DS	2		;in pointer of the TIB (TIB_START+TO_IN point to the next empty byte)
TIB_OFFSET  		DS	2		;TIB buffer offset (for nested shells) 

FOUTER_VARS_END		EQU	*
FOUTER_VARS_END_LIN	EQU	@

;###############################################################################
;# Macros                                                                      #
;###############################################################################
;#Initialization
#macro	FOUTER_INIT, 0
			LED_BUSY_ON
			MOVW	#STATE_INTERPRET, STATE
			MOVW	#$0010, BASE
			MOVW	#$0000, NUMBER_TIB 
			MOVW	#$0000, TO_IN
			MOVW	#$0000, TIB_OFFSET
			MOVW	#$0000, SUSPENDED_IP
#emac

;#Abort action (to be executed in addition of quit and suspend action)
#macro	FOUTER_ABORT, 0
#emac
	
;#Quit action (to be executed in addition of suspend action)
#macro	FOUTER_QUIT, 0
			MOVW	#STATE_INTERPRET, STATE
			MOVW	#$0000, NUMBER_TIB
#emac
	
;#Suspend action
#macro	FOUTER_SUSPEND, 0
			;MOVW	IP, SUSPENDED_IP 	;save IP
			MOVW	NUMBER_TIB, TIB_OFFSET	;save TIB offset	
#emac
	
;Break/suspend handling:
;=======================
;#Break: Set break indicator and perform a systewm reset
#macro	SCI_BREAK_ACTION, 0
			RESET_RESTART_NO_MSG	
#emac

;#Suspend: Set suspend flag
#macro	SCI_SUSPEND_ACTION, 0
			LDX	NEXT_PTR 		;avoid nested SUSPEND requests
			CPX	#NEXT_SUSPEND_MODE
			BEQ	DONE
			MOVW	#NEXT_SUSPEND_ENTRY, NEXT_PTR
DONE			EQU	*	
#emac

;Functions:
;==========
;#Fix and load BASE
; args:   BASE: any base value
; result: D:    range adjusted base value (2<=base<=16)
;         BASE: range adjusted base value (2<=base<=16)
; SSTACK: none
;         X and Y are preserved
#macro	FOUTER_FIX_BASE, 0
			SSTACK_JOBSR	FOUTER_FIX_BASE, 2
#emac

;#Find the next string (delimited by a selectable character) on the TIB and terminate it. 
; args:   A:   delimiter
;         #TIB: char count in TIB
;         >IN:  TIB index
; result: X:    string pointer
;	  D:    character count
;         >IN:  new TIB index
; SSTACK: 5 bytes
;         Y is preserved
#macro	FOUTER_PARSE, 0
			SSTACK_JOBSR	FOUTER_PARSE, 5
#emac

;#Find the next string (delimited by whitespace) on the TIB and terminate it. 
; args:   #TIB: char count in TIB
;         >IN:  TIB index
; result: X:    string pointer
;	  D:    character count
;         >IN:  new TIB index
; SSTACK: 5 bytes
;         Y is preserved
#macro	FOUTER_PARSE_WS, 0
			LDAA	" "
			FOUTER_PARSE
#emac

;#Convert a string into an unsigned number
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if successful (cleared on overflow) 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 10 bytes
;         X, Y, and D are preserved
#macro	FOUTER_TO_NUMBER, 0
			SSTACK_CHECK_BOUNDARIES	10, 10
			JOBSR	FOUTER_TO_NUMBER
#emac

;#Check for a sign prefix
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if prefix was found 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 8 bytes
;         X, Y, and D are preserved
#macro	FOUTER_TO_SIGN, 0
			SSTACK_CHECK_BOUNDARIES	8, 10
			JOBSR	FOUTER_TO_SIGN
#emac

;#Check for a filler character
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if filler character was found 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 10 bytes
;         X, Y, and D are preserved
#macro	FOUTER_TO_FILLER, 0
			SSTACK_CHECK_BOUNDARIES	8, 10
			JOBSR	FOUTER_TO_FILLER
#emac

;#Check for an ASM-style base prefix
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if prefix was found 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 8 bytes
;         X, Y, and D are preserved
#macro	FOUTER_TO_ABASE, 0
			SSTACK_CHECK_BOUNDARIES	8, 10
			JOBSR	FOUTER_TO_ABASE
#emac

;#Check for a C-style base prefix
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if prefix was found 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 10 bytes
;         X, Y, and D are preserved
#macro	FOUTER_TO_CBASE, 0
			SSTACK_CHECK_BOUNDARIES	10, 10
			JOBSR	FOUTER_TO_CBASE
#emac

#Check if the string starts with a valid digit
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if first character is a valid digit	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 10 bytes
;         X, Y, and D are preserved
#macro	FOUTER_PEEK_NUM, 0
			SSTACK_CHECK_BOUNDARIES	10, 10
			JOBSR	FOUTER_PEEK_NUM
#emac
	
;#Convert a terminated string into a number
; args:   X:   string pointer
;	  D:   character count
; result: Y:X: number (saturated in case of an overflow)
;	  D:   cell count
;	       or  0 if format is invalid
;	       or -1 in case of an overflow	
; SSTACK: 22 bytes
;         No registers are preserved
#macro	FOUTER_INTEGER, 0	
			SSTACK_JOBSR	FOUTER_INTEGER, 22
#emac

;###############################################################################
;# Code                                                                        #
;###############################################################################
#ifdef FOUTER_CODE_START_LIN
			ORG 	FOUTER_CODE_START, FOUTER_CODE_START_LIN
#else
			ORG 	FOUTER_CODE_START
FOUTER_CODE_START_LIN	EQU	@
#endif
	
;#Fix and load BASE
; args:   BASE: any base value
; result: D:    range adjusted base value (2<=base<=16)
;         BASE: range adjusted base value (2<=base<=16)
; SSTACK: 2 bytes
;         X and Y are preserved
FOUTER_FIX_BASE		EQU	*
			LDD	BASE
			CPD	#NUM_BASE_MAX
			BLS	FOUTER_FIX_BASE_1
			LDD	#NUM_BASE_MAX
			JOB	FOUTER_FIX_BASE_2
FOUTER_FIX_BASE_1	CPD	#NUM_BASE_MIN
			BHS	FOUTER_FIX_BASE_3
			LDD	#NUM_BASE_MIN
FOUTER_FIX_BASE_2	STD	BASE
			;Done 
FOUTER_FIX_BASE_3	SSTACK_PREPULL	2
			RTS

;#Find the next string (delimited by a selectable character) on the TIB and terminate it. 
; args:   A:    delimiter
;         #TIB: char count in TIB
;         >IN:  TIB index
; result: X:    string pointer
;	  D:    character count	
;         >IN:  new TIB index
; SSTACK: 4 bytes
;         Y is preserved
FOUTER_PARSE		EQU	*	
			;Save registers
			PSHY
			;Check for empty string (delimiter in A)
			LDY	TO_IN			;current >IN -> Y
FOUTER_PARSE_1		CPY	NUMBER_TIB		;check for the end of the input buffer
			BHS	FOUTER_PARSE_7		;return empty string
			BCLR	TIB_START,Y, #$80	;remove termination
			CMPA	TIB_START,Y		
			BEQ	FOUTER_PARSE_2		;skip delimeter
			CMPA	#" "			;check is delimiter is space char
			BNE	FOUTER_PARSE_3		;parse remaining caracters
			CMPA	TIB_START,Y		
			BLS	FOUTER_PARSE_3		;parse remaining caracters
FOUTER_PARSE_2		LEAY	1,Y			;skip delimeter (increment >IN)
			JOB	FOUTER_PARSE_1
			;Parse remaining characters (>IN in Y, delimiter in A)
FOUTER_PARSE_3		LEAX	TIB_START,Y 		;string pointer -> X
FOUTER_PARSE_4		LEAY	1,Y			;increment >IN		
			CPY	NUMBER_TIB		;check for the end of the input buffer
			BHS	FOUTER_PARSE_5		;return parsed string
			BCLR	TIB_START,Y, #$80	;remove termination
			CMPA	TIB_START,Y		
			BEQ	FOUTER_PARSE_5		;delimeter found
			CMPA	#" "			;check is delimiter is space char
			BNE	FOUTER_PARSE_4		;parse remaining caracters
			CMPA	TIB_START,Y		
			BLS	FOUTER_PARSE_4		;parse remaining caracters
			;Delimeter found (>IN in Y, string pointer in X)
FOUTER_PARSE_5		STY	TO_IN 			;update >IN
			LEAY	TIB_START,Y		;end delimiter position -> Y
			BSET	-1,Y, #$80 		;terminate previous character
			TFR	X, D			;calculate character count
			COMA
			COMB
			ADDD	#1
			LEAY	D,Y
			TFR	Y, D
			;Restore registers (string pointer in X, char count in D)
FOUTER_PARSE_6		SSTACK_PREPULL	4
			PULY
			;Done (string pointer in X, char count in D)
			RTS
			;Return enpty string
FOUTER_PARSE_7		MOVW	NUMBER_TIB, TO_IN 	;mark parse area emptu
			CLRA				;clear char count
			CLRB
			TFR	D, X 			;clear string pointer
			JOB	FOUTER_PARSE_6		;done

;#Convert a string into an unsugned number
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if successful (cleared on overflow) 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 10 bytes
;         X, Y, and D are preserved
FOUTER_TO_NUMBER	EQU	*
FOUTER_TO_NUMBER_BASE	EQU	 8 				;base
FOUTER_TO_NUMBER_STRCNT	EQU	10				;char count
FOUTER_TO_NUMBER_STRPTR	EQU	12				;string pointer
FOUTER_TO_NUMBER_NUMHI	EQU	14				;number MSW
FOUTER_TO_NUMBER_NUMLO	EQU	16				;number LSW
			;Save registers
			PSHY
			PSHX
			PSHD
			;Check string length
FOUTER_TO_NUMBER_1	LDD	FOUTER_TO_NUMBER_STRCNT,SP
			BEQ	FOUTER_TO_NUMBER_3 		;empty input string
			;Read base
			LDD	FOUTER_TO_NUMBER_BASE,SP 	;sign/base -> D
			ANDA	#$7F				;remove sign bit
			TFR	D, X				;base -> X
			;Read digit from string (base in X)
			LDAB	[FOUTER_TO_NUMBER_STRPTR,SP] 	;read char
			ANDB	#$7F				;remove termination
			STRING_UPPER				;make upper case (SSTACK: 8 bytes)
			;Convert digit (char in B, base in X)
FOUTER_TO_NUMBER_2	CMPB	(FOUTER_SYMTAB-1),X
			BEQ	FOUTER_TO_NUMBER_5 		;digit found
			DBNE	X, FOUTER_TO_NUMBER_2		;try next symbol
			;Restore registers
FOUTER_TO_NUMBER_3	SSTACK_PREPULL	8
			SEC					;flag no overflow
FOUTER_TO_NUMBER_4	PULD
			PULX
			PULY
			;Done
			RTS
			;Add digit (digit+1 in X)
FOUTER_TO_NUMBER_5	LEAX	-1,X
			;Multiply number by base and add digit (digit in X)
			LDY	FOUTER_TO_NUMBER_NUMLO,SP
			STX	FOUTER_TO_NUMBER_NUMLO,SP		
			LDD	FOUTER_TO_NUMBER_BASE,SP
			ANDA	#$7F 				;remove sign bit
			EMUL					;Y * D => Y:D
			ADDD	FOUTER_TO_NUMBER_NUMLO,SP	;add digit to temp result
			EXG	Y, D
			ADCB	#$00
			ADCA	#$00
			BCS	FOUTER_TO_NUMBER_6 		;number out of range
			STY	FOUTER_TO_NUMBER_NUMLO,SP	;store resulting LSW
			LDY	FOUTER_TO_NUMBER_NUMHI,SP
			STD	FOUTER_TO_NUMBER_NUMHI,SP
			LDD	FOUTER_TO_NUMBER_BASE,SP
			ANDA	#$7F 				;remove sign bit			
			EMUL					;Y * D => Y:D
			TBNE	Y, FOUTER_TO_NUMBER_6 		;number out of range	
			ADDD	FOUTER_TO_NUMBER_NUMHI,SP	;add digit to temp result
			BCS	FOUTER_TO_NUMBER_6 		;number out of range
			STD	FOUTER_TO_NUMBER_NUMHI,SP	;
			;Advanve to next digit
			LDX	FOUTER_TO_NUMBER_STRCNT,SP
			LEAX	-1,X
			STX	FOUTER_TO_NUMBER_STRCNT,SP
			LDX	FOUTER_TO_NUMBER_STRPTR,SP
			LEAX	1,X
			STX	FOUTER_TO_NUMBER_STRPTR,SP
			JOB	FOUTER_TO_NUMBER_1
			;Number out fo range
FOUTER_TO_NUMBER_6	LDD	#$FFFF
			STD	FOUTER_TO_NUMBER_NUMHI,SP
			STD	FOUTER_TO_NUMBER_NUMLO,SP
FOUTER_TO_NUMBER_7	SSTACK_PREPULL	8
			CLC
			JOB	FOUTER_TO_NUMBER_4

;#Check for a sign prefix
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if prefix was found 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 8 bytes
;         X, Y, and D are preserved
FOUTER_TO_SIGN		EQU	*
FOUTER_TO_SIGN_BASE	EQU	 8 				;base
FOUTER_TO_SIGN_STRCNT	EQU	10				;char count
FOUTER_TO_SIGN_STRPTR	EQU	12				;string pointer
FOUTER_TO_SIGN_NUMHI	EQU	14				;number MSW
FOUTER_TO_SIGN_NUMLO	EQU	16				;number LSW
			;Save registers
			PSHY
			PSHX
			PSHD
			;Check string length
			LDY	FOUTER_TO_SIGN_STRCNT,SP
			BEQ	FOUTER_TO_SIGN_3 		;empty input string
			;Read char from string (char count in Y)
			LDX	FOUTER_TO_SIGN_STRPTR,SP			
			LDAB	1,X+ 				;read char
			ANDB	#$7F				;remove termination
			CMPB	#"+"				;check for plus prefix
			BEQ	FOUTER_TO_SIGN_1     		;plus sign found
			CMPB	#"-"				;check for minus prefix
			BNE	FOUTER_TO_SIGN_3     		;no prefix found
			;Invert sign (char count in Y, new string pointer in X)
			LDAA	#$80
			EORA	FOUTER_TO_SIGN_BASE,SP
			STAA	FOUTER_TO_SIGN_BASE,SP
			;Advance string pointer (char count in Y, new string pointer in X)
FOUTER_TO_SIGN_1	STX	FOUTER_TO_SIGN_STRPTR,SP 	;update string pointer
			LEAY	-1,Y				;decrement string count
			STY	FOUTER_TO_SIGN_STRCNT,SP
			;Restore registers
			JOB	FOUTER_TO_SIGN_2
FOUTER_TO_SIGN_2	EQU	FOUTER_TO_NUMBER_3
			;No prefix found 
FOUTER_TO_SIGN_3	EQU	FOUTER_TO_NUMBER_7

;#Check for a filler character
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if filler character was found 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 8 bytes
;         X, Y, and D are preserved
FOUTER_TO_FILLER	EQU	*
FOUTER_TO_FILLER_BASE	EQU	 8 				;base
FOUTER_TO_FILLER_STRCNT	EQU	10				;char count
FOUTER_TO_FILLER_STRPTR	EQU	12				;string pointer
FOUTER_TO_FILLER_NUMHI	EQU	14				;number MSW
FOUTER_TO_FILLER_NUMLO	EQU	16				;number LSW
			;Save registers
			PSHY
			PSHX
			PSHD
			;Check string length
			LDY	FOUTER_TO_FILLER_STRCNT,SP
			BEQ	FOUTER_TO_FILLER_2 		;empty input string
			;Read char from string (decremented char count in Y)
			LDX	FOUTER_TO_FILLER_STRPTR,SP			
			LDAB	1,X+ 				;read first char
			ANDB	#$7F				;remove termination
			CMPB	#"_"
			BEQ	FOUTER_TO_FILLER_3 		;filler char found
			;No filler char found
FOUTER_TO_FILLER_1	JOB	FOUTER_TO_FILLER_2		
FOUTER_TO_FILLER_2	JOB	FOUTER_TO_NUMBER_7		
			;Advance to nect character (char count in Y, new string pointer in X)
FOUTER_TO_FILLER_3	EQU	FOUTER_TO_SIGN_1
	
;#Check for an ASM-style base prefix
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if prefix was found 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 8 bytes
;         X, Y, and D are preserved
FOUTER_TO_ABASE		EQU	*
FOUTER_TO_ABASE_BASE	EQU	 8 				;base
FOUTER_TO_ABASE_STRCNT	EQU	10				;char count
FOUTER_TO_ABASE_STRPTR	EQU	12				;string pointer
FOUTER_TO_ABASE_NUMHI	EQU	14				;number MSW
FOUTER_TO_ABASE_NUMLO	EQU	16				;number LSW
			;Save registers
			PSHY
			PSHX
			PSHD
			;Check string length
			LDY	FOUTER_TO_ABASE_STRCNT,SP
			BEQ	FOUTER_TO_ABASE_4	 	;empty input string
			;Read char from string (char count in Y)
			LDX	FOUTER_TO_ABASE_STRPTR,SP			
			LDAB	1,X+ 				;read char
			ANDB	#$7F				;remove termination
			LDAA	#2 				;check for binary prefix 
			CMPB	#"%"
			BEQ	FOUTER_TO_ABASE_1 		;prefix found
			LDAA	#8				;check for octal prefix 
			CMPB	#"@"
			BEQ	FOUTER_TO_ABASE_1 		;prefix found
			LDAA	#10				;check for decimal prefix 
			CMPB	#"&"
			BEQ	FOUTER_TO_ABASE_1 		;prefix found
			LDAA	#16				;check for hexadecimal prefix 
			CMPB	#"$"
			BNE	FOUTER_TO_ABASE_4 		;no prefix found
			;Set base (base in A, char count in Y, new string pointer in X)
FOUTER_TO_ABASE_1	STAA	(FOUTER_TO_ABASE_BASE+1),SP
			BCLR	FOUTER_TO_ABASE_BASE,SP, #$7F
			;Advance string pointer (char count in Y, new string pointer in X)
FOUTER_TO_ABASE_2	JOB	FOUTER_TO_ABASE_3
FOUTER_TO_ABASE_3	EQU	FOUTER_TO_SIGN_1
			;No prefix found 
FOUTER_TO_ABASE_4	EQU	FOUTER_TO_NUMBER_7

;#Check for a C-style base prefix
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if prefix was found 	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 10 bytes
;         X, Y, and D are preserved
FOUTER_TO_CBASE		EQU	*
FOUTER_TO_CBASE_BASE	EQU	 8 				;base
FOUTER_TO_CBASE_STRCNT	EQU	10				;char count
FOUTER_TO_CBASE_STRPTR	EQU	12				;string pointer
FOUTER_TO_CBASE_NUMHI	EQU	14				;number MSW
FOUTER_TO_CBASE_NUMLO	EQU	16				;number LSW
			;Save registers
			PSHY
			PSHX
			PSHD
			;Check string length
			LDY	FOUTER_TO_CBASE_STRCNT,SP
			BEQ	FOUTER_TO_CBASE_2 		;empty input string
			DBEQ	Y, FOUTER_TO_CBASE_2 		;single char string
			;Read char from string (decremented char count in Y)
			LDX	FOUTER_TO_CBASE_STRPTR,SP			
			LDAB	1,X+ 				;read first char
			ANDB	#$7F				;remove termination
			CMPB	#"0"
			BNE	FOUTER_TO_CBASE_2 		;no prefix found
			LDAB	1,X+ 				;read second char
			ANDB	#$7F				;remove termination
			STRING_UPPER				;make upper case (SSTACK: 2 bytes)
			LDAA	#2 				;check for binary prefix 
			CMPB	#"B"
			BEQ	FOUTER_TO_CBASE_3 		;prefix found
			LDAA	#8				;check for octal prefix 
			CMPB	#"O"
			BEQ	FOUTER_TO_CBASE_3 		;prefix found
			LDAA	#10				;check for decimal prefix 
			CMPB	#"D"
			BEQ	FOUTER_TO_CBASE_3 		;prefix found
			LDAA	#16				;check for hexadecimal prefix 
			CMPB	#"H"
			BEQ	FOUTER_TO_CBASE_3 		;prefix found
			CMPB	#"X"
			BEQ	FOUTER_TO_CBASE_3 		;prefix found
			;No prefix found
FOUTER_TO_CBASE_1	JOB	FOUTER_TO_CBASE_2			
FOUTER_TO_CBASE_2	EQU	FOUTER_TO_NUMBER_7			
			;Set base (base in A, char count in Y, new string pointer in X)
FOUTER_TO_CBASE_3	EQU	FOUTER_TO_ABASE_1

;#Check if the string starts with a valid digit
; args:   Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; result: C-flag: set if first character is a valid digit	
;         Stack:        +--------+--------+
;			|    Sign/Base    | SP+0
;			+--------+--------+
;			| Rem Char Count  | SP+2
;			+--------+--------+
;			|  Rem Char Ptr   | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
; SSTACK: 10 bytes
;         X, Y, and D are preserved
FOUTER_PEEK_NUM		EQU	*
FOUTER_PEEK_NUM_BASE	EQU	 8 				;base
FOUTER_PEEK_NUM_STRCNT	EQU	10				;char count
FOUTER_PEEK_NUM_STRPTR	EQU	12				;string pointer
FOUTER_PEEK_NUM_NUMHI	EQU	14				;number MSW
FOUTER_PEEK_NUM_NUMLO	EQU	16				;number LSW
			;Save registers	
			PSHY
			PSHX
			PSHD
			;Check string length
			LDD	FOUTER_PEEK_NUM_STRCNT,SP
			BEQ	FOUTER_PEEK_NUM_3 		;empty input string
			;Read base
			LDD	FOUTER_PEEK_NUM_BASE,SP 	;sign/base -> D
			ANDA	#$7F				;remove sign bit
			TFR	D, X				;base -> X
			;Read char from string (base in X)
			LDAB	[FOUTER_PEEK_NUM_STRPTR,SP]	;read second char
			ANDB	#$7F				;remove termination
			STRING_UPPER				;make upper case (SSTACK: 2 bytes)
			;Convert digit (char in B, base in X)
FOUTER_PEEK_NUM_1	CMPB	(FOUTER_SYMTAB-1),X
       			BEQ	FOUTER_PEEK_NUM_4 		;valid digit found
       			DBNE	X, FOUTER_PEEK_NUM_1		;try next symbol
       			;No valid digit found
FOUTER_PEEK_NUM_2	JOB	FOUTER_PEEK_NUM_3
FOUTER_PEEK_NUM_3	EQU	FOUTER_TO_NUMBER_7
       			;Valid digit found
FOUTER_PEEK_NUM_4	EQU	FOUTER_TO_NUMBER_3
	
;#Convert a terminated string into a number
; args:   X:   string pointer
;	  D:   character count
; result: Y:X: number (saturated in case of an overflow)
;	  D:   cell count
;	       or  0 if format is invalid
;	       or -1 in case of an overflow	
; SSTACK: 22 bytes
;         No registers are preserved
FOUTER_INTEGER		EQU	*	
;			;Allocate temporary memory (string pointer in X, char count in D)
;         Stack:        +--------+--------+
;			|      Base       | SP+0
;			+--------+--------+
;			|   String Size   | SP+2
;			+--------+--------+
;			|   Char Pointer  | SP+4
;			+--------+--------+
;			|   Number MSW    | SP+6
;			+--------+--------+
;			|   Number LSW    | SP+8
;			+--------+--------+
FOUTER_INTEGER_BASE	EQU	0 			;base		
FOUTER_INTEGER_STRCNT	EQU	2			;char count	
FOUTER_INTEGER_STRPTR	EQU	4			;string pointer	
FOUTER_INTEGER_NUMHI	EQU	6			;number MSW	
FOUTER_INTEGER_NUMLO  	EQU	8			;number LSW	
FOUTER_INTEGER_RET_D	EQU	FOUTER_INTEGER_STRPTR	;D return value
FOUTER_INTEGER_RET_Y	EQU	FOUTER_INTEGER_NUMHI	;Y return value	
FOUTER_INTEGER_RET_X  	EQU	FOUTER_INTEGER_NUMLO	;X return value	
			;Initialize stack struckture (string pointer in X, char count in D)
			LDY	#$0000
			PSHY				;number LSW
			PSHY				;number MSW
			PSHX				;string pointer
			PSHD				;char count
			PSHY				;base (must be zero at this point)
			;Parse prefix
			;        v
			;    CHECK SIGN
			;    1 C-flag 0
			;    |        +----------+
			;    v                   v
			;    CHECK ABASE         CHECK ABASE
			;    1 C-flag  0         0 C-flag  1
			;    |         v         v         v
			;    |         CHECK CBASE     CHECK SIGN
			;    |         1 C-flag  0         |
			;    | +-------+         v	   |
			;    | |           DEFAULT BASE    |
			;    | | +---------------+         |       
			;    | | | +-----------------------+        
			;    | | | |        
			;    v v v v
			;    PEEK NUM
			;    1 C-f. 0   
			;    v      v
			;  valid invalid
			FOUTER_TO_SIGN 			;check for sign prefix
			BCS	FOUTER_INTEGER_3	;sign prefix found
			FOUTER_TO_ABASE 		;check for ASM-style base prefix
			BCS	FOUTER_INTEGER_4	;ASM-style base prefix found
FOUTER_INTEGER_1	FOUTER_TO_CBASE 		;check for C-style base prefix
			BCS	FOUTER_INTEGER_5	;C-style base prefix found
			FOUTER_FIX_BASE			;set default base
			BRCLR	FOUTER_INTEGER_BASE,SP, #$80, FOUTER_INTEGER_2	
			ORAA	#$80	
FOUTER_INTEGER_2	STD	FOUTER_INTEGER_BASE,SP
			JOB	FOUTER_INTEGER_5	;check if next character is a valid digit
FOUTER_INTEGER_3	FOUTER_TO_ABASE 		;check for ASM-style base prefix
			BCS	FOUTER_INTEGER_5	;ASM-style base prefix found
			JOB	FOUTER_INTEGER_1	;check for C-style base prefix
FOUTER_INTEGER_4	FOUTER_TO_SIGN  		;check for sign prefix
FOUTER_INTEGER_5	FOUTER_PEEK_NUM			;check if next character is a valid digit
			BCC	FOUTER_INTEGER_7	;invalid format
			;Parse number 
FOUTER_INTEGER_6	FOUTER_TO_NUMBER 		;parse digits
			BCC	FOUTER_INTEGER_13	;overflow occured
			LDD	FOUTER_INTEGER_STRCNT,SP;check number of remaing chars
			BEQ	FOUTER_INTEGER_10	;all digits parsed
			DBEQ	D, FOUTER_INTEGER_12	;one char left to parse
			FOUTER_TO_FILLER		;check for filler char
			BCS	FOUTER_INTEGER_6	;filler char found
			;Invalid format 
FOUTER_INTEGER_7	MOVW	#0, FOUTER_INTEGER_RET_D,SP	
FOUTER_INTEGER_8	MOVW	#0, FOUTER_INTEGER_RET_Y,SP	
			MOVW	#0, FOUTER_INTEGER_RET_X,SP
			;Return result 
FOUTER_INTEGER_9	SSTACK_PREPULL	12 		;free stack space
			LEAS	4,SP
			PULD
			PULY
			PULX
			RTS
			;Single cell integer found
FOUTER_INTEGER_10	LDD	FOUTER_INTEGER_NUMHI,SP ;check for overflow
			BNE	FOUTER_INTEGER_13	;overflow	
			MOVW	#1, FOUTER_INTEGER_RET_D,SP;return cell count
			BRCLR	FOUTER_INTEGER_BASE,SP, #$80, FOUTER_INTEGER_9;positive number
			LDY	FOUTER_INTEGER_NUMLO,SP ;check for overflow
			BMI	FOUTER_INTEGER_13	;overflow
			;Calculate 2's complement (NUMHI in D, NUMHI in Y)
FOUTER_INTEGER_11	COMA
			COMB
			EXG	D, Y
			COMA
			COMB
			ADDD	#1			
			EXG	D, Y
			ADCB	#0
			ADCA	#0
			STY	FOUTER_INTEGER_NUMLO,SP
			STD	FOUTER_INTEGER_NUMHI,SP
			JOB	FOUTER_INTEGER_9	;return result
			;Parse last character
FOUTER_INTEGER_12	LDAB	[FOUTER_INTEGER_STRPTR,SP]
			ANDB	#$7F			;remove termination
			CMPB	#"."			;check for double
			BNE	FOUTER_INTEGER_7	;invalid format
			MOVW	#2, FOUTER_INTEGER_RET_D,SP;return cell count
			BRCLR	FOUTER_INTEGER_BASE,SP, #$80, FOUTER_INTEGER_9;positive number
			LDY	FOUTER_INTEGER_NUMLO,SP
			LDD	FOUTER_INTEGER_NUMHI,SP ;check for overflow
			BPL	FOUTER_INTEGER_11	;calculate 2's complement
			;Overflow 
FOUTER_INTEGER_13	MOVW	#-1, FOUTER_INTEGER_RET_D,SP
			JOB	FOUTER_INTEGER_8	

;Search word in dictionary tree
; args:   Y: dictionary tree pointer
;         X: string pointer
;         D: char count 
; result: C-flag: set if word is in the dictionary	
;         D: {IMMEDIATE, CFA>>1} if word has been found, unchanged otherwise 
; SSTACK: 16  bytes
;         X and Y are preserved 
FOUTER_TREE_SEARCH	EQU	*
			;Save registers (tree pointer in Y, string pointer in X, char count in D)
			PSHY						;save Y
			PSHX						;save X
			PSHD						;save D	
			;Compare substring (tree pointer in Y, string pointer in X, char count in D)
FOUTER_TREE_SEARCH_1	FCDICT_COMP_STRING	FOUTER_TREE_SEARCH_5    ;compare substring (SSTACK: 8 bytes)
			;Substing matches (tree pointer in Y, string pointer in X, char count in D)
			BRCLR	0,Y, #$FF, FOUTER_TREE_SEARCH_4 	;branch detected
			TBNE	D, FOUTER_TREE_SEARCH_7 		;dictionary word too short -> unsuccessful
			;Search successful (tree pointer in Y, string pointer in X, char count in D)
FOUTER_TREE_SEARCH_2	SSTACK_PREPULL	8 				;check stack
			LDD	0,Y 					;get CFA
			SEC						;flag unsuccessful search
			PULX						;remove stack entry				
FOUTER_TREE_SEARCH_3	PULX						;restore X				
			PULY						;restore Y				
			;Done
			RTS		
			;Branch detected (tree pointer in Y, string pointer in X, char count in D) 
FOUTER_TREE_SEARCH_4	LDY	1,Y 					;switch to subtree
			TST	0,Y 					;check for STRING_TERMINATION
			BNE	FOUTER_TREE_SEARCH_1			;no end of dictionary word reached 
			LEAY	1,Y 					;skip zero string
			;Empty substring (tree pointer in Y, string pointer in X, char count in D)
			TBEQ	D, FOUTER_TREE_SEARCH_2 		;match
			LEAY	2,Y 					;switch to next sibling
			JOB	FOUTER_TREE_SEARCH_1			;Parse sibling
			;Try next sibling (tree pointer in Y, string pointer in X, char count in D)
FOUTER_TREE_SEARCH_5	BRCLR	1,Y+, #$FF, FOUTER_TREE_SEARCH_6	;check for BRANCH
			LEAY	1,Y					;skip over CFA
			JOB	FOUTER_TREE_SEARCH_1			;compare next sibling	
FOUTER_TREE_SEARCH_6	BRCLR	2,+Y, #$FF, FOUTER_TREE_SEARCH_7 	;END_OF_BRANCH -> unsuccessful
			JOB	FOUTER_TREE_SEARCH_1			;compare next sibling	
			;Search unsuccessful (tree pointer in Y, string pointer in X, char count in D)
FOUTER_TREE_SEARCH_7	SSTACK_PREPULL	8 				;check stack
			CLC						;flag successful search
			PULD						;restore D				
			JOB	FOUTER_TREE_SEARCH_3
	
;NEXT implementations:
;===================== 	
;Invoke the suspend shell
NEXT_SUSPEND_ENTRY	EQU	*
			;Push the execution context onto the RS 
			RS_CHECK_OF	4 				;check for RS overflow
			LDX	RSP
			MOVW	NEXT_PTR, 2,-X 				;save NEXT_PTR
			MOVW	IP,	  2,-X				;save IP
			MOVW	PSP,	  2,-X				;save PSP
			MOVW	HANDLER,  2,-X				;save HANDLER
			STX	RSP 					;update RSP
			MOVW	#$0000, HANDLER 			;set defaukt handler
			JOB	CF_SUSPEND_RT				;start SUSPEND shell

;Code fields:
;============
;ABORT run-time ( i*x -- ) ( R: j*x -- ) 
;Empty the data stack and perform the function of QUIT, which includes emptying
;the return stack, without displaying a message. 
; args:   none
; result: none
; SSTACK: 8 bytes
; PS:     1 cell
; RS:     2 cells
; throws: FEXCPT_EC_PSOF
;         FEXCPT_EC_RSOF
;         FEXCPT_EC_COMERR
CF_ABORT_RT		EQU	*
			;Initialize ABORT
			FORTH_ABORT
			;Suspend
			;JOB	CF_QUIT_RT

;QUIT run-time ( -- ) ( R: j*x -- )
;Empty the return stack, store zero in SOURCE-ID if it is present, make the user
;input device the input source, and enter interpretation state. Do not display a
;message. Repeat the following: 
; -Accept a line from the input source into the input buffer, set >IN to zero,
;  and interpret. 
; -Display the system prompt if in interpretation state,
;  all processing has been completed, and no ambiguous condition exists.
; args:   none
; result: none
; SSTACK: 8 bytes
; PS:     1 cell
; RS:     2 cells
; throws: FEXCPT_EC_PSOF
;         FEXCPT_EC_RSOF
;         FEXCPT_EC_COMERR
CF_QUIT_RT		EQU	*
			;Initialize QUIT
			FORTH_QUIT
			;Suspend
			;JOB	CF_SUSPEND_RT
	
;SUSPEND run-time ( -- )
;Execute a temporary debug shell.
; args:   none
; result: none
; SSTACK: 8 bytes
; PS:     1 cell
; RS:     2 cells
; throws: FEXCPT_EC_PSOF
;         FEXCPT_EC_RSOF
;         FEXCPT_EC_COMERR
CF_SUSPEND_RT		EQU	*
			;Initialize SUSPEND
               		FORTH_SUSPEND
			;Suspend
			;JOB	CF_SHELL	

;SHELL ( -- ) Generic interactive shell
;Common S12CForth shell. 
; args:   none
; result: none
; SSTACK: 22 bytes
; PS:     1 cell
; RS:     2 cells
; throws: FEXCPT_EC_PSOF
;         FEXCPT_EC_RSOF
;         FEXCPT_EC_COMERR
CF_SHELL		EQU	*
			;Print state dependant prompt
			EXEC_CF	CF_CR 			;print line break
			;Check for SUSPEND mode
			LDX	FOUTER_SUSPEND_PROMPT
			LDD	NEXT_PTR
			CPD	#NEXT_SUSPEND_MODE
			BEQ	CF_SHELL_1	 	;print prompt
			;Check for INTERACTIVE mode
			LDX	FOUTER_INTERACT_PROMPT
			LDD	STATE
			TBEQ	D, CF_SHELL_1 		;print prompt
			;Check for NV COMPILE mode
#ifdef NVC	
			LDX	FOUTER_NVCOMPILE_PROMPT
			LDD	NVC
			TBNE	D, CF_SHELL_1 		;print prompt
#endif
			;Assume NV COMPILE mode  
			LDX	FOUTER_NVCOMPILE_PROMPT
			;Print prompt string
CF_SHELL_1		PS_PUSH_X				
			EXEC_CF	CF_DOT_STRING
			;Query command line
			EXEC_CF	CF_QUERY_APPEND
			;Parse command line
CF_SHELL_2              LDAA	#" " 			;use whitespace as delimiter
			FOUTER_PARSE
			TBNE	D, CF_SHELL_3      	;search dictionaries
			;Parsing complete
			MOVW	TIB_OFFSET, NUMBER_TIB 	;clear local TIB segment
			;Print acknowledge
			PS_PUSH	#FOUTER_SYSTEM_ACK
			EXEC_CF	CF_STRING_DOT
			JOB	CF_SHELL
			;Search UDICT (string pointer in X, char count in D)
CF_SHELL_3		EQU	*
#ifdef	NVC
			LDY	NVC
			BNE	CF_SHELL_4 		;skip UDICT search
#endif
			;FUDICT_SEARCH
			BCS	CF_SHELL_5		;process word	
#ifdef	NVC
			;Search NVDICT (string pointer in X, char count in D)
CF_SHELL_4		FNVDICT_ISEARCH
			BCS	CF_SHELL_5		;process word	
#endif
			;Search CDICT (string pointer in X, char count in D)
			FCDICT_SEARCH
			BCC	CF_SHELL_8		;evaluate string as integer	
			;Process word ({IMMEDIATE, CFA>>1} in D)
CF_SHELL_5		LSLD				;extract CFA
			BCS	CF_SHELL_6		;execute immediate word
			LDY	NEXT_PTR		;check for SUSPEND mode
			CPY	#NEXT_SUSPEND_MODE
			BEQ	CF_SHELL_6		;execute word
			LDY	STATE			;check STATE
			BNE	CF_SHELL_7		;compile word
			;Execute word (CFA in D)
CF_SHELL_6 		TFR	D, X
			EXEC_CFA_X
			JOB	CF_SHELL_2		;parse next word
			;Compile word (CFA in D)
CF_SHELL_7		UDICT_CHECK_OF	1 		;new CP -> X
			STX	CP			;update compile pointer
			STD	-2,X			;add word to compilation
			JOB	CF_SHELL_2		;parse next word
			;Evaluate string as integer (string pointer in X, char count in D) 
CF_SHELL_8		FOUTER_INTEGER	     		;(SSTACK: 22 bytes)
			DBNE	D, CF_SHELL_11 		;check for double number
			;Process single number (number in X)
			LDD	NEXT_PTR		;check for SUSPEND mode
			CPD	#NEXT_SUSPEND_MODE
			BEQ	CF_SHELL_9		;push number onto PS
			LDD	STATE			;check STATE
			BNE	CF_SHELL_10		;compile number as literal
			;Push number onto PS (number in X)
CF_SHELL_9		PS_CHECK_OF	1 		;new PSP -> Y
			STY	PSP			;update PSP
			STX	0,Y	   		;push number onto PS
			JOB	CF_SHELL_2		;parse next word
			;Compile double number as literal (number in X)
CF_SHELL_10		TFR	X, Y
			UDICT_CHECK_OF	2 		;new CP -> X
			STX	CP			;update compile pointer
			MOVW	#CFA_LITERAL_RT, -4,X	;compile LITERAL xt
			STY	-2,X			;compile number
			JOB	CF_SHELL_2		;parse next word
			;Check for double number (cell count-1 in D,  number in Y:X)
CF_SHELL_11		DBNE	D, CF_SHELL_14 		;invalid number
			;Process double number (number in Y:X)
			LDD	NEXT_PTR		;check for SUSPEND mode
			CPD	#NEXT_SUSPEND_MODE
			BEQ	CF_SHELL_12		;push number onto PS
			LDD	STATE			;check STATE
			BNE	CF_SHELL_13		;compile number as literal
			;Push double number onto PS (number in Y:X)
CF_SHELL_12		TFR	Y, D
			PS_CHECK_OF	2 		;new PSP -> Y
			STY	PSP			;update PSP
			STD	0,Y			;push double number onto PS
			STX	2,Y
			JOB	CF_SHELL_2		;parse next word
			;Compile double number as literal (number in Y:X)
CF_SHELL_13		TFR	X, D
			UDICT_CHECK_OF	3 		;new CP -> X
			STX	CP			;update compile pointer
			MOVW	#CFA_2LITERAL_RT, -6,X	;compile 2LITERAL xt
			STY	-4,X			;compile double value
			STD	-2,X
			JOB	CF_SHELL_2		;parse next word
			; 
			;Unknown word (or number out of range)
CF_SHELL_14		THROW	 FEXCPT_EC_UDEFWORD
	
;COMMAND ( -- c-addr u)
;Retrive a string from the command line input. c-addr and u are the location and
;the length of the resulting string.
; args:   PROMPT:     pointer to the prompt string
;         NUMBER_TIB: TIB index   
;         TIB_OFFSET: TIB offset for subshells   
; result: c-addr:     pointer to the command string
;         u:          length of the command string
; SSTACK: 5 bytes
; PS:     2 cells
; RS:     2 cells
; throws: nothing
CF_COMMAND		EQU	*
			;Check PS availability 
CF_COMMAND_1		PS_CHECK_OF	2 		;new PSP -> Y
			;Parse command line (new PSP in Y)
			LDAA	#" " 			;use whitespace as delimiter
			FOUTER_PARSE
			TBNE	D, CF_COMMAND_2		;parsing was successful
			;Parsing was unsuccessful
			MOVW	TIB_OFFSET, NUMBER_TIB 	;clear local TIB segment
			;Print command line prompt 
			EXEC_CF	CF_DOT_PROMPT
			;Query command line
			EXEC_CF	CF_QUERY_APPEND
			JOB	CF_COMMAND_1			
			;Parsing was unsuccessful (new PSP in Y, string pointer in X, char count in D))
CF_COMMAND_2		STY	PSP 			;reserve space on PS
			STX	2,Y			;return c-addr
			STD	0,Y			;return u
			;Done
			NEXT
	
;QUERY ( -- ) Query command line input
;Make the user input device the input source. Receive input into the terminal
;input buffer,mreplacing any previous contents. Make the result, whose address is
;returned by TIB, the input buffer.  Set >IN to zero.
; args:   none
; result: #TIB: char count in TIB
;         >IN:  index pointing to the start of the TIB => 0x0000
; SSTACK: 8 bytes
; PS:     1 cell
; RS:     2 cells
; throws: FEXCPT_EC_PSOF
;         FEXCPT_EC_RSOF
;         FEXCPT_EC_COMERR
CF_QUERY		EQU	*
			;Reset input buffer
			MOVW	#0000, NUMBER_TIB
			;JOB	CF_QUERY_APPEND

;QUERY-APPEND ( -- ) Query command line input
;Set >IN to #TIB. Make the user input device the input source. Receive input into
;the terminal input buffer, appending previous contents. Make the result, whose
;address is returned by TIB+>IN, the input buffer.
; args:   #TIB: char count in TIB
; result: #TIB: new  char count in TIB
;         >IN:  index of the first new input char
; SSTACK: 8 bytes
; PS:     1 cell
; RS:     2 cells
; throws: FEXCPT_EC_PSOF
;         FEXCPT_EC_RSOF
;         FEXCPT_EC_COMERR
CF_QUERY_APPEND		EQU	*
			;Print prompt
			;EXEC_CF	CF_DOT_IPROMPT
			;Setup input buffer
			MOVW	NUMBER_TIB, TO_IN
			;Receive input
CF_QUERY_APPEND_1	EXEC_CF	CF_EKEY				;input car -> [PS+0]
			;Check input (input car in [PS+0])
			LDD	[PSP] 				;input char -> B
			;Ignore LF (input car in B)
			CMPB	#STRING_SYM_LF
			BEQ	CF_QUERY_APPEND_4		;ignore
			;Check for ENTER (CR) (input car in B and in [PS+0])
			CMPB	#STRING_SYM_CR	
			BEQ	CF_QUERY_APPEND_8		;input complete		
			;Check for BACKSPACE (input char in B and in [PS+0])
			CMPB	#STRING_SYM_BACKSPACE	
			BEQ	CF_QUERY_APPEND_7	 	;check for underflow
			CMPB	#STRING_SYM_DEL	
			BEQ	CF_QUERY_APPEND_7	 	;check for underflow
			;Check for valid special characters (input char in B and in [PS+0])
			CMPB	#STRING_SYM_TAB	
			BEQ	CF_QUERY_APPEND_2	 	;echo and append to buffer
			;Check for invalid characters (input char in B and in [PS+0])
			CMPB	#" " 				;first legal character in ASCII table
			BLO	CF_QUERY_APPEND_5		;beep
			CMPB	#"~"				;last legal character in ASCII table
			BHI	CF_QUERY_APPEND_5 		;beep			
			;Check for buffer overflow (input char in B and in [PS+0])
			LDY	NUMBER_TIB
			LEAY	(TIB_PADDING+TIB_START),Y
			CPY	RSP
			BHS	CF_QUERY_APPEND_5 		;beep
			;Append char to input line (input char in B and in [PS+0])
CF_QUERY_APPEND_2	LDY	NUMBER_TIB
			STAB	TIB_START,Y			;store character
			LEAY	1,Y				;increment char count
			STY	NUMBER_TIB
			;Echo input char (input char in [PS+0])
CF_QUERY_APPEND_3	EXEC_CF	CF_EMIT				;print character
			JOB	CF_QUERY_APPEND_1
			;Ignore input char
CF_QUERY_APPEND_4	LDY	PSP 				;drop char from PS
			LEAY	2,Y
			STY	PSP
			JOB	CF_QUERY_APPEND_1
			;BEEP			
CF_QUERY_APPEND_5	LDD	#STRING_SYM_BEEP		;replace received char by a beep
CF_QUERY_APPEND_6	STD	[PSP]
			JOB	CF_QUERY_APPEND_3 		;transmit beep
			;Check for buffer underflow (input char in [PS+0])
CF_QUERY_APPEND_7	LDY	NUMBER_TIB 			;compare char count
			CPY	TO_IN
			BLS	CF_QUERY_APPEND_4		;underflow -> beep
			LEAY	-1,Y
			STY	NUMBER_TIB
			LDD	#STRING_SYM_BACKSPACE		;replace received char by a backspace
			JOB	CF_QUERY_APPEND_6
			;Input complete
CF_QUERY_APPEND_8	LDY	PSP 				;drop char from PS
			LEAY	2,Y
			STY	PSP
			LDY	NUMBER_TIB 			;check char count
			BEQ	CF_QUERY_APPEND_9 		;command line is empty
			BSET	(TIB_START-1),Y, #$80		;terminate last character
CF_QUERY_APPEND_9	NEXT

;PARSE ( char "ccc<char>" -- c-addr u ) Parse the TIB
;Parse ccc delimited by the delimiter char. c-addr is the address (within the
;input buffer) and u is the length of the parsed string.  If the parse area was
;empty, the resulting string has a zero length.
; args:   PSP+0: delimiter char
; result: PSP+0: character count
;         PSP+1: string pointer
; SSTACK: 5 bytes
; PS:     1 cell
; RS:     none
; throws: FEXCPT_EC_PSOF
;         FEXCPT_EC_PSUF
CF_PARSE		EQU	*
			;Check PS
			PS_CHECK_UFOF	1, 1 		;new PSP -> Y
			STY	PSP
			;Get delimiter char (PSP in Y)
			LDAA	3,Y
			;Parse TIB (delimiter char in A, PSP in Y)  
			FOUTER_PARSE 			;(SSTACK: 5 bytes)
			;Pass results to PS (char count in A, string pointer in X, PSP in Y)
			STX	2,Y
			TAB
			CLRA
			STD	0,Y
			;Done
			NEXT

;>NUMBER ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 ) 
;ud2 is the unsigned result of converting the characters within the string
;specified by c-addr1 u1 into digits, using the number in BASE, and adding each
;into ud1 after multiplying ud1 by the number in BASE. Conversion continues
;left-to-right until a character that is not convertible, including any "+" or
;"-", is encountered or the string is entirely converted. c-addr2 is the
;location of the first unconverted character or the first character past the end
;of the string if the string was entirely converted. u2 is the number of
;unconverted characters in the string. If ud2 overflows during the conversion,
;both result and conversion string are left untouched.	
; args:   PSP+0: character count
;         PSP+1: string pointer
;         PSP+2: initial number
; result: PSP+0: remaining character count
;         PSP+1: pointer to unconverted substring
;         PSP+2: resulting number
; SSTACK: 18 bytes
; PS:     none
; RS:     none
; throws: FEXCPT_EC_PSUF
CF_TO_NUMBER		EQU	*
			;Check PS
			PS_CHECK_UF	4 		;PSP -> Y			
			;Check SSTACK (PSP in Y)
			SSTACK_PREPUSH	18
			;Copy parameters from PS to SSTACK (PSP in Y)
			MOVW	6,Y, 2,SP- 		;number LSW
			MOVW	4,Y, 2,SP-		;number MSW
			MOVW	2,Y, 2,SP-		;string pointer
			MOVW	0,Y, 2,SP-		;char count
			;copy BASE to SSTACK (PSP in Y)
			FOUTER_FIX_BASE
			PSHD
			;Try to convert string to number  (PSP in Y)
			FOUTER_TO_NUMBER		;(SSTACK: 8 bytes)
			BCC	CF_TO_NUMBER_1		;numeric overflow
			;Copy parameters from SSTACK to PS (PSP in Y)
			SSTACK_PREPULL	10
			MOVW	2,SP, 0,Y 		;char count
			MOVW	4,SP, 2,Y 		;string pointer
			MOVW	6,SP, 4,Y 		;number MSW
			MOVW	8,SP, 6,Y 		;number LSW
			;Clean up SSTACK
CF_TO_NUMBER_1		LEAS	10,SP
			;Done
			NEXT
	
;INTEGER ( c-addr u -- d s | n 1 | 0) Interpret string as integer
;Interpret string as integer value and return a single or double cell number
;along with the cell count. If the interpretation was unsuccessful, return a
;FALSE flag
; args:   PSP+0: char count
;         PSP+1: string pointer
; result: PSP+0: cell count
;         PSP+1: double value
; or
;         PSP+0: cell count
;         PSP+1: single value
; or
;         PSP+0: false flag
; SSTACK: 22 bytes
; PS:     1 cell
; RS:     none
; throws: FEXCPT_EC_PSOF
;         FEXCPT_EC_PSUF
CF_INTEGER		EQU	*
			;Check PS
			PS_CHECK_UFOF	2, 1 		;new PSP -> Y
			STY	PSP
			;Interpret string (PSP in Y)
			LDD	2,Y
			LDX	4,Y
			FOUTER_INTEGER			;(SSTACK: 22 bytes)
			STD	0,Y			;store cell count
			DBEQ	D, CF_INTEGER_4		;single cell
			DBNE	D, CF_INTEGER_2		;not an integer (done)
			;Double cell value (integer in Y:X) 
			TFR	Y, D
			LDY	PSP
			STD	2,Y
			STX	4,Y
			;Done
CF_INTEGER_1		NEXT
			;Not an integer 
CF_INTEGER_2		LDY	PSP
			MOVW	#$0000, 4,+Y
CF_INTEGER_3		STY	PSP
			JOB	CF_INTEGER_1 		;done
			;Single cell value (integer in X) 
CF_INTEGER_4		LDY	PSP
			MOVW	#$0001, 2,+Y
			JOB	CF_INTEGER_3

;RESUME ( -- ) IMMEDIATE
;Exit suspend mode 
;
;Throws:
;"Return stack underflow"
CF_RESUME		EQU	*
			RS_CHECK_UF	3		;RSP -> X 
			MOVW	2,X+, NEXT_PTR		;restore NEXT_PTR
			MOVW	2,X+, HANDLER		;restore HANDLER
			MOVW	2,X+, IP		;restore IP
			STX	RSP
			NEXT

;LITERAL run-time semantics
;Run-time: ( -- x )
;Place x on the stack.
;
;S12CForth implementation details:
;Throws:
;"Parameter stack overflow"
CF_LITERAL_RT		EQU	*
			PS_CHECK_OF	1		 	;check for PS overflow (PSP-new cells -> Y)
			LDX	IP				;push the value at IP onto the PS
			MOVW	2,X+ 0,Y			; and increment the IP
			STX	IP
			STY	PSP
			NEXT

;2LITERAL run-time semantics
;Run-time: ( -- d )
;Place d on the stack.
;
;S12CForth implementation details:
;Throws:
;"Parameter stack overflow"
CF_TWO_LITERAL_RT	EQU	*
			PS_CHECK_OF	2		 	;check for PS overflow (PSP-new cells -> Y)
			LDX	IP				;push the value at IP onto the PS
			MOVW	2,X+, 0,Y			; and increment the IP
			MOVW	2,X+, 2,Y			; and increment the IP
			STX	IP
			STY	PSP
			NEXT
	
FOUTER_CODE_END		EQU	*
FOUTER_CODE_END_LIN	EQU	@
	
;###############################################################################
;# Tables                                                                      #
;###############################################################################
#ifdef FOUTER_TABS_START_LIN
			ORG 	FOUTER_TABS_START, FOUTER_TABS_START_LIN
#else
			ORG 	FOUTER_TABS_START
FOUTER_TABS_START_LIN	EQU	@
#endif	

;Symbol tables
FOUTER_SYMTAB		EQU	NUM_SYMTAB
	
;System prompts
FOUTER_SUSPEND_PROMPT	FCC	"S"
FOUTER_INTERACT_PROMPT	FCS	"> "
FOUTER_NVCOMPILE_PROMPT	FCC	"NV"
FOUTER_COMPILE_PROMPT	FCS	"+ "

FOUTER_SYSTEM_ACK	FCS	" ok"

FOUTER_TREE_EOB		EQU	$00 	;end of branch
FOUTER_TREE_BI		EQU	$00 	;branch indicator
FOUTER_TREE_ES		EQU	$00 	;empty string
	
FOUTER_TABS_END		EQU	*
FOUTER_TABS_END_LIN	EQU	@

;###############################################################################
;# Words                                                                       #
;###############################################################################
#ifdef FOUTER_WORDS_START_LIN
			ORG 	FOUTER_WORDS_START, FOUTER_WORDS_START_LIN
#else
			ORG 	FOUTER_WORDS_START
FOUTER_WORDS_START_LIN	EQU	@
#endif	
			ALIGN	1
;#ANSForth Words:
;================
;Word: QUERY ( -- )
;Make the user input device the input source. Receive input into the terminal
;input buffer,mreplacing any previous contents. Make the result, whose address is
;returned by TIB, the input buffer.  Set >IN to zero.
;
;Throws:
;"Parameter stack overflow"
;"Return stack overflow"
;"Invalid RX data"
CFA_QUERY		DW	CF_QUERY

;Word: PARSE ( char "ccc<char>" -- c-addr u )
;Parse ccc delimited by the delimiter char. c-addr is the address (within the
;input buffer) and u is the length of the parsed string.  If the parse area was
;empty, the resulting string has a zero length.
;
;Throws:
;"Parameter stack overflow"
;"Parameter stack underflow"
CFA_PARSE		DW	CF_PARSE

;Word: >NUMBER ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 ) 
;ud2 is the unsigned result of converting the characters within the string
;specified by c-addr1 u1 into digits, using the number in BASE, and adding each
;into ud1 after multiplying ud1 by the number in BASE. Conversion continues
;left-to-right until a character that is not convertible, including any "+" or
;"-", is encountered or the string is entirely converted. c-addr2 is the
;location of the first unconverted character or the first character past the end
;of the string if the string was entirely converted. u2 is the number of
;unconverted characters in the string. If ud2 overflows during the conversion,
;both result and conversion string are left untouched.
;
;Throws:
;"Parameter stack underflow"
CFA_TO_NUMBER		DW	CF_TO_NUMBER
	
;Word: BASE ( -- a-addr ) 
;a-addr is the address of a cell containing the current number-conversion radix
;{{2...36}}. 
;
;Throws:
;"Parameter stack overflow"
CFA_BASE		DW	CF_CONSTANT_RT
			DW	BASE

;Word: >IN ( -- a-addr )
;a-addr is the address of a cell containing the offset in characters from the
;start of the input buffer to the start of the parse area.  
;
;Throws:
;"Parameter stack overflow"
CFA_TO_IN		DW	CF_CONSTANT_RT
			DW	TO_IN

;Word: #TIB ( -- a-addr )
;a-addr is the address of a cell containing the number of characters in the
;terminal input buffer.
;
;Throws:
;"Parameter stack overflow"
CFA_NUMBER_TIB		DW	CF_CONSTANT_RT
			DW	NUMBER_TIB

;Word: WORDS ( -- )
;List the definition names in the first word list of the search order. The
;format of the display is implementation-dependent.
;WORDS may be implemented using pictured numeric output words. Consequently, its
;use may corrupt the transient region identified by #>.
CFA_WORDS		DW	CF_INNER
			DW	CFA_WORDS_CDICT
			DW	CFA_EOW

;S12CForth Words:
;================
;Word: QUERY-APPEND ( -- )
;Set >IN to #TIB. Make the user input device the input source. Receive input into
;the terminal input buffer, appending previous contents. Make the result, whose
;address is returned by TIB+>IN, the input buffer.
;
;Throws:
;"Parameter stack overflow"
;"Return stack overflow"
;"Invalid RX data"
CFA_QUERY_APPEND	DW	CF_QUERY_APPEND
	
;Word: INTEGER ( c-addr u -- d s | n 1 | 0)
;Interpret string as integer value and return a single or double cell number
;along with the cell count. If the interpretation was unsuccessful, return a
;FALSE flag
;
;Throws:
;"Parameter stack underflow"
;"Parameter stack overflow"
CFA_INTEGER		DW	CF_INTEGER

;Word: RESUME ( -- ) IMMEDIATE
;Exit suspend mode 
;
;Throws:
;"Return stack underflow"
CFA_RESUME		DW	CF_RESUME

;Word: TIB-OFFSET ( -- a-addr )
;a-addr is the address of a cell containing the number of characters in the
;terminal input buffer.
;
;Throws:
;"Parameter stack overflow"
CFA_TIB_OFFSET		DW	CF_CONSTANT_RT
			DW	TIB_OFFSET

;LITERAL run-time semantics
;Run-time: ( -- x )
;Place x on the stack.
;
;S12CForth implementation details:
;Throws:
;"Parameter stack overflow"
CFA_LITERAL_RT		DW	CF_LITERAL_RT

;2LITERAL run-time semantics
;Run-time: ( -- x1 x2 )
;Place cell pair x1 x2 on the stack.
;
;S12CForth implementation details:
;Throws:
;"Parameter stack overflow"
CFA_TWO_LITERAL_RT	DW	CF_TWO_LITERAL_RT

FOUTER_WORDS_END	EQU	*
FOUTER_WORDS_END_LIN	EQU	@