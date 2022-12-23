nasm -f elf -o lib/kernel/print.o lib/kernel/print.S
gcc -m32 -I ./lib/kernel/ -c kernel/main.c -o kernel/main.o
ld -m elf_i386 -Ttext 0xc0001500 -e main -o kernel.bin kernel/main.o lib/kernel/print.o

