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
    times 59 dq 0
    times 5 db 0
    
; 4 * 8 + 60 * 8 = 512 字节， 地址 0x1ff，下个地址 0x200



    total_mem_bytes dd 0  ; 0x900+0x200 = 0xb00, value = 32 MB 0x02000000


    gdt_ptr dw GDT_LIMIT ; gdt指针，低16位定义大小，高32位定义全局描述符表地址，共48位
             dd GDT_BASE

    ; 4 + 6 + 244 + 2 = 256 字节，对齐后 loader_start 就是 0x300
    ards_buf times 244 db 0 ; 读取内存，使用ards结构存储对应内存结构，一个ards为20字节
    ards_nr dw 0            ; ards 数量
    
    SELECTOR_CODE equ (0x0001 << 3) + TI_GDT + RPL0
    SELECTOR_DATA equ (0x0002 << 3) + TI_GDT + RPL0
    SELECTOR_VIDEO equ (0x0003 << 3) + TI_GDT + RPL0
loader_start:
    ; 使用中断的 int 15 中断功能，ax 中的值是E820，edx 使用 'SAMP'
    ; eax、di中的内容都需要设置，为读取内存做准备
    mov sp, LOADER_BASE_ADDR
    xor ebx, ebx    ; 清零
    mov ax, 0
    mov es, ax
    mov di, ards_buf    ; ards buf 地址放入di，存储内存情况
.e820_mem_get_loop:
    mov edx, 0x534d4150 ; SMAP，用来检查返回后的 eax 中的值
    mov eax, 0x0000e820  ; 
    mov ecx, 20        ; cx=20，20个字节
    int 0x15
    jc .e820_failed_so_try_e801 ; 失败的时候使用e801指令获取内存，根据flag寄存器的CF位判断
    add di, cx          ; di 地址 + 20，即 ards 大小
    inc word [ards_nr]  ; ards 加 1，记录 ards 数量
    cmp ebx, 0          ; 若 ebx 为 0 且 CF 为 0，说明已经读取完毕，ebx 中存放下一个 ards 地址位置
    jne .e820_mem_get_loop


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
    and eax, 0x0000FFFF
    or edx, eax
    add edx, 0x100000
    mov esi, edx


    xor eax, eax
    mov ax, bx
    mov ecx, 0x10000
    mul ecx
    mov edx, esi
    add edx, eax
    jmp .mem_get_ok


.e801_failed_so_try88:

    mov ah, 0x88
    int 0x15
    jc .error_hlt
    and eax, 0x0000FFFF


    mov cx, 0x400
    mul cx
    shl edx, 16
    or edx, eax
    add edx, 0x100000

.error_hlt:
	jmp $

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

    mov eax, KERNEL_START_SECTOR  ; 0x9
    mov ebx, KERNEL_BIN_BASE_ADDR ; kernel.bin 加载进内存的位置，0x70000
    mov ecx, 200
    
	call rd_disk_m_32 ; 从硬盘的第9个扇读取200个扇区
    
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
	jmp SELECTOR_CODE:enter_kernel
    

enter_kernel:
	call kernel_init
	mov esp, 0xc009f000
	jmp KERNEL_ENTRY_POINT

kernel_init:
	; 加载kernel程序到内存位置0x70000中，后面需要实现kernel进程映像
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx

    mov dx, [KERNEL_BIN_BASE_ADDR + 42] ; 表示程序头表的每个段大小
	mov ebx, [KERNEL_BIN_BASE_ADDR + 28] ; 第一个段在程序中的偏移量
	add ebx, KERNEL_BIN_BASE_ADDR		 ; 第一个段的位置
    mov cx, [KERNEL_BIN_BASE_ADDR + 44] ; 偏移处表示有多少个段
    
.each_segment:
	cmp byte [ebx + 0], PT_NULL
	je .PTNULL
	push dword [ebx + 16] ; 段偏移16个字节的位置，放的是p_filesz，表示该段在程序中的大小
	mov eax, [ebx + 4] 
	add eax, KERNEL_BIN_BASE_ADDR
	push eax ; 源地址，base地址加4
	push dword [ebx + 8] ; 目的地址

	call mem_cpy ; memcpy(dst_addr, src_addr, size)
	add esp, 12

.PTNULL:
	add ebx, edx
	loop .each_segment
	ret

mem_cpy:
	cld
	push ebp
	mov ebp, esp
	push ecx

	mov edi, [ebp + 8]
	mov esi, [ebp + 12]
	mov ecx, [ebp + 16]
	rep movsb

	pop ecx
	pop ebp
	ret

setup_page:

    mov ecx, 4096
    mov esi, 0

.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi], 0  ; 清空 0x100000 的物理地址
    inc esi
    loop .clear_page_dir

; 创建页目录表
.create_pde:
    mov eax, PAGE_DIR_TABLE_POS ; 0x100000，使用这个物理地址作为页目录起始地址
    add eax, 0x1000		; 4KB空间用来当作目录页，之后的空间用作页表地址
    mov ebx, eax		; eax=ebx=0x101000




    or eax, PG_US_U | PG_RW_W | PG_P    ; eax 写权限和用户权限等的添加
    mov [PAGE_DIR_TABLE_POS + 0x0], eax ; 第一个页目录表记录第一条页表的位置
    mov [PAGE_DIR_TABLE_POS + 0xc00], eax ; 第768个页表和第一个相同，0xc00是3072字节
    sub eax, 0x1000		; eax 重新是第一个页目录的值，下一句放入地址 0x101000-4=0x100ffc，指向页目录表第一项
    mov [PAGE_DIR_TABLE_POS + 4092], eax

    mov ecx, 256
    mov esi, 0
	mov edx, PG_US_U | PG_RW_W | PG_P
.create_pte:
	mov [ebx+esi*4], edx ; 循环256次，从0x101000开始，每4字节写入edx，edx保存的是物理页地址，这里写了前256个页表
	add edx, 4096
	inc esi
	loop .create_pte


    mov eax, PAGE_DIR_TABLE_POS
	add eax, 0x2000				; eax=0x102000
	or eax, PG_US_U | PG_RW_W | PG_P
	mov ebx, PAGE_DIR_TABLE_POS	; ebx=0x100000
	mov ecx, 254
	mov esi, 769
.create_kernel_pde:
	mov [ebx+esi*4], eax 	; 写内核的256个页表
	inc esi
	add eax, 0x1000
	loop .create_kernel_pde
	ret 


; 读取硬盘的n个扇区
rd_disk_m_32:

    mov esi, eax ; 备份 eax 和 cx 的数据
    mov di, cx
    ; 读写硬盘
    ; 第一步--------------设置读取的扇区数
    mov dx, 0x1f2 ; 准备往 0x1f2 端口写数据
    mov al, cl    ; cl 传值
    out dx, al    ; 写入1，即读取的硬盘扇区数为 1

    mov eax, esi

    ; 第二步--------------LBA的低、中、高地址写入内容
    ; 低地址端口 0x1f3, 中 0x1f4, 高0x1f5

    mov dx, 0x1f3
    out dx, al


    mov cl, 8       ; cl = 1000b
    shr eax, cl     ; eax 右移8位，为0
    mov dx, 0x1f4   
    out dx, al      ; 中8位为0


    shr eax, cl     ; 高8位为0
    mov dx, 0x1f5
    out dx, al

    shr eax, cl     ; 最后4位放在device寄存器中，device为杂项寄存器
    and al, 0x0f    ; 对应端口 0x1f6
    or al, 0xe0     ; 可设定硬盘的地址模式，是否为 LBA，还是 CHS
    mov dx, 0x1f6
    out dx, al

    ; 第三步-----------从硬盘读取对应数据
    mov dx, 0x1f7   ; 该端口读时获取硬盘状态，写时对硬盘的操作命令
    mov al, 0x20
    out dx, al
    
    ; 第四步-----------检查硬盘状态
    .not_ready:
        ; 给硬盘处理时间，使用nop
        nop
        in al, dx       ; 此时硬盘还是0x1f7端口，先获取硬盘状态看是否准备好，指硬盘内寻址成功
        and al, 0x88
        cmp al, 0x08    
        jnz .not_ready  ; 如果没有则继续等待


        mov ax, di  ; 要读取的扇区数, 3
        mov dx, 256
        mul dx      ; ax = 256
        mov cx, ax  ; cx = 256，读取的时候一次两个字节，扇区大小512B，读 256 次
    ; 接下来从0x1f0端口读取数据
        mov dx, 0x1f0 ;
    .go_on_read:
        in ax, dx       ; dx读取2个字节数据，传给ax
        mov [ebx], ax   ; ax内容放入内存 0x70000地址
        add ebx, 2       ; ebx 加2，0x70002
        loop .go_on_read    ; 如果cx不为0，继续读取，此时cx更新为255
        ret             ; jmp到原来pop栈顶内容，回到call的位置，再 pop
