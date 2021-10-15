;--------------------------------------
;standalone program without c lib 
;so program begin from _start, _statr does some initialization
;and then it call main, main is the your write code in c program
;main does some thing that you want it to do, and then it does some 
;clean up and issues syscall for exit.
;---------------------------------------
    global        _start 
    section       .text

_start: mov rax, 1
         mov rdi, 1
         mov rsi, message
         mov rdx, 12
         syscall 
         mov rax, 60
         xor rdi, rdi
         syscall 

         section  .data

message: db       "hello, world", 10
