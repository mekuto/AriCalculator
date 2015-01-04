;###############################################################################
;# AriCalculator - Demo                                                        #
;###############################################################################
;#    Copyright 2010-2014 Dirk Heisswolf                                       #
;#    This file is part of the S12CBase framework for Freescale's S12C MCU     #
;#    family.                                                                  #
;#                                                                             #
;#    S12CBase is free software: you can redistribute it and/or modify         #
;#    it under the terms of the GNU General Public License as published by     #
;#    the Free Software Foundation, either version 3 of the License, or        #
;#    (at your option) any later version.                                      #
;#                                                                             #
;#    S12CBase is distributed in the hope that it will be useful,              #
;#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
;#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
;#    GNU General Public License for more details.                             #
;#                                                                             #
;#    You should have received a copy of the GNU General Public License        #
;#    along with S12CBase.  If not, see <http://www.gnu.org/licenses/>.        #
;###############################################################################
;# Description:                                                                #
;#    This demo application transmits each byte it receives via the SCI.       #
;#                                                                             #
;# Usage:                                                                      #
;#    1. Upload S-Record                                                       #
;#    2. Execute code at address "START_OF_CODE"                               #
;###############################################################################
;# Version History:                                                            #
;#    August 18, 2014                                                          #
;#      - Initial release                                                      #
;###############################################################################

;###############################################################################
;# Configuration                                                               #
;###############################################################################
;# LRE or flash
#ifndef DEMO_LRE
#ifndef DEMO_FLASH
DEMO_LRE		EQU	1 		;default is LRE
#endif
#endif

;# Clocks
CLOCK_CPMU		EQU	1		;CPMU
CLOCK_IRC		EQU	1		;use IRC
CLOCK_OSC_FREQ		EQU	 1000000	; 1 MHz IRC frequency
CLOCK_BUS_FREQ		EQU	25000000	; 25 MHz bus frequency
CLOCK_REF_FREQ		EQU	 1000000	; 1 MHz reference clock frequency
CLOCK_VCOFRQ		EQU	$1		; 10 MHz VCO frequency
CLOCK_REFFRQ		EQU	$0		;  1 MHz reference clock frequency

;# Memory map:
MMAP_S12G128		EQU	1 		;S12G128
#ifdef DEMO_LRE
MMAP_RAM		EQU	1 		;use RAM memory map
#else
MMAP_FLASH		EQU	1 		;use FLASH memory map
#endif
	
;# Interrupt stack
ISTACK_LEVELS		EQU	1	 	;interrupt nesting not guaranteed
;ISTACK_DEBUG		EQU	1 		;don't enter wait mode

;# Subroutine stack
SSTACK_DEPTH		EQU	27	 	;no interrupt nesting
;SSTACK_DEBUG		EQU	1 		;debug behavior

;# COP
;COP_DEBUG		EQU	1 		;disable COP

;# RESET
RESET_WELCOME		EQU	DEMO_WELCOME 	;welcome message
	
;# Vector table
;VECTAB_DEBUG		EQU	1 		;multiple dummy ISRs
	
;# SCI
SCI_FC_RTSCTS		EQU	1 		;RTS/CTS flow control
SCI_RTS_PORT		EQU	PTM 		;PTM
SCI_RTS_PIN		EQU	PM0		;PM0
SCI_CTS_PORT		EQU	PTM 		;PTM
SCI_CTS_PIN		EQU	PM1		;PM1
SCI_HANDLE_BREAK	EQU	1		;react to BREAK symbol
SCI_HANDLE_SUSPEND	EQU	1		;react to SUSPEND symbol
SCI_BD_ON		EQU	1 		;use baud rate detection
SCI_BD_TIM		EQU	1 		;TIM
SCI_BD_ICPE		EQU	0		;IC0
SCI_BD_ICNE		EQU	1		;IC1			
SCI_BD_OC		EQU	2		;OC2			
SCI_BD_LOG_ON		EQU	1		;log captured BD pulses			
SCI_DLY_OC		EQU	3		;OC3
SCI_ERRSIG_ON		EQU	1 		;signal errors
SCI_BLOCKING_ON		EQU	1		;enable blocking subroutines
	
;# STRING
STRING_FILL_ON		EQU	1 		;STRING_FILL_BL/STRING_FILL_NB enabled
	
;###############################################################################
;# Resource mapping                                                            #
;###############################################################################
			ORG	MMAP_RAM_START, MMAP_RAM_START 
#ifdef DEMO_LRE
;Code
DEMO_CODE_START		EQU	*
DEMO_CODE_START_LIN	EQU	@
			ORG	DEMO_CODE_END, 	DEMO_CODE_END_LIN

;Tables
DEMO_TABS_START		EQU	*
DEMO_TABS_START_LIN	EQU	@
			ORG	DEMO_TABS_END, 	DEMO_TABS_END_LIN
#endif
	
;Variables
DEMO_VARS_START		EQU	*
DEMO_VARS_START_LIN	EQU	@
			ORG	DEMO_VARS_END, 	DEMO_VARS_END_LIN

#ifndef DEMO_LRE
			ORG	$E000, $3E000
;Code
DEMO_CODE_START		EQU	*
DEMO_CODE_START_LIN	EQU	@
			ORG	DEMO_CODE_END, 	DEMO_CODE_END_LIN

;Tables
DEMO_TABS_START		EQU	*
DEMO_TABS_START_LIN	EQU	@
			ORG	DEMO_TABS_END, 	DEMO_TABS_END_LIN

			ALIGN 	7, $FF ;align to D-Bug12XZ programming granularity
#endif

;###############################################################################
;# Variables                                                                   #
;###############################################################################
#ifdef DEMO_VARS_START_LIN
			ORG 	DEMO_VARS_START, DEMO_VARS_START_LIN
#else
			ORG 	DEMO_VARS_START
#endif	

DEMO_KEY_CODE		DS	1 	;pushed key stroke
DEMO_PAGE   		DS	1	;current display page
DEMO_COL    		DS	1	;current key pad ccolumn
DEMO_CUR_KEY 		DS	1	;current key code
	
BASE_VARS_START		EQU	*
BASE_VARS_START_LIN	EQU	@
			ORG	BASE_VARS_END, 	BASE_VARS_END_LIN

DISP_VARS_START		EQU	*
DISP_VARS_START_LIN	EQU	@
			ORG	DISP_VARS_END, 	DISP_VARS_END_LIN

KEYS_VARS_START		EQU	*
KEYS_VARS_START_LIN	EQU	@
			ORG	KEYS_VARS_END, 	KEYS_VARS_END_LIN
	
DEMO_VARS_END		EQU	*
DEMO_VARS_END_LIN	EQU	@
	
;###############################################################################
;# Macros                                                                      #
;###############################################################################
;Break handler
#macro	SCI_BREAK_ACTION, 0
			LED_BUSY_ON
#emac
	
;Suspend handler
#macro	SCI_SUSPEND_ACTION, 0
			LED_BUSY_OFF
#emac

;###############################################################################
;# Code                                                                        #
;###############################################################################
#ifdef DEMO_CODE_START_LIN
			ORG 	DEMO_CODE_START, DEMO_CODE_START_LIN
#else
			ORG 	DEMO_CODE_START
#endif	

;Application code
START_OF_CODE		EQU	*		;Start of code

			;Initialization
			BASE_INIT
			DISP_INIT
			KEYS_INIT

DEMO_LOOP		;Wait for key stroke
			KEYS_GET_BL 		;key code -> A
			STAA	DEMO_KEY_CODE

			;Print key code (key code in A)
			LDX	#DEMO_PRINT_HEADER 		;print header
			STRING_PRINT_BL
			LDY	#$0000 				;reverse digits
			TFR	A, X
			LDAB	#16 				;set base
			NUM_REVERSE
			NUM_REVPRINT_BL
			NUM_CLEAN_REVERSE

			;Display keystroke
			;Initialize variables
			MOVB	#$B0, DEMO_PAGE
			CLR	DEMO_COL
			CLR	DEMO_CUR_KEY

			;Draw empty line
			JOBSR	DEMO_NEW_PAGE
			JOBSR	DEMO_BLANK_PAGE

			;Draw next line
DEMO_1			JOBSR	DEMO_MARGIN
			JOBSR	DEMO_NEW_PAGE
			CLR	DEMO_COL

			;Draw next box
DEMO_2 			LDAA	DEMO_CUR_KEY
			CMPA	DEMO_KEY_CODE
			BEQ	DEMO_3 			;draw black box
			JOBSR	DEMO_WHITE_BOX
			JOB	DEMO_4
DEMO_3 			JOBSR	DEMO_BLACK_BOX

			;Switch to next key code
DEMO_4			INC	DEMO_CUR_KEY
			INC	DEMO_COL
			LDAA	#5
			CMPA	DEMO_COL	
			BNE	DEMO_2 			;draw next box
			
			;Switch to next page
			LDAA	#$B7
			CMPA	DEMO_PAGE
			BNE	DEMO_1 			;draw next line
			
			;Draw empty line
			JOBSR	DEMO_MARGIN
			JOBSR	DEMO_NEW_PAGE
			JOBSR	DEMO_BLANK_PAGE
			JOBSR	DEMO_MARGIN

			JOB	DEMO_LOOP
	
			;Start new page 
DEMO_NEW_PAGE		DISP_STREAM_FROM_TO_BL	DEMO_CMD_START, DEMO_CMD_END ;switch to command mode
			LDAB	DEMO_PAGE	
			DISP_TX_BL
			INCB
			STAB	DEMO_PAGE
			DISP_STREAM_FROM_TO_BL	DEMO_NEW_PAGE_START, DEMO_NEW_PAGE_END
			RTS

			;Blank page
DEMO_BLANK_PAGE		DISP_STREAM_FROM_TO_BL	DEMO_BLANK_PAGE_START, DEMO_BLANK_PAGE_END
			RTS

			;Margin
DEMO_MARGIN		DISP_STREAM_FROM_TO_BL	DEMO_MARGIN_START, DEMO_MARGIN_END
			RTS

			;Draw a white box
DEMO_WHITE_BOX		DISP_STREAM_FROM_TO_BL	DEMO_WHITE_BOX_START, DEMO_WHITE_BOX_END
			RTS

			;Draw a black box
DEMO_BLACK_BOX		DISP_STREAM_FROM_TO_BL	DEMO_BLACK_BOX_START, DEMO_BLACK_BOX_END
			RTS
	
BASE_CODE_START		EQU	*
BASE_CODE_START_LIN	EQU	@
			ORG	BASE_CODE_END, 	BASE_CODE_END_LIN

DISP_CODE_START		EQU	*
DISP_CODE_START_LIN	EQU	@
			ORG	DISP_CODE_END, 	DISP_CODE_END_LIN

KEYS_CODE_START		EQU	*
KEYS_CODE_START_LIN	EQU	@
			ORG	KEYS_CODE_END, 	KEYS_CODE_END_LIN

DEMO_CODE_END		EQU	*
DEMO_CODE_END_LIN	EQU	@

;###############################################################################
;# Tables                                                                      #
;###############################################################################
#ifdef DEMO_TABS_START_LIN
			ORG 	DEMO_TABS_START, DEMO_TABS_START_LIN
#else
			ORG 	DEMO_TABS_START
#endif	

DEMO_CMD_START		DB	DISP_ESC_START DISP_ESC_CMD
DEMO_CMD_END		EQU	*

DEMO_NEW_PAGE_START	DB	$10 $04
			DB	DISP_ESC_START DISP_ESC_DATA
			DB      DISP_ESC_START $10 $00
DEMO_NEW_PAGE_END	EQU	*
	
DEMO_BLANK_PAGE_START	DB      DISP_ESC_START 40 $00
DEMO_BLANK_PAGE_END	EQU	*
	
DEMO_MARGIN_START	DB      DISP_ESC_START $0C $00
DEMO_MARGIN_END	EQU	*
	
DEMO_WHITE_BOX_START	DB	$00 $7E DISP_ESC_START $04 $42 $7E $00
DEMO_WHITE_BOX_END	EQU	*

DEMO_BLACK_BOX_START	DB	$00 DISP_ESC_START $06 $7E $00
DEMO_BLACK_BOX_END	EQU	*
	
DEMO_PRINT_HEADER	STRING_NL_NONTERM
			FCS	"Key code: "

DEMO_WELCOME		FCC	"This is the AriCalculator Demo"
			STRING_NL_TERM
	
BASE_TABS_START		EQU	*
BASE_TABS_START_LIN	EQU	@
			ORG	BASE_TABS_END, 	BASE_TABS_END_LIN

DISP_TABS_START		EQU	*
DISP_TABS_START_LIN	EQU	@
			ORG	DISP_TABS_END, 	DISP_TABS_END_LIN

KEYS_TABS_START		EQU	*
KEYS_TABS_START_LIN	EQU	@
			ORG	KEYS_TABS_END, 	KEYS_TABS_END_LIN

DEMO_TABS_END		EQU	*
DEMO_TABS_END_LIN	EQU	@

;###############################################################################
;# Includes                                                                    #
;###############################################################################
#include ./gpio_AriCalculator.s	   									;I/O setup
#include ./disp_splash.s										;Splash screen image
#include ./disp_AriCalculator.s										;Display driver
#include ./keys_AriCalculator.s										;keypad driver
#include ./vectab_AriCalculator.s									;Vector table
#include ../../../Subprojects/S12CForth/Subprojects/S12CBase/Source/S12G-Micro-EVB/base_S12G-Micro-EVB.s;S12CBase framework
	
