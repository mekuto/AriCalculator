;###############################################################################
;# S12CBase - ERROR - Error Handler (LFBDMPGMR port)                           #
;###############################################################################
;#    Copyright 2010-2012 Dirk Heisswolf                                       #
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
;#    This module detects the cause of the previous system reset and prints a  #
;#    status message over the SCI interface.                                   #
;#                                                                             #
;#    The reset handler also provides routines for triggering system resets    #
;#    from software.                                                           #
;###############################################################################
;# Required Modules:                                                           #
;#    PRINT  - SCI output routines                                             #
;#    COP    - Watchdog handler                                                #
;#                                                                             #
;# Requirements to Software Using this Module:                                 #
;#    - none                                                                   #
;###############################################################################
;# Version History:                                                            #
;#    April 4, 2010                                                            #
;#      - Initial release                                                      #
;#    May 30, 2010                                                             #
;#      - Changed "Initialization failure" error to "Unknown cause" error      #
;#    June 8, 2010                                                             #
;#      - Changed checksum for error message                                   #
;#      - Fixed COP error handling                                             #
;#    July 2, 2010                                                             #
;#      - compined error messages "Unknown cause" and "Unknown error" to       #
;#        "Unknown problem"                                                    #
;#      - changed error codes                                                  #
;#    January 2, 2012                                                          #
;#      - the LFBDMPGMR bootloader only supports one reset entry               #
;#        -> either print valid error or welcome message                       #
;###############################################################################

;###############################################################################
;# Constants                                                                   #
;###############################################################################
;Severity levels
ERROR_LEVEL_INFO	EQU	(ERROR_STRINGTAB_INFO-ERROR_STRINGTAB)>>1
ERROR_LEVEL_WARNING	EQU	(ERROR_STRINGTAB_WARNING-ERROR_STRINGTAB)>>1
ERROR_LEVEL_ERROR	EQU	(ERROR_STRINGTAB_ERROR-ERROR_STRINGTAB)>>1
ERROR_LEVEL_FATAL	EQU	(ERROR_STRINGTAB_FATAL-ERROR_STRINGTAB)>>1

;#Reset entry codes -> LFBDMPGMR bootloader only supports one reset entry
;ERROR_ENTRYCODE_EXT	EQU	$00
;ERROR_ENTRYCODE_COP	EQU	$01
;ERROR_ENTRYCODE_CM	EQU	$02

;###############################################################################
;# Variables                                                                   #
;###############################################################################
			ORG	ERROR_VARS_START
ERROR_MSG		DS	2 ;Reset message to be displayed
ERROR_MSG_CHECK		DS	1 ;Checksum to determine if the reset message
;ERROR_ENTRYCODE	DS	1 ;Register to remember the entry point
ERROR_VARS_END		EQU	*

;###############################################################################
;# Macros                                                                      #
;###############################################################################
;#Reset entries -> LFBDMPGMR bootloader only supports one reset entry
;#macro	ERROR_ENTRY_EXT, 0
;			CLR	ERROR_ENTRYCODE
;			;MOVB	#ERROR_ENTRYCODE_EXT, ERROR_ENTRYCODE
;#emac	
;#macro	ERROR_ENTRY_COP, 0
;			MOVB	#ERROR_ENTRYCODE_COP, ERROR_ENTRYCODE
;#emac	
;#macro	ERROR_ENTRY_CM, 0
;			MOVB	#ERROR_ENTRYCODE_CM, ERROR_ENTRYCODE
;#emac	

;#Initialization
#macro	ERROR_INIT, 0
;			;Check entry code
;			LDAB	ERROR_ENTRYCODE
;			BEQ	ERROR_INIT_EXT
;			DECB
;			BEQ	ERROR_INIT_COP
;			DECB
;			BEQ	ERROR_INIT_CM
;			;Illegal entry code
;			BRA	ERROR_INIT_UNKNOWN ;throw fatal error
;
;			;Clock monitor reset
;ERROR_INIT_CM		LDY	#ERROR_MSG_CM 
;			ERROR_PRINT 			;print error message (SSTACK: 18 bytes)
;			JOB	ERROR_INIT_DONE

			;COP or software reset
ERROR_INIT_COP		LDD	ERROR_MSG 		;check for valid error message
			TFR	D, Y
			ABA
			COMA
			CMPA	ERROR_MSG_CHECK
;			BNE	ERROR_INIT_COP_1	;checksum is invalid
			BNE	ERROR_INIT_EXT 		;if checksum is invalid, print welcome message
			LEAX	1,Y
			PRINT_STRCNT 			;check if error message has a valid format
			CMPA	#$FF
;			BNE	ERROR_INIT_COP_2	;message is correctly terminated
			BNE	ERROR_INIT_EXT 		;if message not correctly terminated, print welcome message	
;ERROR_INIT_COP_1	LDY	#ERROR_MSG_COP		;complain ablut COP instead
ERROR_INIT_COP_2	ERROR_PRINT 			;print error message (SSTACK: 18 bytes)
			JOB	ERROR_INIT_DONE
	
			;External reset
ERROR_INIT_EXT		LDAA	CRGFLG 			;determine the cause of the external reset

			;Low voltage reset
			BITA	#LVRF 			;check for low voltage reset
			BEQ	ERROR_INIT_EXT_1	;no low voltage reset
			LDY	#ERROR_MSG_LV
			ERROR_PRINT 			;print error message (SSTACK: 18 bytes)
			JOB	ERROR_INIT_DONE

			;Power-on reset 
ERROR_INIT_EXT_1	;BITA	#PORF 			;check for power-on reset ;treat external reset as POR!
			;BEQ	ERROR_INIT_EXT_2	;no power-on reset
			LDX	#ERROR_WELCOME_STRING	;print welcome message
			PRINT_LINE_BREAK 		;print line break sequence (SSTACK:11 bytes)
			PRINT_STR 			;print string (SSTACK: 13 bytes)
			LDX	#MAIN_NAME_STRING	;print firmware name
			PRINT_STR 			;print string (SSTACK: 13 bytes)
			LDX	#MAIN_VERSION_STRING	;print firmware version
			LDAB	#" "			;print a space character
			PRINT_CHAR 			;print character (SSTACK:8 bytes)
			PRINT_STR 			;print string (SSTACK: 13 bytes)
			LDAB	#"!"			;print exclamation mark
			PRINT_CHAR 			;print character (SSTACK:8 bytes)
			;JOB	ERROR_INIT_DONE
	
			;External reset
ERROR_INIT_EXT_2	;LDY	#ERROR_MSG_EXT
			;ERROR_PRINT 			;print error message (SSTACK: 18 bytes)
			;JOB	ERROR_INIT_DONE

			;Unknown error 
;ERROR_INIT_UNKNOWN	LDY	#ERROR_MSG_UNKNOWN
;			ERROR_PRINT 			;print error message (SSTACK: 18 bytes)
;			JOB	ERROR_INIT_DONE
	
;ERROR_INIT_DONE	PRINT_WAIT			;wait until message is printed	
ERROR_INIT_DONE		MOVW	#$0000, ERROR_MSG 	;invalidate error message
			CLR	ERROR_MSG_CHECK
			PRINT_WAIT			;wait until message is printed	
#emac
	
;#Print error message
; args:   Y: pointer to the error message
; SSTACK: 18 bytes
;         X, Y, and D are preserved 
#macro	ERROR_PRINT, 0
			SSTACK_JOBSR	ERROR_PRINT
#emac

;#Perform a reset due to a fatal error
;# Args: message pointer	
#macro	ERROR_RESTART, 1
			BGND
			LDD	#\1
			JOB	ERROR_RESTART
#emac
	
;Error Message Definition
#macro	ERROR_MSG, 2
			DB	\1
			FCS	\2
#emac
	
;###############################################################################
;# Code                                                                        #
;###############################################################################
			ORG	ERROR_CODE_START

;#Print error message
; args:   Y: pointer to the error message
; SSTACK: 18 bytes
;         X, Y, and D are preserved 
ERROR_PRINT		EQU	*
			;Save registers 
			SSTACK_PSHYXB			;save registers

			;Print error level 
			LDAB	0,Y 			;read error level
			CMPB	#((ERROR_STRINGTAB_END-ERROR_STRINGTAB)>>1) ;check level
			BHS	ERROR_PRINT_1 		;invalid error level
			LDX	#ERROR_STRINGTAB
			LSLB
			LDX	B,X
			PRINT_LINE_BREAK 		;print line break sequence (SSTACK:11 bytes)
			PRINT_STR 			;print string (SSTACK: 13 bytes)
	
			;Print error message
                        LEAX	1,Y
			PRINT_STRCNT 			;chack if error message has a valid format
			CMPA	#$FF
			BEQ	ERROR_PRINT_1 		;message too long (probably not terminated)	
			PRINT_STR 			;print string (SSTACK:13 bytes)

			;Print error message
 			LDAB	#"!"	   		;print exclamation mark
			PRINT_CHAR 			;print character (SSTACK:8 bytes)
			
			;Restore registers 
			SSTACK_PULBXY			;restore registers
			SSTACK_RTS

			;Throw a fatal error
ERROR_PRINT_1		ERROR_RESTART	ERROR_MSG_UNKNOWN		
	
;#Perform a reset due to a fatal error
;# Args: D: message pointer	
ERROR_RESTART		EQU	*
			STD	ERROR_MSG 	;save error message
			ABA			;calculate checksum
			COMA	
			STAA	ERROR_MSG_CHECK	;save checksum
			COP_RESET

;#Trigger a fatal error if a reset accurs
ERROR_ISR		EQU	*
			LDD	#ERROR_MSG_UEXPIRQ	;Unexpected interrupt
			JOB	ERROR_RESTART

ERROR_CODE_END		EQU	*	

;###############################################################################
;# Tables                                                                      #
;###############################################################################
			ORG	ERROR_TABS_START
;#Error strings
ERROR_STRING_INFO	FCS	"Info! "
ERROR_STRING_WARNING	FCS	"Warning! "
ERROR_STRING_ERROR	FCS	"Error! "
ERROR_STRING_FATAL	FCS	"Fatal Error! "

;#Error string table
ERROR_STRINGTAB		EQU	*
ERROR_STRINGTAB_INFO	DW	ERROR_STRING_INFO
ERROR_STRINGTAB_WARNING	DW	ERROR_STRING_WARNING
ERROR_STRINGTAB_ERROR	DW	ERROR_STRING_ERROR
ERROR_STRINGTAB_FATAL	DW	ERROR_STRING_FATAL
ERROR_STRINGTAB_END	EQU	*

;#Welcome strings
ERROR_WELCOME_STRING	FCS	"Hello, this is "

;#Error messages
;ERROR_MSG_SOFT		ERROR_MSG	ERROR_LEVEL_INFO,  "Software reset"
;ERROR_MSG_COP		ERROR_MSG	ERROR_LEVEL_FATAL, "Watchdog timeout"
;ERROR_MSG_CM		ERROR_MSG	ERROR_LEVEL_FATAL, "Clock failure"
ERROR_MSG_LV		ERROR_MSG	ERROR_LEVEL_FATAL, "Power failure"
;ERROR_MSG_UNKNOWN	ERROR_MSG	ERROR_LEVEL_FATAL, "Unknown problem"
ERROR_MSG_UEXPIRQ	ERROR_MSG	ERROR_LEVEL_FATAL, "Unexpected interrupt"
;ERROR_MSG_EXT		ERROR_MSG	ERROR_LEVEL_INFO,  "External reset"
	
ERROR_TABS_END		EQU	*