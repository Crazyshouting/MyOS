#include "print.h"
#include "init.h"

void main(void){
	put_str("I'm a kernel\n");
	init_all();
	asm volatile ("sti"); // 表示开中断，将elfag寄存器中的 IF 位置 1。
	while(1);
}
