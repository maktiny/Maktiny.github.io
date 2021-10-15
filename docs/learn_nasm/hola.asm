;---------------------------
;using c lib ary 
;---------------------------
      global main
      extern puts

      section   .text

main: mov       rdi, message 
      call      puts 
      ret 
message: 
      db        "hola,numdo",0
