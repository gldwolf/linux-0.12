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
	mov	ax,#BOOTSEG     ! 从 ds:[si] 移动到 es:[di]
	mov	ds,ax           ! 即从 0x07c0:0x0000 -> 0x9000:0x0000 处
	mov	ax,#INITSEG
	mov	es,ax
	mov	cx,#256         ! 共移动 256 字，即 512 Bytes
	sub	si,si
	sub	di,di
	rep                 ! 重复执行并递减 cx 的值，直至 cx = 0 为止
	movw
    ! 跳转到新的地址(0x90000:[go])上去执行
	jmpi	go,INITSEG  ! 以上代码是将 bootsect 程序从 0x07c0 移动到 0x90000

! 此时代码就已经跳到 0x90000:[go](段内偏移)
go:	mov	ax,cs		
    ! 设置一个任意远大于 512() 的值
	mov	dx,#0xfef4	! arbitrary value >>512 - disk parm size

	mov	ds,ax
	mov	es,ax
	push	ax

	mov	ss,ax		! put stack at 0x9ff00 - 12.
	mov	sp,dx
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


	push	#0
	pop	fs
	mov	bx,#0x78		! fs:bx is parameter table address
	seg fs
	lgs	si,(bx)			! gs:si is source

	mov	di,dx			! es:di is destination
	mov	cx,#6			! copy 12 bytes
	cld

	rep
	seg gs
	movw

	mov	di,dx
	movb	4(di),*18		! patch sector count

	seg fs
	mov	(bx),di
	seg fs
	mov	2(bx),es

	pop	ax
	mov	fs,ax
	mov	gs,ax
	
	xor	ah,ah			! reset FDC 
	xor	dl,dl
	int 	0x13	

! load the setup-sectors directly after the bootblock.
! Note that 'es' is already set up.

load_setup:
	xor	dx, dx			! drive 0, head 0
	mov	cx,#0x0002		! sector 2, track 0
	mov	bx,#0x0200		! address = 512, in INITSEG
	mov	ax,#0x0200+SETUPLEN	! service 2, nr of sectors
	int	0x13			! read it
	jnc	ok_load_setup		! ok - continue

	push	ax			! dump error code
	call	print_nl
	mov	bp, sp
	call	print_hex
	pop	ax	
	
	xor	dl, dl			! reset FDC
	xor	ah, ah
	int	0x13
	j	load_setup

ok_load_setup:

! Get disk drive parameters, specifically nr of sectors/track

	xor	dl,dl
	mov	ah,#0x08		! AH=8 is get drive parameters
	int	0x13
	xor	ch,ch
	seg cs
	mov	sectors,cx
	mov	ax,#INITSEG
	mov	es,ax

! Print some inane message

	mov	ah,#0x03		! read cursor pos
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

print_nl:
	mov	ax, #0xe0d	! CR
	int	0x10
	mov	al, #0xa	! LF
	int 	0x10
	ret

!/*
! *	print_hex is for debugging purposes, and prints the word
! *	pointed to by ss:bp in hexadecmial.
!*/

print_hex:
	mov	cx, #4		! 4 hex digits
	mov	dx, (bp)	! load word into dx
print_digit:
	rol	dx, #4		! rotate so that lowest 4 bits are used
	mov	ah, #0xe	
	mov	al, dl		! mask off so we have only next nibble
	and	al, #0xf
	add	al, #0x30	! convert to 0 based digit, '0'
	cmp	al, #0x39	! check for overflow
	jbe	good_digit
	add	al, #0x41 - 0x30 - 0xa 	! 'A' - '0' - 0xa

good_digit:
	int	0x10
	loop	print_digit
	ret


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

