
Thread 1 "latx-x86_64" received signal SIGSEGV, Segmentation fault.
0x000000ffe801f770 in code_gen_buffer ()
(gdb) x/10i $pc 
=> 0xffe801f770 <code_gen_buffer+127688>:	st.d	$r13,$r14,0 //当前出错的PC
   0xffe801f774 <code_gen_buffer+127692>:	st.d	$r22,$r31,8(0x8)
   0xffe801f778 <code_gen_buffer+127696>:	st.d	$r6,$r31,432(0x1b0)
   0xffe801f77c <code_gen_buffer+127700>:	st.d	$r7,$r31,440(0x1b8)
   0xffe801f780 <code_gen_buffer+127704>:	st.d	$r8,$r31,448(0x1c0)
   0xffe801f784 <code_gen_buffer+127708>:	st.d	$r9,$r31,456(0x1c8)
   0xffe801f788 <code_gen_buffer+127712>:	st.d	$r17,$r31,464(0x1d0)
   0xffe801f78c <code_gen_buffer+127716>:	st.d	$r18,$r31,472(0x1d8)
   0xffe801f790 <code_gen_buffer+127720>:	st.d	$r19,$r31,480(0x1e0)
   0xffe801f794 <code_gen_buffer+127724>:	st.d	$r20,$r31,488(0x1e8)
(gdb) x/10i $pc - 4
   0xffe801f76c <code_gen_buffer+127684>:	ld.d	$r14,$r31,328(0x148)
=> 0xffe801f770 <code_gen_buffer+127688>:	st.d	$r13,$r14,0
   0xffe801f774 <code_gen_buffer+127692>:	st.d	$r22,$r31,8(0x8)
   0xffe801f778 <code_gen_buffer+127696>:	st.d	$r6,$r31,432(0x1b0)
   0xffe801f77c <code_gen_buffer+127700>:	st.d	$r7,$r31,440(0x1b8)
   0xffe801f780 <code_gen_buffer+127704>:	st.d	$r8,$r31,448(0x1c0)
   0xffe801f784 <code_gen_buffer+127708>:	st.d	$r9,$r31,456(0x1c8)
   0xffe801f788 <code_gen_buffer+127712>:	st.d	$r17,$r31,464(0x1d0)
   0xffe801f78c <code_gen_buffer+127716>:	st.d	$r18,$r31,472(0x1d8)
   0xffe801f790 <code_gen_buffer+127720>:	st.d	$r19,$r31,480(0x1e0)
(gdb) x $r14
   0x0:	Cannot access memory at address 0x0
(gdb) p/x $r14 //显示当前寄存器的值
$1 = 0x0
(gdb) x/10i $pc - 100 //显示当前pc - 100的地址的指令
