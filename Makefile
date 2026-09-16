#
# mod_catbase - 用 CatBase 写的 FreeSWITCH 模块
#
#   make          # 编译出 mod_catbase.so
#   make check    # 只编 CatBase 部分成可执行文件跑一遍（验证 FFI / 模块逻辑）
#   make install  # 安装到 $(MOD_DIR)
#   make clean
#
# 路径可按需覆盖，例如：
#   make CATBASE=/usr/local/catbase FS_ROOT=/usr/local/freeswitch
#
# 构建分两步（原因见 mod_catbase_glue.zig 顶部说明）：
#   1. catbasecc 编译 mod_catbase.cat，生成 Zig 源码 $(CATBASE)/runtime/mod_catbase.zig
#   2. zig 编译 mod_catbase_glue.zig（导出 C ABI + 模块接口表）得到 mod_catbase.so
# catbasecc 0.0.10 的 `-shared` 只生成 pub fn/pub const，Zig 不会把它们放进动态符号表，
# 产出的 .so 没有模块入口符号、也没有 DT_NEEDED（ldd 显示 statically linked）。
# 等 catbasecc 支持导出 C 符号后，第 2 步换成 `catbasecc -shared mod_catbase.cat` 即可。

CATBASE ?= /usr/src/cb/catbase
CATCC   ?= $(CATBASE)/bin/catbasecc
ZIG     ?= /usr/local/zig/zig
FS_ROOT ?= /usr/local/freeswitch
MOD_DIR ?= $(FS_ROOT)/mod

MOD_NAME := mod_catbase
SRC      := $(MOD_NAME).cat
GLUE     := $(MOD_NAME)_glue.zig
GEN_DIR  := gen
GEN_ZIG  := $(GEN_DIR)/$(MOD_NAME).zig
SO       := $(MOD_NAME).so

ZIGFLAGS := -dynamic -fPIC -lc -O ReleaseSmall --name $(MOD_NAME)
FSLIBS   := -L$(FS_ROOT)/lib -lfreeswitch

all: $(SO)

# 1. CatBase -> Zig 源码（生成物由编译器放在 $(CATBASE)/runtime/ 下）
$(GEN_ZIG): $(SRC)
	$(CATCC) -shared -o $(MOD_NAME) $(SRC)
	@test -f $(CATBASE)/runtime/$(MOD_NAME).zig || \
		{ echo "error: 未生成 $(CATBASE)/runtime/$(MOD_NAME).zig，请确认 conf/config.conf 里 keep_zig_files = true"; exit 1; }
	mkdir -p $(GEN_DIR)
	cp -f $(CATBASE)/runtime/$(MOD_NAME).zig $(GEN_ZIG)
	rm -rf $(GEN_DIR)/runtime
	cp -r $(CATBASE)/runtime/runtime $(GEN_DIR)/

# 2. Zig -> mod_catbase.so（导出层引用生成的代码，符号因此被真正编进动态库）
$(SO): $(GLUE) $(GEN_ZIG)
	$(ZIG) build-lib $(GLUE) $(ZIGFLAGS) $(FSLIBS)
	mv -f lib$(MOD_NAME).so $(SO)

check: $(SRC)
	$(CATCC) -o $(MOD_NAME) $(SRC)
	./$(MOD_NAME)

install: $(SO)
	install -d $(MOD_DIR)
	install -m 0755 $(SO) $(MOD_DIR)/$(SO)

clean:
	rm -rf $(GEN_DIR) $(SO) lib$(MOD_NAME).so lib$(MOD_NAME).so.o $(MOD_NAME) $(MOD_NAME).o

.PHONY: all check install clean
