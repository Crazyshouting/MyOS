TI_GDT equ 0
RPL0 equ 0
SELECTOR_VIDEO equ (0x0003 << 3) + TI_GDT + RPL0

[bits 32]
section .data
put_int_buffer dq 0

section .text
global put_str
put_str:
	push ebx
	push ecx
	xor ecx, ecx
	mov ebx, [esp + 12]

.goon:
	mov cl, [ebx]
	cmp cl, 0
	jz .str_over
	push ecx ; if not a '\0', then call put_char
	call put_char
	add esp, 4
	inc ebx
	jmp .goon
.str_over:
	pop ecx
	pop ebx
	ret


global put_char
put_char:

    pushad
    mov ax, SELECTOR_VIDEO ; 3号选择子
    mov gs, ax
    
    mov dx, 0x03d4 ; 显存的数据读写端口
    mov al, 0x0e
    out dx, al	   ; 写入0x0e索引，
    mov dx, 0x03d5
    in al, dx	   ; 读入光标高8位
    mov ah, al

	mov dx, 0x03d4
	mov al, 0x0f
	out dx, al
	mov dx, 0x03d5
	in al, dx	   ; 读入光标低8位

	mov bx, ax
	mov ecx, [esp + 36]	; 读入需要显示的字符参数

	cmp cl, 0xd           ; 判断是否回车或换行
	jz .is_carriage_return
	cmp cl, 0xa
	jz .is_line_feed

	cmp cl, 0x8
	jz .is_backspace ; 判断是否回退
	jmp .put_other	 ; 正常显示字符

.is_backspace:
	dec bx
	shl bx, 1
	mov byte [gs:bx], 0x20	; bx记录光标的位置，因为这里是回退一个格子
	inc bx					; 首先bx减一，左移表示显存中的地址偏移，0x20表示空格，0x7表示黑白显示格式
	mov byte [gs:bx], 0x07	; 光标减一，填入空格，再加一，设置显示格式
	shr bx, 1
	jmp .set_cursor

.put_other:
    shl bx, 1

    mov [gs:bx], cl
    inc bx
    mov byte [gs:bx], 0x07
    shr bx, 1
    inc bx
    cmp bx, 2000
    jl .set_cursor

.is_line_feed:
.is_carriage_return:
	xor dx, dx	; 如果是回车键或者换行键
	mov ax, bx	; bx 是光标位置，给ax
	mov si, 80
	div si		; dx 存储余数，bx减余数表示回到行首
	sub bx, dx

.is_carriage_return_end:
	add bx, 80	; 回到行首后，再加80，表示下一行
	cmp bx, 2000 ; 比较是否超过显示最大数量字符
.is_line_feed_end:
	jl .set_cursor	;换行后设置光标

.roll_screen:
	cld ; 滚屏功能，即超过2000个字符时候的处理
	mov ecx, 960

	mov esi, 0xc00b80a0 ; 重复960次，每次复制4个字节，把2-25行的内容移到1-24行
	mov edi, 0xc00b8000
	rep movsd

	mov ebx, 3840
	mov ecx, 80

.cls:
	mov word [gs:ebx], 0x0720 ; 最后一行使用空格填充
	add ebx, 2
	loop .cls
	mov bx, 1920 ; 光标放到首字符

.set_cursor:
	mov dx, 0x03d4
	mov al, 0x0e
	out dx, al
	mov dx, 0x03d5
	mov al, bh
	out dx, al

	mov dx, 0x03d4
	mov al, 0x0f
	out dx, al
    mov dx, 0x03d5
	mov al, bl
	out dx, al

	.put_char_done:
		popad
		ret

global put_int
put_int:
	pushad
	mov ebp, esp
	mov eax, [ebp + 4*9] ; eax and edx store the number
	mov edx, eax
	mov edi , 7		; 偏移，表示put_int_buffer的最后一字节
	mov ecx, 8		; 需要显示的字符个数，8个
	mov ebx, put_int_buffer	; ebx store the address of put_int_buffer

.16based_4bits:
	and edx, 0x0000000F ; edx 前4位做与 
	cmp edx, 9			; 判断数字是否大于 9
	jg .is_A2F			; 大于9则跳转
	add edx, '0'		; 
	jmp .store
.is_A2F:
	sub edx, 10		; 数字 >= 10，先减10，再加 'A'，用于显示字符，即16进制
	add edx, 'A'

.store:
	mov [ebx + edi], dl	; 低8位，放入ebx+edi地址
	dec edi				; edi 减一，成6，往前移动一个字节
	shr eax, 4			; eax 右移4位，需要显示的数字的后8位变成后4位
	mov edx, eax		; ecx = 7，还有 7 个数字要处理显示
	loop .16based_4bits


.ready_to_print:
	inc edi		; buffer内容处理完后 edi 为-1，加一为0

.skip_prefix_0:
	cmp edi, 8  ; 如果edi已经是末尾了，那就je跳转，说明可以打印了
	je .full0	; 否则继续执行go_on_skip

.go_on_skip:
	mov cl, [put_int_buffer + edi] ; buffer 移入 cl
	inc edi
	cmp cl, '0'	; 如果 cl 为0，那么跳转
	je .skip_prefix_0	; 
	dec edi		; 如果 cl 不是 0 ，那么减一，变成原来位置，然后放上数字
	jmp .put_each_num

.full0:
	mov cl, '0'
.put_each_num:	; 调用put_char，显示数字
	push ecx
	call put_char
	add esp, 4
	inc edi
	mov cl, [put_int_buffer + edi]
	cmp edi, 8
	jl .put_each_num
	popad
	ret
