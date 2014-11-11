EESchema Schematic File Version 2
LIBS:AriCalculator
LIBS:AriCalculator-RevC-cache
EELAYER 27 0
EELAYER END
$Descr User 8268 5827
encoding utf-8
Sheet 1 6
Title "AriCalulator"
Date "4 dec 2014"
Rev "RevC"
Comp "Dirk Heisswolf"
Comment1 ""
Comment2 ""
Comment3 ""
Comment4 ""
$EndDescr
Wire Notes Line
	-26200 -93450 -30750 -93450
NoConn ~ -23300 -9850
$Sheet
S 1300 2700 1600 1200
U 544A6FCE
F0 "Supply" 50
F1 "AriCalculator-RevC-Supply.sch" 50
$EndSheet
$Sheet
S 5400 2400 1550 1500
U 544A66C8
F0 "Keypad" 50
F1 "AriCalculator-RevC-Keypad.sch" 50
F2 "KEYPAD_ROW_F" O L 5400 3300 60 
F3 "KEYPAD_ROW_E" O L 5400 3400 60 
F4 "KEYPAD_ROW_D" O L 5400 3500 60 
F5 "KEYPAD_ROW_C" O L 5400 3600 60 
F6 "KEYPAD_ROW_B" O L 5400 3700 60 
F7 "KEYPAD_ROW_A" O L 5400 3800 60 
F8 "KEYPAD_COL_0" T L 5400 3000 60 
F9 "KEYPAD_COL_1" T L 5400 2900 60 
F10 "KEYPAD_COL_2" T L 5400 2800 60 
F11 "KEYPAD_COL_3" T L 5400 2700 60 
F12 "KEYPAD_COL_4" B L 5400 2600 60 
F13 "KEYPAD_ROW_G" O L 5400 3200 60 
F14 "KEYPAD_COL_5" B L 5400 2500 60 
$EndSheet
$Sheet
S 5400 1400 1600 700 
U 544A65A6
F0 "Display" 50
F1 "AriCalculator-RevC-Display.sch" 50
F2 "DISPLAY_BACKLIGHT" I L 5400 2000 60 
F3 "DISPLAY_SS" I L 5400 1700 60 
F4 "DISPLAY_SCK" I L 5400 1600 60 
F5 "DISPLAY_A0" I L 5400 1800 60 
F6 "DISPLAY_RESET" I L 5400 1900 60 
F7 "DISPLAY_MOSI" I L 5400 1500 60 
$EndSheet
$Sheet
S 1300 1400 1600 1000
U 544A6636
F0 "UART" 50
F1 "AriCalculator-RevC-UART.sch" 50
F2 "UART_CTS" I R 2900 2050 60 
F3 "UART_RTS" O R 2900 2150 60 
F4 "UART_RXD" O R 2900 1950 60 
F5 "UART_TXD" I R 2900 1850 60 
F6 "VUSB_SENSE" U R 2900 1650 60 
$EndSheet
Wire Wire Line
	4950 2500 5400 2500
Wire Wire Line
	4950 2600 5400 2600
Wire Wire Line
	4950 2700 5400 2700
Wire Wire Line
	4950 2800 5400 2800
Wire Wire Line
	4950 2900 5400 2900
Wire Wire Line
	4950 3300 5400 3300
Wire Wire Line
	4950 3400 5400 3400
Wire Wire Line
	4950 3500 5400 3500
Wire Wire Line
	4950 3600 5400 3600
Wire Wire Line
	4950 2000 5400 2000
Wire Wire Line
	4950 1900 5400 1900
Wire Wire Line
	4950 1800 5400 1800
Wire Wire Line
	4950 1700 5400 1700
Wire Wire Line
	4950 1600 5400 1600
Wire Wire Line
	4950 1500 5400 1500
Wire Wire Line
	2900 1850 3350 1850
Wire Wire Line
	2900 1950 3350 1950
Wire Wire Line
	2900 2050 3350 2050
$Sheet
S 3350 1400 1600 2500
U 544A64C5
F0 "MCU" 50
F1 "AriCalculator-RevC-MCU.sch" 50
F2 "KEYPAD_COL_0" T R 4950 3000 60 
F3 "KEYPAD_COL_1" T R 4950 2900 60 
F4 "KEYPAD_COL_2" T R 4950 2800 60 
F5 "KEYPAD_COL_3" T R 4950 2700 60 
F6 "KEYPAD_COL_4" T R 4950 2600 60 
F7 "KEYPAD_ROW_A" I R 4950 3800 60 
F8 "KEYPAD_ROW_B" I R 4950 3700 60 
F9 "KEYPAD_ROW_C" I R 4950 3600 60 
F10 "KEYPAD_ROW_D" I R 4950 3500 60 
F11 "KEYPAD_ROW_E" I R 4950 3400 60 
F12 "KEYPAD_ROW_F" I R 4950 3300 60 
F13 "UART_CTS" O L 3350 2050 60 
F14 "DISPLAY_BACKLIGHT" O R 4950 2000 60 
F15 "UART_RTS" I L 3350 2150 60 
F16 "UART_TXD" O L 3350 1850 60 
F17 "UART_RXD" I L 3350 1950 60 
F18 "DISPLAY_SS" O R 4950 1700 60 
F19 "DISPLAY_SCK" O R 4950 1600 60 
F20 "DISPLAY_MOSI" O R 4950 1500 60 
F21 "DISPLAY_A0" O R 4950 1800 60 
F22 "DISPLAY_RESET" O R 4950 1900 60 
F23 "KEYPAD_COL_5" B R 4950 2500 60 
F24 "KEYPAD_ROW_G" I R 4950 3200 60 
F25 "VUSB_SENSE" U L 3350 1650 60 
$EndSheet
Wire Wire Line
	4950 3800 5400 3800
Wire Wire Line
	4950 3700 5400 3700
Wire Wire Line
	4950 3000 5400 3000
Wire Wire Line
	4950 3200 5400 3200
Wire Wire Line
	2900 2150 3350 2150
Wire Wire Line
	2900 1650 3350 1650
$EndSCHEMATC