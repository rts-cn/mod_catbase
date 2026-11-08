# mod_catbase

使用 CatBase 语言写了一个 FreeSWITCH 模块。

https://catbase-lang.com/

CatBase 还很年轻，期待越来越好。

## 编译

依赖 CatBase 0.1.8 以上，0.0.10 也可以支持，修改 Makefile 中 catcc 的路径即可。

将 catbase 放到 `/usr/local/catbase`，或修改 Makefile 中的路径。

```
make
make install
```

在 FreeSWITCH 中

```
freeswitch> load mod_catbase
freeswitch> catbase hello
```

## 输出示例

```
freeswitch@seven-o> load mod_catbase
2026-11-08 15:43:11.429932 95.17% [INFO] switch_time.c:1437 Timezone reloaded 597 definitions
2026-11-08 15:43:11.429932 95.17% [NOTICE] mod_catbase.cat:0 mod_catbase loaded
2026-11-08 15:43:11.429932 95.17% [CONSOLE] switch_loadable_module.c:1833 Successfully Loaded [mod_catbase]

+OK Reloading XML
+OK

2026-11-08 15:43:11.429932 95.17% [NOTICE] switch_loadable_module.c:448 Adding API Function 'catbase'
freeswitch@seven-o> catbase hello

mod_catbase: hello

freeswitch@seven-o>
```
