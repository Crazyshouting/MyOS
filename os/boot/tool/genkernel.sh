CPATH=/home/zzx/project/MyOS/MyOS/os/boot/kernel
gcc -c $CPATH/main.c -o $CPATH/main.o && ld $CPATH/main.o -Ttext 0xc0001500 -e main -o $CPATH/kernel.bin
