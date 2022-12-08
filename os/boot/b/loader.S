    %include "boot.inc"
    section loader vstart=LOADER_BASE_ADDR
    LOADER_STACK_TOP equ LOADER_BASE_ADDR

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
; 4 * 8 + 60 * 8 = 512 字节， 地址 0x1ff，下个地址 0x200



    total_mem_bytes dd 0



    gdt_ptr dw GDT_LIMIT ; gdt指针，低16位定义大小，高32位定义全局描述符表地址，共48位
             dd GDT_BASE

    ; 4 + 6 + 244 + 2 = 256 字节，对齐后 loader_start 就是 0x300
    ards_buf times 244 db 0 ; 读取内存，使用ards结构存储对应内存结构，一个ards为20字节
    ards_nr dw 0            ; ards 数量

    loader_start:
    ; 使用中断的 int 15 中断功能，ax 中的值是E820，edx 使用 'SAMP'
    ; eax、di中的内容都需要设置，为读取内存做准备
    ；
    xor ebx, ebx    ; 清零
    mov edx, 0x534d4150 ; SMAP，用来检查返回后的 eax 中的值
    mov di, ards_buf    ; ards buf 地址放入di，存储内存情况
.e820_mem_get_loop:
    mov ax, 0x0000e820  ; 
    mov ecx, 20         ; cx=20，读取20个字节
    int 0x15
    jc .e820_failed_so_try_e801 ; 失败的时候使用e801指令获取内存，根据flag寄存器的CF位判断
    add di, cx          ; di 地址 + 20，即 ards 大小
    inc word [ards_nr]  ; ards 加 1，记录 ards 数量
    cmp ebx, 0          ; 若 ebx 为 0 且 CF 为 0，说明已经读取完毕，ebx 中存放下一个 ards 地址位置
    jnz .e820_mem_get_loop


    mov cx, [ards_nr]   ; loop 循环 cx 次，即 ards 的个数
    mov ebx, ards_buf   ; ards_buf 地址放入 ebx
    xor edx, edx        ; 
.find_max_mem_area:
    mov eax, [ebx]      ; ards_buf 0-3 字节放入 eax
    add eax, [ebx+8]    ; ards_buf 8-11 字节加上 eax，组成当前内存的最大地址 
    add ebx, 20         ; ards_buf + 20，下个 ards 结构
    cmp edx, eax        ; 比较 edx 和 eax 的内容，保留较大的地址
    jge .next_ards
    mov edx, eax
.next_ards:
    loop .find_max_mem_area
    jmp .mem_get_ok



; 使用 e801 获得内存，否则 88
.e820_failed_so_try_e801:
    mov ax, 0xe801
    int 0x15
    jc .e801_failed_so_try88


    mov cx, 0x400
    mul cx
    shl edx, 16
    and eax, 0x0000ffff
    or edx, eax
    add edx, 0x100000
    mov esi, edx


    xor eax, eax
    mov ax, bx
    mov ecx, 0x10000
    mul ecx
    add esi, eax
    mov edx, esi
    jmp .mem_get_ok


.e801_failed_so_try88:

    mov ah, 0x88
    int 0x15
    jc .error_hlt
    and eax, 0x0000ffff


    mov cx, 0x400
    mul cx
    shl edx, 16
    or edx, eax
    add edx, 0x100000

.mem_get_ok:
    mov [total_mem_bytes], edx



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

    ; mov byte [gs:160], 'P'   ; 第160个字节，显示P字符，每个字符2字节，所以是第81个字符，在第二行第一个

call setup_page ; 创建页表目录和页表


sgdt [gdt_ptr]  ; 储存原来 gdt_ptr 的位置


mov ebx, [gdt_ptr + 2]  ; gdt 的地址
or dword [ebx + 0x18 + 4], 0xc0000000 ; 将 video 显卡段的地址加 0xc0000000，高 4 字节的是 video 段基址



add dword  [gdt_ptr+2], 0xc0000000 ; gdt 地址加 0xc0000000，移到高1G的内核段

add esp, 0xc0000000                ; esp 移入内核段


mov eax, PAGE_DIR_TABLE_POS        ; 页目录表位置放入eax
mov cr3, eax                       ; cr3 存储页目录表物理地址


mov eax, cr0
or eax, 0x80000000
mov cr0, eax


lgdt [gdt_ptr]

mov byte [gs:160], 'V'

jmp $


setup_page:

    mov ecx, 4096
    mov si, 0
.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi], 0  ; 清空 0x100000 的物理地址
    inc esi
    loop .clear_page_dir

; 创建页目录表
.create_pde:
    mov eax, PAGE_DIR_TABLE_POS ; 0x100000
    add eax, 0x1000
    mov ebx, eax




    or eax, PG_US_U | PG_RW_W | PG_P
    mov [PAGE_DIR_TABLE_POS + 0x0], eax
    mov [PAGE_DIR_TABLE_POS + 0xc00], eax

    sub eax, 0x1000
    mov [PAGE_DIR_TABLE_POS + 4092], eax


    mov ecx, 256