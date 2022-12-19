CPATH=/home/zzx/project/MyOS/MyOS/os/boot/kernel
gcc -m32 -I ./lib/kernel/ -c kernel/main.c -o kernel/main.o
nasm -f elf -o lib/kernel/print.o lib/kernel/print.S
ld -m elf_i386 -Ttext 0xc0001500 -e main -o kernel.bin kernel/main.o lib/kernel/print.o

