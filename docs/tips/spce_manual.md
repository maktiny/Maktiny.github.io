## 直接运行所有的测试样例
```c
./myrun1.sh test all 1

```

## 运行单个样例
1. 运行spec kill不掉的话，使用kill -9 $(pidof latx-i386或者x86_64)强力杀

```c
//运行当样例需要把myrun1.sh脚本中的脚本换成第三行
 runspec -c gcc8-2000-dyn.cfg -i $1 -n 1 $2 -I
./myrun1.sh ref (175)相应的编号 1

/*在目录下 spec2000/benchspec/CINT2000/175.vpr/run/00000018 
 *打开speccmd.md文件中复制跑的指令放到shell终端中直接运行
 */

../00000018/vpr_base.Of.gcc830.dyn net.in arch.in place.out dum.out -nodisp -place_only -init_t 5 -exit_t 0.005 -alpha_t 0.9412 -inner_num 2

```


