HQEMU的代码框架

1. 在QEMU的main()函数中初始化LLVM的环境

   ```c
                                                 main()<QEMU>
                                                    |
                                                llvm_init()
                                                     |
                                                CreateLLVMEnv()//开始初始化LLVMEnv变量（调用LLVMEnv()构造函数）
                                                     |
                                                  LLVMEnv()//创建一个TraceCache和Translator
                                                     |
                                                  CreateTranslator()//调用translator的构造函数和根据translator的数量初始化线程
                                                     |
                      -----------------------------------------------------------------------
                      |                                                                  |
                 StartThread()                                                     LLVMTranslator()
                     |                                                                   |
                     |                                                             InitializeModule();
                     |                                                             InitializeType();//初始化IRFactory()的数据
       			  |																InitializeTarget();//获取CPUArchState()的数据
       			  | 															InitializeHelpers();
       			  |																InitializeDisasm();
                 WorkerFunc()/*让线程去执行该函数*/                                   IRFactory()//translator最重要的数据结构
   ```

   <link rel="stylesheet" href="//cdn.bootcss.com/gitalk/1.5.0/gitalk.min.css">
<script src="//cdn.bootcss.com/gitalk/1.5.0/gitalk.min.js"></script>
<div id="gitalk-container" style="margin: 30px;padding-bottom: 30px;"></div>
         <script>
            var gitalk = new Gitalk({
                clientID: '6ffe2db84139272698af', // GitHub Application Client ID
                clientSecret: 'f0ca780aa3b773a31ab646f1f53a81d16d83da2f', // GitHub Application Client Secret
                repo: 'Maktiny.github.io',      // 存放评论的仓库
                owner: 'Maktiny',          // 仓库的创建者，
                admin: [Maktiny],        // 如果仓库有多个人可以操作，那么在这里以数组形式写出
                id: md5(location.pathname),      // 用于标记评论是哪个页面的，确保唯一，并且长度小于50
                title: document.title,
                body:  '文章链接：'+ decodeURIComponent(location.origin+location.pathname),
            })
            gitalk.render('gitalk-container');    // 渲染Gitalk评论组件
        </script>
