#ifndef __LIB_IO_H
#define __LIB_IO_H
#include "stdint.h"
/*
	QImode，quarter-interger，表示一个字节的整数
	HImode，half-interger， 表示一个两字节的整数
	b 输出寄存器 QImode，[a-d]l
	w 输出寄存器 HImode，[a-d]x
*/
// asm [volatile] ("assemble code" : output : input : clobber/modify)
// ax 写入数据，向端口 port 中写入 dx
static inline void outb(uint16_t port, uint8_t data){
	// N 属于 [0,255]，d 表示dx端口号
	// %b0 表示 al，%w1 表示 dx
	asm volatile ("outb %b0, %w1" : : "a" (data), "Nd" (port));
}

// 重复 word_cnt 次，addr 开始的数据写入 port
// outsw，将 ds:esi 写入 port
static inline void outsw(uint32_t port, const void* addr, uint32_t word_cnt){
	asm volatile ("cld; rep outsw" : "+S" (addr), "+c" (word_cnt) : "d" (port));
}

// port 中读入的数据返回
static inline uint8_t inb(uint16_t port){
	uint8_t data;
	asm volatile ("inb %w1, %b0" : "=a" (data) : "Nd" (port));
	return data;
}

// 端口 port 读入的 word_cnt 个字写入 addr
static inline void insw(uint16_t port, void* addr, uint32_t word_cnt){
	asm volatile ("cld; rep insw" : "+D" (addr), "+c" (word_cnt) : "d" (port) : "memory");
}

#endif
