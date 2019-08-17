# tu58v3
Improved version of tu58 emulator

This is an emulator for a DEC TU-58 block addressable tape system. 

It is wrtten in AVR assembler. 

This project has been ongoing for many years. On the back burner. A few years back
I got the rom image from a real TU-58. I disassembled and commented the code.
(It's on bitsavers) That gave me an outline for my AVR code.

The storage is a single CF card that supports multiple images of 65536 512 byte blocks.
This is far more storage than a real TU-58 could support. 

Some things are different from a real TU-58:

BLOCKS greater than 512 supported

No capstan roller to turn to goo

Boot switch not implemented

Special addressing mode not implemented.

The emulator has been tested with RT-11 and XXDP test CZTUU.

I have done a PCB layout and had prototypes run (OSHPARK)

This is an updated version of the tu-58 emulator

The processor has been changed to an ATmega32A to allow a parallel interface to the CF card.

Component count is reduced by eliminating the SPI interface.

Jumpers have been added to select baud rate.

UNIT is restricted to 0 or 1 to prevent corrupting CF card image.

JTAG programming and test connector added.

