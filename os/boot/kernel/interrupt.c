#include "interrupt.h"
#include "stdint.h"
#include "global.h"
#include "interrupt.h"
#include "io.h"
#include "print.h"

#define PIC_M_CTRL 0x20
#define PIC_M_DATA 0x21
#define PIC_S_CTRL 0xa0
#define PIC_S_DATA 0xa1

#define IDT_DESC_CNT 0X21 // 33, define the number of interr.

#define EFLAGS_IF 0x00000200 // eflag 寄存器，if位为1
#define GET_EFLAGS(EFLAG_VAR) asm volatile("pushfl; popl %0" : "=g" (EFLAG_VAR))
extern intr_handler intr_entry_table[IDT_DESC_CNT];
char* intr_name[IDT_DESC_CNT];
intr_handler idt_table[IDT_DESC_CNT];


// 初始化 ICW, set OCW
static void pic_init(void){
	// 初始化主片
	outb (PIC_M_CTRL, 0x11); // 0x20 写入 0x11，ICW1 是使用偶数地址写入
	outb (PIC_M_DATA, 0x20); // 0x21 写入 0x20，ICW2 初始化中断起始地址

	outb (PIC_M_DATA, 0x04);
	outb (PIC_M_DATA, 0x01);

	// 初始化从片
	outb (PIC_S_CTRL, 0x11); // 从片 0xa0
	outb (PIC_S_DATA, 0x28);

	outb (PIC_S_DATA, 0x02);
	outb (PIC_S_DATA, 0x01);

	// 打开主片上的IRO，只接受时钟中断，OCW，初始化后的内容是操作数
	outb (PIC_M_DATA, 0xfe);
    outb (PIC_S_DATA, 0xff);

	put_str("pic init done\n");
}



//中断门描述符结构体，8字节
struct gate_desc{
	uint16_t func_offset_low_word; // 中断程序在目标段内的偏移量，低16位，之后是高16位
	uint16_t selector;			   // 目标代码段选择子，对应内核程序
	uint8_t  dcount;
	uint8_t attribute;
	uint16_t func_offset_high_word;
};


static void make_idt_desc(struct gate_desc* p_gdesc, uint8_t attr, intr_handler function);
static struct gate_desc idt[IDT_DESC_CNT]; // idt 中断描述符表



static void make_idt_desc(struct gate_desc* p_gdesc, uint8_t attr, intr_handler function){
	p_gdesc->func_offset_low_word = (uint32_t) function & 0x0000ffff;
	p_gdesc->selector = SELECTOR_K_CODE;
	p_gdesc->dcount = 0;
	p_gdesc->attribute = attr;
	p_gdesc->func_offset_high_word = ((uint32_t) function & 0xffff0000) >> 16;
}

static void idt_desc_init(void){
	int i;
	for(i = 0; i < IDT_DESC_CNT; ++i){
		make_idt_desc(&idt[i], IDT_DESC_ATTR_DPL0, intr_entry_table[i]);
	}
	put_str("idt_desc_init done\n");
}


static void general_intr_handler(uint8_t vec_nr){
	// 对于 0x27和0x2f号的伪中断不处理
	if(vec_nr == 0x27 || vec_nr == 0x2f){
		return;
	}
	put_str("int vector : 0x");
	put_int(vec_nr);
	put_char('\n');
}

static void exception_init(void){
	int i;
	for(i = 0; i < IDT_DESC_CNT; ++i){
		idt_table[i] = general_intr_handler; // 默认的中断处理函数
		intr_name[i] = "unknown";
	}
	intr_name[0] = "#DE Divide Error";
	intr_name[1] = "#DB Debug Exception";
	intr_name[2] = "NMI Interrupt";
	intr_name[3] = "#BP Breakpoint Exception";
	intr_name[4] = "#OF Overflow Exception";
	intr_name[5] = "#BR BOUND Range Exceeded Exception";
	intr_name[6] = "#UD Invalid Opcode Exception";
	intr_name[7] = "#NM Device Not Available Exception";
	intr_name[8] = "#DF Double Fault  Exception";
	intr_name[9] = "Coprocessor Segment Overrun";
	intr_name[10] = "#TS Ivalid TSS Exception";
	intr_name[11] = "#NP Segment Not Present";
	intr_name[12] = "#SS Stack Fault Exception";
	intr_name[13] = "#GP General Protection Exception";
	intr_name[14] = "#PF Page-fault Exception";
	intr_name[16] = "#MF x87 FPU Floating-Point Error";
	intr_name[17] = "#AC Alignment Check Exception";
	intr_name[18] = "#MC Machine-Check Exception";
	intr_name[19] = "#XF SIMD Floating-Point Exception";
}

void idt_init(){
	put_str("idt_init start\n");
	idt_desc_init(); 	// 初始化中断描述符表
	exception_init(); 	// 初始化前20个中断处理函数名
	pic_init();			// 初始化中断控制器 8259A
	// idt 首地址即为中断描述符的初始地址，左移16位后是48位，接着使用lidt加载该地址
	// 也就是 idt_operand 就是寄存器 LGDT 中的内容
	uint64_t idt_operand = ((sizeof(idt) - 1) | ((uint64_t) (uint32_t) idt << 16));
	asm volatile("lidt %0" : : "m" (idt_operand));
	put_str("idt_init done\n");
}

enum intr_status intr_enable(){
	enum intr_status old_status;
	if(INTR_ON == intr_get_status()){
		old_status = INTR_ON;
		return old_status;
	} else{
		old_status = INTR_OFF;
		asm volatile("sti");
		return old_status;
	}
}

enum intr_status intr_disable(){
	enum intr_status old_status;
	if(INTR_ON == intr_get_status()){
		old_status = INTR_ON;
		asm volatile("cli" : : : "memory");
		return old_status;
	} else{
		old_status = INTR_OFF;
		return old_status;
	}
}

enum intr_status intr_set_status(enum intr_status status){
	return status & INTR_ON ? intr_enable() : intr_disable();
}

enum intr_status intr_get_status(){
	uint32_t eflags = 0;
	GET_EFLAGS(eflags);
	return (EFLAGS_IF & eflags) ? INTR_ON : INTR_OFF;
}