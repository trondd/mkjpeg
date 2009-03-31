do compile.do

vsim -t ps -lib WORK JPEG_TB -novopt

#mem load -infile header.hex -format hex /JPEG_TB/U_JpegEnc/U_JFIFGen/U_Header_RAM

do wave.do
radix hex

run 1 us


