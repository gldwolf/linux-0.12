#!/bin/bash

# 修改所有的 Makefile
find ./ -name 'Makefile' | xargs -I{} sed -i -e 's/=gas/=as/g' -e 's/=gld/=ld/g' -e 's/as$/as --32/g' -e 's/-fcombine-regs //g' -e 's/-mstring-insns//g' -e 's/CFLAGS.*=/CFLAGS\t=-m32 /g' -e 's/=ld$/=ld -m elf_i386 -e startup_32 -Ttext 0/g' -e 's/-Wall/-w/g' -e 's/=gar/=ar/g' -e "s/-O //g" {}

# 修改 asm 文件
egrep --exclude=modifier.sh -rn "align 2" ./ 2>/dev/null | awk -F : '{print $1}' | uniq | xargs -I {} sed -i 's/align 2/align 4/g' {}
egrep --exclude=modifier.sh -rn "align 3" ./ 2>/dev/null | awk -F : '{print $1}' | uniq | xargs -I {} sed -i 's/align 3/align 8/g' {}

# Modify c comment to asm comment in boot/bootsect.S
sed -i -e '300,311s/^/!&/g' -e '346,349s/^/!&/g' -e '370,374s/^/!&/g' -e '69,84s/^/!&/g' boot/bootsect.S

# 删除 include/unistd.h 中的 pause()、sync()、fork() 函数定义
sed -i -e 's/int fork(void);/\/\/&/g' -e 's/int sync(void);/\/\/&/g' -e 's/int pause(void);/\/\/&/g' include/unistd.h

# 替换 printf 为 printw 防止冲突
sed -i 's/ printf/ printw/g' init/main.c

# 删除内嵌汇编中的寄存器
find -type f -exec sed -i 's/:\"\w\{2\}\"\(,\"\w\{2\}\"\)*)/:) /g' {} \;

# 将 extern inline 替换为 static inline
sed -i 's/^extern inline /static inline /g' include/asm/segment.h
sed -i 's/^extern inline /static inline /g' include/linux/mm.h
sed -i 's/^extern inline /static inline /g' include/string.h
sed -i 's/^extern inline /static inline /g' kernel/blk_drv/blk.h

# 修改 fs/exec.c 162 行
sed -i -e "161s/\!(pag = (char \*) page/\(\!page/g" -e "162s/pag =.*page/page/g" -e "164a\                else\n                    pag = (char *) page[p/PAGE_SIZE];" fs/exec.c
sed -i '155a\        cp = get_free_page();' lib/malloc.c
sed -i '157c\        bdesc->page = bdesc->freeptr = (void *) cp;' lib/malloc.c

# 删除汇编文件中 c 变量及方法引用中的 _ 前缀
sed -ri "s/\b_([a-zA-Z])/\1/g" boot/head.s
sed -ri "s/\b_([a-zA-Z])/\1/g" kernel/sys_call.s
sed -ri "s/\b_([a-zA-Z])/\1/g" kernel/chr_drv/console.c
sed -ri "s/\b_([a-zA-Z])/\1/g" mm/page.s
sed -ri "s/\b_([a-zA-Z])/\1/g" kernel/asm.s
sed -ri "s/\b_([a-zA-Z])/\1/g" include/linux/sched.h
sed -ri "s/\b_([a-zA-Z])/\1/g" kernel/sched.c
sed -ri "s/\b_([a-zA-Z])/\1/g" kernel/fork.c
sed -ri "s/\b_([a-zA-Z])/\1/g" kernel/chr_drv/serial.c
sed -ri "s/\b_([a-zA-Z])/\1/g" kernel/chr_drv/rs_io.s
sed -ri "s/\b_([a-zA-Z])/\1/g" kernel/chr_drv/keyboard.S
sed -i -e '277s/#define get_base/#define get_base_asm/g' -e '262s/#define set_base/#define set_base_asm/g' include/linux/sched.h
sed -i -e '263s/#define set_limit/#define set_limit_asm/g' include/linux/sched.h
sed -i -e 's/get_base/get_base_asm/g' kernel/exit.c
sed -i -e 's/get_base/get_base_asm/g' kernel/traps.c
sed -i -e 's/get_base/get_base_asm/g' -e 's/set_base/set_base_asm/g' kernel/fork.c
sed -i -e 's/get_base/get_base_asm/g' -e 's/set_base/set_base_asm/g' -e 's/set_limit/set_limit_asm/g' fs/exec.c
sed -ri "s/([[:blank:]])printf/\1printw/g" init/main.c

# 修改 inline 问题
sed -i '84s/inline //g' fs/buffer.c
sed -i '270s/inline //g' kernel/blk_drv/floppy.c

# _start 问题
sed -i '15s/$/&,startup_32/g' boot/head.s

# 安装 32 位库 
#sudo yum install glibc-devel.i686
#sudo yum install libgcc.i686

# 添加 MAJOR 和 MINOR 到 tools/build.c
sed -i '35a#define MINOR(a) ((a)&0xff)\n#define MAJOR(a) (((unsigned)(a))>>8)' tools/build.c

# 将 ROOT_DEV 改为 FLOPPY，SWAP 置空
sed -i -e 's/ROOT_DEV=\/dev\/hd6/ROOT_DEV=FLOPPY/g' -e 's/SWAP_DEV=.*$/SWAP_DEV=/g' Makefile

# 修改程序入口点索引
sed -i -e '190s/5/6/g' -e '190s/$/& \/\/ 判断入口点地址是否为 0x0/g' tools/build.c
