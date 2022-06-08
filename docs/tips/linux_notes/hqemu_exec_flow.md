### hqemu的hot path的NET算法
1. hqemu的NET算法的实现，使用了两个helper函数
```c

/* Helper function to perform trace prediction. */
void helper_NET_predict(CPUArchState *env, int id)
{
    auto &Tracer = getNETTracer(env);
    Tracer.Predict(&tbs[id]);//tbs是TB的cache，可以通过tcg_out_hotpatch中传入的tb->id索引,
}
```
2. 在该函数中实现paper中的hot path的NET算法，对6-shape和O-shape型的hot path进行标记
当TBs这个vector<TranslationBlock*> TBs数组达到满，或者遇到loop，就把数组放到OptimizeTrace()

```c
void NETTracer::Predict(TranslationBlock *tb)
{
    /* The trace prediction will terminate if a cyclic path is detected.
     * (i.e., current tb has existed in the tracing butter either in the
     * head or middle of the buffer.) */
    int LoopHeadIdx = -1;

#if defined(CONFIG_LLVM)
    /* Skip this trace if the next block is an annotated loop head and
     * is going to be included in the middle of a trace. */
    if (!TBs.empty() && TBs[0] != tb &&
        llvm_has_annotation(tb->pc, ANNOTATION_LOOP)) {
        goto trace_building;
    }
#endif

#if defined(USE_TRACETREE_ONLY)
    /* We would like to have a straight-line or O-shape trace.
     * (the 6-shape trace is excluded) */
    if (!TBs.empty() && tb == TBs[0]) {
        LoopHeadIdx = 0;
        goto trace_building;
    }
#elif defined(USE_RELAXED_NET)
    /* Find any cyclic path in recently recorded blocks. */
    for (int i = 0, e = TBs.size(); i != e; ++i) {
        if (tb == TBs[i]) {
            LoopHeadIdx = i;
            goto trace_building;
        }
    }
#else
    if (!TBs.empty()) {
        if (tb == TBs[0]) {
            /* Cyclic path. */
            LoopHeadIdx = 0;
            goto trace_building;
        }
        if (tb->pc <= TBs[TBs.size() - 1]->pc) {
            /* Backward branch. */
            goto trace_building;
        }
    }
#endif

    TBs.push_back(tb);

    /* Stop if the maximum prediction length is reached. */
    if (TBs.size() == PredictThreshold)
        goto trace_building;

    return;

trace_building:
    /* If the trace is a loop with a branch to the middle of the loop body,
     * we forms two sub-traces: (1) the loop starting from the loopback to
     * the end of the trace and (2) the original trace. */
    /* NOTE: We want to find more traces so the original trace is included. */

    if (LoopHeadIdx > 0) {
        /* Loopback at the middle. The sub-trace (1) is optimized first. */
        TBVec Loop(TBs.begin() + LoopHeadIdx, TBs.end());
        update_tb_mode(Loop[0], BLOCK_ACTIVE, BLOCK_TRACEHEAD);
        OptimizeTrace(Env, Loop, 0);
    }
    OptimizeTrace(Env, TBs, LoopHeadIdx);

    Reset();
}
```

### hqemu对热点代码的优化流程

### 热点代码转换成LLVM IR的流程
1. 
```c

int LLVMEnv::OptimizeTrace(CPUArchState *env, OptRequest Request)
{
    if (InitOnce == false)
        return 0;

    if (TransMode == TRANS_MODE_NONE)
        return 0;
    if (OptimizeOrSkip() == true)
        return 0;

    OptimizationInfo *Opt = Request.release();//每个opt是一个hot path，
    Opt->ComposeCFG();//构建控制流图

    if (TransMode == TRANS_MODE_HYBRIDS) {
        if (!TraceCacheFull) {
            if (!LLEnv->getMemoryManager()->isSizeAvailable())
                TraceCacheFull = true;
            else {
                LLVMTranslator *Translator = LLEnv->AcquireSingleTranslator();
                Translator->GenTrace(env, Opt); //把opt中的hot path TBs翻译成LLVM 的IR
                LLEnv->ReleaseSingleTranslator();
            }
        }

        if (TraceCacheFull)
            return 0;
    } else if (TransMode == TRANS_MODE_HYBRIDM) {
        /* Put the optimization request into the request queue and continue. */
        QM->Enqueue(Opt); //把生成LLVM IR的热点TBs放入到队列中等待后端线程进程LLVM pass的优化
    }

    return 1;
}


void LLVMTranslator::GenTrace(CPUArchState *env, OptimizationInfo *Opt)
{
    struct timeval start, end;
    if (SP->isEnabled())
        gettimeofday(&start, nullptr);

    TraceBuilder Builder(IF, Opt);
    for (;;) {
        GraphNode *Node = Builder.getNextNode();
        if (!Node)
            break;

        Builder.ConvertToTCGIR(Env);//先把guest 代码转化成(qemu)TCG IR

        if (DM.getDebugMode() & (DEBUG_INASM | DEBUG_OP))
            dump(Env, Node->getTB());

        Builder.ConvertToLLVMIR();//把TCG IR 转化为 LLVM IR

        if (Node->getTB()->mode == BLOCK_INVALID || Builder.isAborted()) {
            Abort(Builder);
            return;
        }
    }
    Builder.Finalize();

    if (SP->isEnabled()) {
        gettimeofday(&end, nullptr);
        Builder.getTrace()->setTransTime(&start, &end);
    }

    Commit(Builder); //设置paper中的每个TB头的jump地址(直接跳转到优化后的TB地址去执行优化后的代码)
}
```
2. 生成QEMU的TCG IR : 直接调用QEMU的函数gen_intermediate_code()

```c

void TraceBuilder::ConvertToTCGIR(CPUArchState *env)
{
    TranslationBlock *tb = CurrNode->getTB();

    if (LLEnv->isTraceMode()) {
        env->image_base = (uintptr_t)tb->image - tb->pc;
        tcg_copy_state(env, tb);
    }

    tcg_func_start(&tcg_ctx, tb);
    gen_intermediate_code(env, tb);//QEMU中生成中间码TCG IR的函数
    tcg_liveness_analysis(&tcg_ctx);
}
```
3. 生成LLVM 的 IR
```c

void TraceBuilder::ConvertToLLVMIR()
{
    IF->CreateBlock();

    auto OpcFunc = (IRFactory::FuncPtr *)IF->getOpcFunc();
    TCGArg *VecArgs = tcg_ctx.vec_opparam_buf;

    IF->NI.setTB(CurrNode->getTB());
    for (int oi = tcg_ctx.gen_first_op_idx; oi >= 0; ) {
        TCGOp * const op = &tcg_ctx.gen_op_buf[oi];
        TCGArg *args = &tcg_ctx.gen_opparam_buf[op->args];
        oi = op->next;

        if (isVecOp(op->opc)) {
            args = VecArgs;
            VecArgs += 3;
        }

        IF->NI.setOp(op);
        (IF->*OpcFunc[op->opc])(args);

        if (isAborted()) {
            IF->DeleteSession();
            return;
        }
    }
}
```
