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

    mov byte [gs:0x02], ''
    mov byte [gs:0x03], 0xA4

    mov byte [gs:0x04], 'M'
    mov byte [gs:0x05], 0xA4

    mov byte [gs:0x06], 'B'
    mov byte [gs:0x07], 0xA4

    mov byte [gs:0x08], 'R'
    mov byte [gs:0x09], 0xA4
    
    mov eax, LOADER_START_SECTOR    ; 硬盘的LBA地址
    mov bx, LOADER_BASE_ADDR        ; 硬盘数据写入内存地址
    mov cx, 3                       ; 待读取的硬盘扇区数
    call rd_disk_m_16               ; 硬盘读入函数，先push cs、ip内容当前地址到栈，再jmp到rd_disk_m_16函数的位置
    
    jmp LOADER_BASE_ADDR            ; 进入硬盘写入后内存区域


; 读取硬盘的n个扇区
rd_disk_m_16:

    ; eax 中存储LBA地址 0x2
    ; bx 硬盘写入的位置 0x900


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


        mov ax, di  ; 要读取的扇区数
        mov dx, 768
        mul dx      ; ax = 256
        mov cx, ax  ; cx = 256，读取的时候一次两个字节，扇区大小512B，读 256 次
    ; 接下来从0x1f0端口读取数据
        mov dx, 0x1f0 ; 
    .go_on_read:
        in ax, dx       ; dx读取2个字节数据，传给ax
        mov [bx], ax    ; ax内容放入内存 0x900地址
        add bx, 2       ; bx 加2，0x902
        loop .go_on_read    ; 如果cx不为0，继续读取，此时cx更新为255
        ret             ; jmp到原来pop栈顶内容，回到call的位置，再 pop

    times 510 - ($ - $$) db 0
    db 0x55, 0xaa