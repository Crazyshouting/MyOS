    %include "boot.inc"
    section loader vstart=LOADER_BASE_ADDR
    LOADER_STACK_TOP equ LOADER_BASE_ADDR
    jmp loader_start

; 构建 GDT 描述符，4个，第 0 个不可访问
    GDT_BASE:  dd 0x00000000
                dd 0x00000000

    CODE_DESC: dd 0x0000FFFF  ; 段基址 + 段界限，G位为1，段基址为32位，段界限为 20 位，0xfffff，1MB * 4KB = 4GB
                dd DESC_CODE_HIGH4

    DATA_STACK_DESC: dd 0x0000FFFF
                      dd DESC_DATA_HIGH4

    VIDEO_DESC: dd 0x80000007     ; 段基址是 0x00008000，段界限 0x00007，显存大小 (7+1) * 4KB = 32 KB
                 dd DESC_VIDEO_HIGH4

    GDT_SIZE equ $ - GDT_BASE
    GDT_LIMIT equ GDT_SIZE - 1
    times 60 dq 0
    SELECTOR_CODE equ (0x0001 << 3) + TI_GDT + RPL0
    SELECTOR_DATA equ (0x0002 << 3) + TI_GDT + RPL0
    SELECTOR_VIDEO equ (0x0003 << 3) + TI_GDT + RPL0
; 4 * 8 + 60 * 8 = 512 字节


    gdt_ptr dw GDT_LIMIT ; gdt指针，低16位定义大小，高32位定义全局描述符表地址，共48位
             dd GDT_BASE
    loadermsg db '2 loader in real'

    loader_start:
    ; 实模式打印字符串功能
    ; int 13，第 06 号功能
    ；开始处于实模式
    ; 使用int 10，ax = 13，打印字符串
    ; bp 存储字符串
    ; cx，表示字符串长度，这点和上卷清屏的设置不同
    ; bx，页号和字体前背景颜色
    ; dx，0x1800，第25行，第0列，定义字符串显示的位置
    ; al = 0
    ; al = 1
    ; al = 2
    ; al = 3





    mov sp, LOADER_BASE_ADDR
    mov bp, loadermsg
    mov cx, 17
    mov ax, 0x1301
    mov bx, 0x001f
    mov dx, 0x1800
    int 0x10

    ; 准备进入保护模式
    ; 打开 A20 地址线
    ; 加载 GDT
    ; cr0 的pe位置1



    in al, 0x92
    or al, 0000_0010B
    out 0x92, al


    lgdt [gdt_ptr] ; 在特殊的寄存器加载全局描述符



    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax

    jmp dword SELECTOR_CODE:p_mode_start ; 刷新cpu流水线，让cpu进入保护模式的流水线工作


[bits 32]
p_mode_start:
    mov ax, SELECTOR_DATA    ; 初始化在保护模式下的各个寄存器的值
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, LOADER_STACK_TOP
    mov ax, SELECTOR_VIDEO
    mov gs, ax

    mov byte [gs:160], 'P'   ; 第160个字节，显示P字符，每个字符2字节，所以是第81个字符，在第二行第一个

    jmp $