; 主引导程序
;
%include "boot.inc"
SECTION MBR vstart=0x7c00
    mov ax, cs ; ax = cs，初始化各段寄存器，实模式下cs为段基址
    mov ds, ax ; ds = cs，数据段基址
    mov es, ax ; es = cs，附加数据段基址
    mov ss, ax ; ss = cs，栈基址
    mov fs, ax ; fs = cs，
    mov sp, 0x7c00 ; sp = 0x7c00，栈指针
    mov ax, 0xb800 ; ax = 0xb800
    mov gs, ax ; gs = 0xb800，现存段基址

; 清屏
; 中断功能
; int 0x10，ax寄存器决定具体操作
; ah=0x06，上卷清屏
; al=0x00，表示上卷行数，为 0 则是全部的行数
; ch=0x00，窗口上边位置
; cl=0x00，窗口左边位置
; dh=0x18，窗口下边位置 0x18 = 24d，0-24共25行
; dl=0x4f，窗口右边位置 0x4f = 79d，0-79共80行
; bx，上卷属性


    mov ax, 0x0600
    mov bx, 0x0700
    mov cx, 0
    mov dx, 0x184f


    int 0x10

; 输出字符串 MBR，主要操作显存, 字符+属性，2字节
    mov byte [gs:0x00], '1'
    mov byte [gs:0x01], 0xA4

    mov byte [gs:0x00], ''
    mov byte [gs:0x01], 0xA4

    mov byte [gs:0x00], 'M'
    mov byte [gs:0x01], 0xA4

    mov byte [gs:0x00], 'B'
    mov byte [gs:0x01], 0xA4

    mov byte [gs:0x00], 'R'
    mov byte [gs:0x01], 0xA4

    mov eax, LOADER_START_SECTOR    ; 硬盘的LBA地址
    mov bx, LOADER_BASE_ADDR        ; 硬盘数据写入内存地址
    mov cx, 1                       ; 待读取的硬盘扇区数
    call rd_disk_m_16               ; 硬盘读入函数

    jmp LOADER_BASE_ADDR            ; 进入硬盘写入后内存区域
