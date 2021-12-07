# linux kernel debug tips
## 环境配置参考
- https://medium.com/@daeseok.youn/prepare-the-environment-for-developing-linux-kernel-with-qemu-c55e37ba8ade
# 先qemu运行kernel
```
qemu-system-x86_64 -s -S -kernel arch/x86_64/boot/bzImage -boot c -m 2048M -hda buildroot/output/images/rootfs.ext2 -append "root=/dev/sda rw console=ttyS0,115200 acpi=off nokaslr" -serial stdio -display none

//没有安装Root file system系统
qemu-system-x86_64 -s -S -no-kvm -kernel arch/x86/boot/bzImage -hda /dev/zero -append "root=/dev/zero console=ttyS0 nokaslr" -serial stdio -display none
```

## 另一终端运行gdb
```
gdb ./vmlinux
```
### 然后启动连接
- `target remote:1234`
-  ok 现在可以开始愉快的debug了

## FlameGraph的使用
- 参考: https://yohei-a.hatenablog.jp/entry/20150706/1436208007
- 或者: https://github.com/Martins3/Martins3.github.io/blob/master/docs/tips-reading-kernel.md
### 步骤
1. `perf record -a -g -F75000 dd if=/dev/zero of=/tmp/test.dat bs=1024K count=1000`
2. 
```
    perf script> perf_data.txt \
    perl stackcollapse-perf.pl perf_data.txt | \
    perl flamegraph.pl --title "trace" > flamegraph_dd.svg
```
3. 用浏览器打开生成的svg图.

## bpftrace
- `sudo bpftrace -e 't:block:block_rq_insert { @[kstack] = count(); }`
- 具体语法: https://github.com/iovisor/bpftrace/blob/master/docs/reference_guide.md 

```
Attaching 1 probe...
^C

@[
    blk_mq_sched_request_inserted+61
    blk_mq_sched_request_inserted+61
    dd_insert_requests+113
    blk_mq_sched_insert_requests+99
    blk_mq_flush_plug_list+262
    blk_flush_plug_list+227
    blk_finish_plug+38
    jbd2_journal_commit_transaction+3749
    kjournald2+182
    kthread+299
    ret_from_fork+34
]: 1
@[

export ALL_PROXY=socks5://localhost:1089
export http_proxy=socks5://localhost:1089
export https_proxy=http://localhost:8889


```
