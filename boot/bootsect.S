! bootsect.S 编译后的代码将保存在引导设备的第一个扇区(一个扇区 512 Byte)，
! 将会由 BIOS 读入到内存绝对地址 0x7C00(31KB) 处。
! 该部分代码会把自己由地址 0x7C00 移动到内存绝对地址 0x90000(576KB) 处，
! 并使用 BIOS 中断把启动设备盘中后 2KB 字节(1-4 共四个扇区)代码(boot/setup.S)读入到内存 0x90200(576KB+512B=576.5KB) 处，即 bootsect.S 后面。
! 而内核的其它部分(system 模块)则被读入到内存地址 0x10000(64KB) 处。
!
! 由于文件名后缀为 .S(大写)，可以使用 GNU C 编译器的预处理功能，可以使用 "#include" "#if" 等语句
! 这里主要是为了使用 include/linux/config.h 中定义的常量
#include <linux/config.h>
!
! SYS_SIZE is the number of clicks (16 bytes) to be loaded.
! 0x3000 is 0x30000 bytes = 196kB, more than enough for current
! versions of linux (0x3000*16=0x30000)
! 要加载的 system 模块的长度，单位：节(1节=16字节)，所以 0x3000*16=0x30000=192kb
SYSSIZE = DEF_SYSSIZE
!
!	bootsect.s		(C) 1991 Linus Torvalds
!	modified by Drew Eckhardt
!
! bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
! iself out of the way to address 0x90000, and jumps there.
!
! It then loads 'setup' directly after itself (0x90200), and the system
! at 0x10000, using BIOS interrupts. 
!
! NOTE! currently system is at most 8*65536 bytes long. This should be no
! problem, even in the future. I want to keep it simple. This 512 kB
! kernel size should be enough, especially as this doesn't contain the
! buffer cache as in minix
!
! The loader has been made as simple as possible, and continuos
! read errors will result in a unbreakable loop. Reboot by hand. It
! loads pretty fast by getting whole sectors at a time whenever possible.

! .global 或 .globl 表示其后的标识符是外部的或全局的
.globl begtext, begdata, begbss, endtext, enddata, endbss
.text       ! .text 表示代码段
begtext:
.data       ! .data 表示数据段
begdata:
.bss        ! .bss 表示未初始化数据段
begbss:
.text

! setup 程序所占扇区数
SETUPLEN = 4				! nr of setup-sectors 
! 引导程序 bootsect 由 BIOS 加载到的内存地址
BOOTSEG  = 0x07c0			! original address of boot-sector
! 将 bootsect 程序移动到此处(0x90000: 576KB) - 避开 system 模块
INITSEG  = DEF_INITSEG			! we move boot here - out of the way
! 将 setup 程序加载到此处(0x90200: 576.5KB) - bootsect 后面
SETUPSEG = DEF_SETUPSEG			! setup starts here
! 将 system 模块先加载到此处(0x10000: 64KB)，后面会移动到 0x0 处
SYSSEG   = DEF_SYSSEG			! system loaded at 0x10000 (65536).
! system 模块结束地址
ENDSEG   = SYSSEG + SYSSIZE		! where to stop loading

! ROOT_DEV & SWAP_DEV are now written by "build".
! 根文件系统设备号 ROOT_DEV 和交换设备号 SWAP_DEV 现在由 tools 目录下的 build 程序写入。
ROOT_DEV = 0        ! 根文件系统设备使用与系统引导时同样的设备
SWAP_DEV = 0        ! 交换设备也使用与系统导引时同样的设备

entry start         ! 程序开始点
start:
	mov	ax,#BOOTSEG     ! 将 bootsect.S 代码本身从 ds:[si] 移动到 es:[di]
	mov	ds,ax           ! 即从 0x07c0:0x0000 -> 0x9000:0x0000 处
	mov	ax,#INITSEG
	mov	es,ax
	mov	cx,#256         ! 共移动 256 字，即 512 Bytes(即bootsect代码占1个扇区)
	sub	si,si
	sub	di,di
	rep                 ! 重复执行并递减 cx 的值，直至 cx = 0 为止
	movw
    ! 跳转到新的地址(0x9000:[go])上去执行
	jmpi	go,INITSEG  ! 以上代码是将 bootsect 程序从 0x07c0 移动到 0x90000

! 此时代码就已经跳到 0x9000:[go](段内偏移)
go:	mov	ax,cs	        ! 此时 cs = 0x9000(0)
    ! 设置一个任意远大于 512() 的值
	mov	dx,#0xfef4	    ! arbitrary value >>512 - disk parm size

	mov	ds,ax
	mov	es,ax
    ! 临时保存栈段地址 0x9000，在后面会用到
	push	ax      ! 在此时 ss = 0x00, sp = 0xfffe，即栈指针指向 0x0fffe 处

    ! 设置栈寄存器 ss 和 sp 指向远大于 0x90200 处即可，因为还会将 bootsect.S 后面的 4 个扇区的 setup.s 代码复制到 0x90200 处
	mov	ss,ax		! put stack at 0x9ff00 - 12.
	mov	sp,dx       ! 将栈指针指向 0x9fef4(0x9000:0xfef4) 处
!/*
! *	Many BIOS's default disk parameter tables will not 
! *	recognize multi-sector reads beyond the maximum sector number
! *	specified in the default diskette parameter tables - this may
! *	mean 7 sectors in some cases.
! *
! *	Since single sector reads are slow and out of the question,
! *	we must take care of this by creating new parameter tables
! *	(for the first disk) in RAM.  We will set the maximum sector
! *	count to 18 - the most we will encounter on an HD 1.44.  
! *
! *	High doesn't hurt.  Low does.
! *
! *	Segments are as follows: ds=es=ss=cs - INITSEG,
! *		fs = 0, gs = parameter table segment
! */

! 段寄存器现在状态是: 
! ds=es=ss=cs=0x9000(INITSEG), fs=0x0, gs=软驱参数表所在段的值

! BIOS 设置的中断 0x1E 指向的是软驱参数表(0x1E*4=0x78处)，
!下面代码是先软驱参数表由 0x0000:0x0078 移动到 0x9000:0xfef4 处，
! 然后修改新的参数表中的每磁道最大扇区数(偏移 4 个字节处)为 18

    ! 设置 fs:bx=0x0:0x78=0x78 指向存有软驱参数表的内存地址
	push	#0
	pop	fs
	mov	bx,#0x78		! fs:bx is parameter table address

    ! 将 gs:si 作为源地址，es:di 作为目的地址，拷贝 12 字节数据()
	seg fs              ! 指令 seg 表示下一条语句的操作数(bx)在 fs 段中
    ! 此处表示将 fs:bx 指向的内存地址中的数据(
    ! 软驱参数表所在的内存地址，由 BIOS 设置的)作为 gs:si 的值
	lgs	si,(bx)			! gs:si is source
	mov	di,dx			! es:di is destination(0x9000:0xfef4)
	mov	cx,#6			! copy 12 bytes
	cld                 ! 清除方向标志(clear direction)，复制时指针递增

	rep                 ! 复制 12 bytes 的软驱参数表内容到 0x9000:0xfef4 处
	seg gs
	movw

	mov	di,dx           ! es:di 指向新的软驱参数表
    ! 并修改偏移 4 字节(0x9000:0xfef8)处表示的最大扇区数(改为 18)
	movb	4(di),*18	! patch sector count

    ! 使得 0x1E 中断(内存 0x78 处)指向新软驱参数表地址(0x9000:0xfef4)处
	seg fs
	mov	(bx),di         ! (bx)指向0x78处，di = 0xfef4
	seg fs
	mov	2(bx),es        ! 2(bx)指向0x80处，es = 0x9000

	pop	ax              ! 此时 ax = 0x9000, sp = 0xfef4
	mov	fs,ax
	mov	gs,ax           ! fs = gs = 0x9000
	
	xor	ah,ah			! reset FDC  ! 复位软盘控制器，使其采用新参数
	xor	dl,dl           ! ah = 0, dl = 0(第一个软驱)

! 利用 BIOS 的 0x13 号中断
	int 	0x13	    ! 调用 0x13 中断

! load the setup-sectors directly after the bootblock.
! Note that 'es' is already set up.
! 将 setup 模块的代码(共 4 个扇区)加载到 bootsect 代码块后面(0x90200 处)。
! 注意，此时已经设置 es = 0x9000
! BIOS 0x13 中断的参数说明：
! ah = 0x02 --> 功能号:读磁盘扇区到内存;   al = 需要读取的扇区数
! ch = 磁道(柱面)号的低 8 位;   cl = 开始扇区(位 0-5)，磁道号高 2 位(位 6-7)
! dh = 磁头号;                  dl = 驱动器号(如果是硬盘则位 7 要置位[1])
! es:bx --> 指向数据缓冲区(0x90200); 如果出错则 CF 标志置位，ah 中是出错码
load_setup:
	xor	dx, dx			! drive 0, head 0
	mov	cx,#0x0002		! sector 2, track 0
	mov	bx,#0x0200		! address = 512, in INITSEG(0x9000)
    ! ax = 0x0204; ah = 0x02(功能号), al = 0x04(读4个扇区)
	mov	ax,#0x0200+SETUPLEN	! service 2, nr of sectors
	int	0x13			! read it
    ! 如果没出错(进位标志位 CF != 1)，则直接跳到 ok_load_setup 处继续执行
	jnc	ok_load_setup		! ok - continue

    ! 如果出错，则显示出错信息
	push	ax			! dump error code ! 出错码(ah 中存储)入栈，此时 sp = 0xfef4 + 2
	call	print_nl    ! 打印换行符
	mov	bp, sp          ! print_hex 将会打印  ss:bp 指向的地址中的数值
	call	print_hex   ! 以十六进制的形式打印错误码
	pop	ax	            ! ss:sp = 0x9fef4 栈指针指向软驱参数表
	
	xor	dl, dl			! reset FDC ! 复位磁盘控制器(驱动器号)，并重试
	xor	ah, ah          ! 清除错误码
	int	0x13
	j	load_setup      ! 跳回到 load_setup 进行重试: j 表示 jmp

! 若执行到此处表示已经将 setup 模块加载到内存 0x90200 处
ok_load_setup:

! Get disk drive parameters, specifically nr of sectors/track
! 利用 BIOS 0x13 中断的 8 号功能来获取磁盘驱动器的参数。实际是获取每个磁道的扇区数，并保存在 sectors(该代码中的 sectors 位置) 处
! 获取磁盘驱动器参数的中断调用格式和返回信息如下：
! 调用格式：ah = 0x08   dl = 驱动器号
! 返回信息：如果出错，则 CF 置位，且 ah = 错误码
! ah = 0, al = 0        bl = 驱动器类型(AT/PS2)
! ch = 最大磁道号的低 8 位      cl = 每磁道最大扇区数(位 0-5)，最大磁道号高 2 位(位 6-7)
! dh = 最大磁头数   dl = 驱动器数量
! es:di -> 软驱参数表(0x9fef4)
	xor	dl,dl           ! 驱动器号(0)
	mov	ah,#0x08		! AH=8 is get drive parameters(功能号 8 --> 获取驱动器参数)
	int	0x13            ! 调用 0x13 号中断读取驱动器参数(返回信息已写入各个寄存器)
	xor	ch,ch           ! 将 ch 复位，这样使用 cx 时只有低 8 位有效
	seg cs
    ! 由于上面 ch 已经置位(0)，而对于软盘而言，最大磁道数不会超过 256(2^8)，所以，cl 中的位 6-7 为 0，因此，cx 中的数据即每磁道的扇区数
	mov	sectors,cx      ! 将每磁道的扇区数保存到 sectors 处
	mov	ax,#INITSEG
	mov	es,ax           ! 因为上面获取磁盘参数表时中断修改了 es 的值，重新改回 0x9000

! Print some inane message
! 下面代码利用 BIOS 0x10 中断的 0x03 功能和 0x13 中断来显示信息 "'Loading'+回车换行" 共 9 个字符
! BIOS 0x10 中断说明：
! 功能号: ah = 0x03, 读取光标所在位置
! 输入: bh = 页号
! 返回: ch = 扫描开始线; cl = 扫描结束线; dh = 行号(0x00 顶端); dl = 列号(0x00 最左边)
! 功能号: ah = 0x13, 显示字符串
! 输入: al = 放置光标的方式及规定属性。0x01 -- 表示使用 bl 中的属性值，光标停在字符串结尾处。
! bh = 显示页面号, bl = 字符属性; dh = 行号; dl = 列号。cx = 显示的字符串字符数。
! es:bp 此寄存器对指向要显示的字符串起始位置处

	mov	ah,#0x03		! read cursor pos ! 读取光标所在位置
	xor	bh,bh
	int	0x10
	
	mov	cx,#9
	mov	bx,#0x0007		! page 0, attribute 7 (normal)
	mov	bp,#msg1
	mov	ax,#0x1301		! write string, move cursor
	int	0x10

! ok, we've written the message, now
! we want to load the system (at 0x10000)

	mov	ax,#SYSSEG
	mov	es,ax		! segment of 0x010000
	call	read_it
	call	kill_motor
	call	print_nl

! After that we check which root-device to use. If the device is
! defined (!= 0), nothing is done and the given device is used.
! Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
! on the number of sectors that the BIOS reports currently.

	seg cs
	mov	ax,root_dev
	or	ax,ax
	jne	root_defined
	seg cs
	mov	bx,sectors
	mov	ax,#0x0208		! /dev/ps0 - 1.2Mb
	cmp	bx,#15
	je	root_defined
	mov	ax,#0x021c		! /dev/PS0 - 1.44Mb
	cmp	bx,#18
	je	root_defined
undef_root:
	jmp undef_root
root_defined:
	seg cs
	mov	root_dev,ax

! after that (everyting loaded), we jump to
! the setup-routine loaded directly after
! the bootblock:

	jmpi	0,SETUPSEG

! This routine loads the system at address 0x10000, making sure
! no 64kB boundaries are crossed. We try to load it as fast as
! possible, loading whole tracks whenever we can.
!
! in:	es - starting address segment (normally 0x1000)
!
sread:	.word 1+SETUPLEN	! sectors read of current track
head:	.word 0			! current head
track:	.word 0			! current track

read_it:
	mov ax,es
	test ax,#0x0fff
die:	jne die			! es must be at 64kB boundary
	xor bx,bx		! bx is starting address within segment
rp_read:
	mov ax,es
	cmp ax,#ENDSEG		! have we loaded all yet?
	jb ok1_read
	ret
ok1_read:
	seg cs
	mov ax,sectors
	sub ax,sread
	mov cx,ax
	shl cx,#9
	add cx,bx
	jnc ok2_read
	je ok2_read
	xor ax,ax
	sub ax,bx
	shr ax,#9
ok2_read:
	call read_track
	mov cx,ax
	add ax,sread
	seg cs
	cmp ax,sectors
	jne ok3_read
	mov ax,#1
	sub ax,head
	jne ok4_read
	inc track
ok4_read:
	mov head,ax
	xor ax,ax
ok3_read:
	mov sread,ax
	shl cx,#9
	add bx,cx
	jnc rp_read
	mov ax,es
	add ah,#0x10
	mov es,ax
	xor bx,bx
	jmp rp_read

read_track:
	pusha
	pusha	
	mov	ax, #0xe2e 	! loading... message 2e = .
	mov	bx, #7
 	int	0x10
	popa		

	mov dx,track
	mov cx,sread
	inc cx
	mov ch,dl
	mov dx,head
	mov dh,dl
	and dx,#0x0100
	mov ah,#2
	
	push	dx				! save for error dump
	push	cx
	push	bx
	push	ax

	int 0x13
	jc bad_rt
	add	sp, #8   	
	popa
	ret

bad_rt:	push	ax				! save error code
	call	print_all			! ah = error, al = read
	
	
	xor ah,ah
	xor dl,dl
	int 0x13
	

	add	sp, #10
	popa	
	jmp read_track

!/*
! *	print_all is for debugging purposes.  
! *	It will print out all of the registers.  The assumption is that this is
! *	called from a routine, with a stack frame like
! *	dx 
! *	cx
! *	bx
! *	ax
! *	error
! *	ret <- sp
! *
!*/
 
print_all:
	mov	cx, #5		! error code + 4 registers
	mov	bp, sp	

print_loop:
	push	cx		! save count left
	call	print_nl	! nl for readability
	jae	no_reg		! see if register name is needed
	
	mov	ax, #0xe05 + 0x41 - 1
	sub	al, cl
	int	0x10

	mov	al, #0x58 	! X
	int	0x10

	mov	al, #0x3a 	! :
	int	0x10

no_reg:
	add	bp, #2		! next register
	call	print_hex	! print it
	pop	cx
	loop	print_loop
	ret

! 调用 BIOS 0x10 号中断，以电传方式(什么是电传方式?)显示回车换行
print_nl:
	mov	ax, #0xe0d	! CR
	int	0x10
	mov	al, #0xa	! LF
	int 0x10
	ret

!/*
! *	print_hex is for debugging purposes, and prints the word
! *	pointed to by ss:bp in hexadecmial.
! * print_hex 主要用于调试，将会以十六进制的方式打印 ss:bp 指向的字符
!*/
! 调用 BIOS 0x10 号中断，以电传方式和 4 个十六进制数显示 ss:bp 指向的字
print_hex:
	mov	cx, #4		! 4 hex digits          ! 要显示 4 个十六进制数字
	mov	dx, (bp)	! load word into dx     ! 显示值(ss:bp 指向的数字)放入 dx
print_digit:
! 先显示高字节，因此需要把 dx 中值左旋 4 bit，此时高 4 bit 在 dx 的低 4 位中
! dx 寄存器有 16 bit，每次循环只打印 4 bit(由高往低打印)
	rol	dx, #4		! rotate so that lowest 4 bits are used -- 将高 4 bit 转为低 4 bit
	mov	ah, #0xe	! 0x10 的中断功能号
	mov	al, dl		! mask off so we have only next nibble
	and	al, #0xf    ! 将要显示的值放入 al 中，并只取低 4 bit(屏蔽 al 中高 4bit)

    ! 将要显示的数字转换成 ascii 码值，即加上 0x30('0' 的 ascii 值):
    ! '1' 用 ascii 表示为 0x31
	add	al, #0x30	! convert to 0 based digit, '0'
    ! 若此时 al 超过 0x39，即表示需要用 'A' - 'F' 来显示(再+7)
	cmp	al, #0x39	! check for overflow    'A' - 'F'
	jbe	good_digit  ! 如果 <= 0x39，则直接显示

    ! 如果 > 0x39 则要再 +7 比如 0x40 表示数字 10，显示时对应的 ascii 为 0x41(十进制 65)
	add	al, #0x41 - 0x30 - 0xa 	! 'A' - '0' - 0xa = 0x7

good_digit:
	int	0x10
	loop	print_digit     ! cx--, 若 cx > 0 则显示下一个值
	ret                     ! 返回到函数调用处


!/*
! * This procedure turns off the floppy drive motor, so
! * that we enter the kernel in a known state, and
! * don't have to worry about it later.
! */
kill_motor:
	push dx
	mov dx,#0x3f2
	xor al, al
	outb
	pop dx
	ret

! 每磁道的扇区数
sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "Loading"

.org 506
swap_dev:
	.word SWAP_DEV
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss:

