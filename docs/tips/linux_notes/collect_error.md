### malloc 和memset的使用
```c
    IR2_INST** check_ins_num = (IR2_INST**) malloc(size * sizeof(IR2_INST*));
    assert(check_ins_num != NULL && " alloc check_ins_num space is afiled!");
    memset(check_ins_num, 0, size * sizeof(IR2_INST*));

    //在使用的check_ins_num的使用注意越界检查
   check_ins_num[index++] = ir2_ins_next;
   assert(index < size  && "index is so big");
```
