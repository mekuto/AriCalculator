#!/usr/bin/env perl
###############################################################################
# AriCalculator - Image Converter                                             #
###############################################################################
#    Copyright 2012 - 2014 Dirk Heisswolf                                     #
#    This file is part of the AriCalculator framework for NXP's S12(X) MCU    #
#    families.                                                                #
#                                                                             #
#    AriCalculator is free software: you can redistribute it and/or modify    #
#    it under the terms of the GNU General Public License as published by     #
#    the Free Software Foundation, either version 3 of the License, or        #
#    (at your option) any later version.                                      #
#                                                                             #
#    AriCalculator is distributed in the hope that it will be useful,         #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#    GNU General Public License for more details.                             #
#                                                                             #
#    You should have received a copy of the GNU General Public License        #
#    along with AriCalculator.  If not, see <http://www.gnu.org/licenses/>.   #
###############################################################################
# Description:                                                                #
#    This perl script converts a 128x64 8-bit grascale raw image into a       #
#    stream for a ST7565R display controller. The palette of the image must   #
#    be sorted from dark to light                                             #
###############################################################################
# Version History:                                                            #
#    25 April, 2009                                                           #
#      - Initial release                                                      #
#     7 August, 2012                                                          #
#      - Added script to AriCalculator tools                                  #
#     12 August, 2014                                                         #
#      - Added workaround for stange raw image format generated by Gimp 2.8   #
###############################################################################

#################
# Perl settings #
#################
use 5.005;
#use warnings;
use IO::File;

#############
# constants #
#############
$escape_char       =  0xe3;

###############
# global vars #
###############
$src_file          = "";
$src_handle        =  0;
@src_buffer        = ();
$pixel             =  0;
$color             =  0;
$color_depth       =  0;
@split_buffer      = ();
$column_group      =  0;
$column            =  0;
$page              =  0;
@paged_buffer      = ();
@out_buffer        = ();
$out_file          = "";
$out_handle        =  0;
$repeat_count      =  0;
$current_data      = undef;
$next_data         = undef;

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
@months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
@days   = ("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat");

###################
# print help text #
###################
if ($#ARGV < 0) {
    printf "usage: %s <raw image file>\n", $0;
    print  "\n";
    exit;
}

##################
# read file name #
##################
$src_file = $ARGV[0];
printf STDOUT ("Processing image file \"%s\"\n", $src_file);

###################
# open image file #
###################
#check if file exists
if (! -e $src_file) {
    printf STDOUT ("    ERROR! File \"%s\" does not exist\n", $src_file);
    exit;
} 
#check if file is readable
if (! -r $src_file) {
    printf STDOUT "    ERROR! File \"%s\" is not readable\n", $src_file;
    exit;
}
#check if file can be opened
if ($src_handle = IO::File->new($src_file, O_RDONLY)) {
} else {
    printf STDOUT "    ERROR! Unable to open file \"%s\" (%s)\n", $src_file, $!;
    exit;
}

#read file
$src_handle->seek(0, SEEK_SET);      #reset file handle pointer
$color_depth = 0;
$pixel_offset = 0;
while ($src_handle->read($pixel, 1)) {
    $pixel = unpack("C", $pixel);
    if ($pixel < 64) {            #Gimp 2.8 dumps 16 bit pixel values (every other byte being 0xFF) -> discard
	if ($pixel_offset  > 0) { #Gimp 2.8 dumps addidional data at the beginning of the file      -> discard
	    $pixel_offset--;
	} else {
	    if ($pixel > $color_depth) {
		$color_depth = $pixel
	    }
	    push @src_buffer, $pixel;
	    #printf STDOUT "Pixel(%4d): %x\n",  $#src_buffer, $pixel;
	}
    }
}
$src_handle->close();                           #close file handle

#check image format
    if ($#src_buffer != (128*64)-1) {
    printf STDOUT "    ERROR! Wrong image format (%d pixels)\n", $#src_buffer+1;
    exit;
}
#printf STDOUT "Color depth: %d\n", $color_depth;

#for $y (0..64) {
#    for $x (0..127) {
#	$px = $src_buffer[$x+(128*$y)];
#	if ($px == 0) {print STDOUT "#";}
#	if ($px == 1) {print STDOUT "*";}
#	if ($px == 2) {print STDOUT ".";}
#	if ($px >  2) {print STDOUT " ";}
#    }
#    print STDOUT "\n"
#}

#####################
# convert image file #
######################
#split source buffer into gray shades
@split_buffer = ();
foreach $color (0..$color_depth-1) {
    foreach $pixel (@src_buffer) {       #not flipped
    #foreach $pixel (reverse(@src_buffer)) { #flipped
	if ($pixel <= $color) {
	    push @split_buffer, 0xFF;
	} else {
	    push @split_buffer, 0x00;
	}
	#printf STDOUT "Color: %4d Index: %6d Pixel: %4d => %.2X\n", $color, $#split_buffer, $pixel, $split_buffer[$#split_buffer]; 
    }
}
#printf STDOUT "Splitted image: %d\n", $#split_buffer+1;

#arrange split buffer into pages
@paged_buffer = ();
foreach $page (0..(($#split_buffer+1)/(128*8))-1) {
    foreach $column (0..127) {
	#printf STDOUT "Page: %4d Column: %4d %2X %2X %2X %2X %2X %2X %2X %2X\n", $page, $column, 
	#($split_buffer[($page*(128*8))+$column+(128*0)]),
	#($split_buffer[($page*(128*8))+$column+(128*1)]),
	#($split_buffer[($page*(128*8))+$column+(128*2)]),
	#($split_buffer[($page*(128*8))+$column+(128*3)]),
	#($split_buffer[($page*(128*8))+$column+(128*4)]),
	#($split_buffer[($page*(128*8))+$column+(128*5)]),
	#($split_buffer[($page*(128*8))+$column+(128*6)]),
	#($split_buffer[($page*(128*8))+$column+(128*7)]);
	 push @paged_buffer, (($split_buffer[($page*(128*8))+$column+(128*0)]& 0x01) |
			      ($split_buffer[($page*(128*8))+$column+(128*1)]& 0x02) |
			      ($split_buffer[($page*(128*8))+$column+(128*2)]& 0x04) |
			      ($split_buffer[($page*(128*8))+$column+(128*3)]& 0x08) |
			      ($split_buffer[($page*(128*8))+$column+(128*4)]& 0x10) |
			      ($split_buffer[($page*(128*8))+$column+(128*5)]& 0x20) |
			      ($split_buffer[($page*(128*8))+$column+(128*6)]& 0x40) |
			      ($split_buffer[($page*(128*8))+$column+(128*7)]& 0x80));
    }
}
#printf STDOUT "Paged image: %d\n", $#paged_buffer+1;

##################
# write ASM file #
##################
#determine output file name
if ($src_file =~ /^(.+)\.raw$/i) {
    $out_file = sprintf("%s.s", $1);
} else {
    $out_file = sprintf("%s.s", $src_file);
}

#open output file
if ($out_handle = IO::File->new($out_file,  O_CREAT|O_WRONLY)) {
    $out_handle->truncate(0);
} else {
    printf STDOUT "    ERROR! Unable to open file \"%s\" (%s)\n", $out_file, $!;
    exit;
}

#print header
printf $out_handle "#ifndef\tDISP_SPLASH\n";
printf $out_handle "#define\tDISP_SPLASH\n";
printf $out_handle ";###############################################################################\n"; 
if ($color_depth == 1) {
    printf $out_handle ";# AriCalculator - Image: %-50s   #\n", sprintf("%s (single frame)", $src_file);
} else {
    printf $out_handle ";# AriCalculator - Image: %-50s   #\n", sprintf("%s (%d frames)", $src_file, $color_depth);
}
printf $out_handle ";###############################################################################\n";
printf $out_handle ";#    Copyright 2012 - %4d Dirk Heisswolf                                     #\n", $year;
printf $out_handle ";#    This file is part of the AriCalculator framework for NXP's S12(X) MCU    #\n";
printf $out_handle ";#    families.                                                                #\n";
printf $out_handle ";#                                                                             #\n";
printf $out_handle ";#    AriCalculator is free software: you can redistribute it and/or modify    #\n";
printf $out_handle ";#    it under the terms of the GNU General Public License as published by     #\n";
printf $out_handle ";#    the Free Software Foundation, either version 3 of the License, or        #\n";
printf $out_handle ";#    (at your option) any later version.                                      #\n";
printf $out_handle ";#                                                                             #\n";
printf $out_handle ";#    AriCalculator is distributed in the hope that it will be useful,         #\n";
printf $out_handle ";#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #\n";
printf $out_handle ";#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #\n";
printf $out_handle ";#    GNU General Public License for more details.                             #\n";
printf $out_handle ";#                                                                             #\n";
printf $out_handle ";#    You should have received a copy of the GNU General Public License        #\n";
printf $out_handle ";#    along with AriCalculator.  If not, see <http://www.gnu.org/licenses/>.   #\n";
printf $out_handle ";###############################################################################\n";
printf $out_handle ";# Description:                                                                #\n";
printf $out_handle ";#    This file contains the two macros:                                       #\n";
printf $out_handle ";#       DISP_SPLASH_TAB:                                                      #\n";
printf $out_handle ";#           This macro allocates a table of raw image data.                   #\n";
printf $out_handle ";#                                                                             #\n";
printf $out_handle ";#       DISP_SPLASH_STREAM:                                                   #\n";
printf $out_handle ";#           This macro allocates a compressed stream of image data and        #\n";
printf $out_handle ";#           control commands, which can be directly driven to the display     #\n";
printf $out_handle ";#           driver.                                                           #\n";
printf $out_handle ";###############################################################################\n";
printf $out_handle ";# Generated on %3s, %3s %.2d %4d                                               #\n", $days[$wday], $months[$mon], $mday, $year;
printf $out_handle ";###############################################################################\n";
printf $out_handle "\n";

#Print image 
print $out_handle ";+--------------------------------------------------------------------------------------------------------------------------------+\n";
for my $row (0..63) {
    print $out_handle ";|";
    for my $column (0..127) {
	my $pixel = int(($src_buffer[$column+(128*$row)] * 8)/$color_depth);
	#print $out_handle $pixel;	
	if ($pixel == 0) {print $out_handle "#";}
	if ($pixel == 1) {print $out_handle "@";}
	if ($pixel == 2) {print $out_handle "%";}
	if ($pixel == 3) {print $out_handle "+";}
	if ($pixel == 4) {print $out_handle "*";}
	if ($pixel == 5) {print $out_handle "-";}
	if ($pixel == 6) {print $out_handle ":";}
	if ($pixel == 7) {print $out_handle ".";}
	if ($pixel >  7) {print $out_handle " ";}
    }
    print $out_handle "|\n"
}
print $out_handle ";+--------------------------------------------------------------------------------------------------------------------------------+\n\n";

#write data table 
@out_buffer = @paged_buffer;

printf $out_handle "#macro DISP_SPLASH_TAB, 0\n";
printf $out_handle "\n";

foreach $color (0..$color_depth-1) {
    printf $out_handle ";#Frame %d:\n", $color;
    printf $out_handle ";#----------------------------------------------------------------------\n";
    foreach $page (0..7) {
	printf $out_handle ";#Page %d:\n", $page;
	foreach $column_group (0..15) {
	    printf $out_handle "\t\tDB";
	    foreach $column (0..7) {
		printf $out_handle "  \$%.2X", shift @out_buffer;
	    }  
	    printf $out_handle "\n";
	}    
    }
    printf $out_handle "\n";
}
printf $out_handle "#emac\n";
printf $out_handle ";Size = %d bytes\n", $#paged_buffer+1;
printf $out_handle "\n";

#write command stream 
@out_buffer = @paged_buffer;
#printf STDOUT "Out Buffer: %4d\n", $#out_buffer; 

printf $out_handle "#macro DISP_SPLASH_STREAM, 0\n";
printf $out_handle "\n";

$stream_count = 0;
foreach $color (0..$color_depth-1) {
    printf $out_handle ";#Frame %d:\n", $color;
    printf $out_handle ";#----------------------------------------------------------------------\n";

    foreach $page (0..7) {
	#printf STDERR ";#Page %d:\n", $page;
	printf $out_handle ";#Page %d:\n", $page;
	printf $out_handle "\t\tDB  \$B%.1X \$10 \$00                     ;set page and column address\n", ($page & 0xF);
	#printf $out_handle "\t\tDB  \$B%.1X \$10 \$04                    ;set page and column address\n", ($page & 0xF);
	printf $out_handle "\t\tDB  DISP_ESC_START DISP_ESC_DATA    ;switch to data input";
	$stream_count += 5;
	$column_group = 8;
	$repeat_count = 1;
	$current_data = shift @out_buffer;	
	foreach $column (0..127) {
	    if ($column       <  127) {
		$next_data = shift @out_buffer; #don't fetch from next page
	    }
	    if (($column       <  127)      &&
		($current_data == $next_data)) {
		$repeat_count++;
		#printf STDERR "## data: %X repeat%d \n", $current_data, $repeat_count; 
	    } else {
		#printf STDERR "### data: %X repeat%d \n", $current_data, $repeat_count; 
		if ( ($repeat_count >  3) ||
                    (($repeat_count >= 2) && ($current_data == $escape_char))) {
		    printf $out_handle "\n\t\tDB  DISP_ESC_START \$%.2X \$%.2X          ;repeat %d times", ($repeat_count-1), 
		                                                                                            $current_data, 
                                                                                                            $repeat_count;
		    $stream_count += 3;		
		    $column_group =  8;
		    $repeat_count =  1;
		} elsif ($current_data == $escape_char) {
		    printf $out_handle "\n\t\tDB  DISP_ESC_START DISP_ESC_ESC     ;escape \$%.2X", $escape_char;
		    $stream_count += 2;		
		    $column_group =  8;
		    $repeat_count =  1;
		} else {
		    foreach my $double_count (1..$repeat_count) {
			if (++$column_group >= 8) {
			    $column_group = 0;
			    printf $out_handle "\n\t\tDB ";
			}
			printf $out_handle " \$%.2X", $current_data;
			$stream_count += 1;
			$repeat_count =  1;
		    }		
		}
		$current_data = $next_data;
	    }
	}	
	printf $out_handle "\n\t\tDB  DISP_ESC_START DISP_ESC_CMD     ;switch to command input\n";
	$stream_count += 3;
    }
}
printf $out_handle "#emac\n";
printf $out_handle ";Size = %d bytes\n", $stream_count;
printf $out_handle "#endif\n";

#close file
$out_handle->close();

1;
