#
# mod_catbase - 用 CatBase 写的 FreeSWITCH 模块
#
#   make          # 编译出 mod_catbase.so
#   make check    # 只把 CatBase 部分编成可执行文件跑一遍（验证模块逻辑 / FFI）
#   make install  # 安装到 $(MOD_DIR)，然后 fs_cli -x "load mod_catbase"
#   make clean
#
# 路径可按需覆盖，例如：
#   make CATBASE=/usr/local/catbase FS_ROOT=/usr/local/freeswitch
#
# 构建步骤：
#   1. catbasecc 编译 mod_catbase.cat，生成 Zig 源码 $(CATBASE)/runtime/mod_catbase.zig
#   2. 生成 $(GEN_DIR)/mod_catbase_abi.zig（C ABI 适配层，内容见下面的 define）
#   3. zig 编译 [适配层 + mod_catbase_glue.c] -> mod_catbase.so
#
# 第 2 步的由来：catbasecc 0.0.10 生成的入口是 pub fn 而不是 export fn，Zig 不会把
# pub 声明放进符号表（未被引用的直接丢掉，被引用的符号名也会被 mangle 成
# "mod_catbase.xxx"），所以 C 链接不到 CatBase 编译出来的函数，需要几行 export fn
# 做 C ABI 适配。等 catbasecc 支持导出 C 符号后，第 2 步和 mod_catbase_glue.c 里的
# extern 声明都可以删掉。

CATBASE ?= /usr/src/cb/catbase
CATCC   ?= $(CATBASE)/bin/catbasecc
ZIG     ?= /usr/local/zig/zig
FS_ROOT ?= /usr/local/freeswitch
FS_INC  ?= $(FS_ROOT)/include/freeswitch
FS_LIB  ?= $(FS_ROOT)/lib
MOD_DIR ?= $(FS_ROOT)/mod

MOD_NAME := mod_catbase
SRC      := $(MOD_NAME).cat
GLUE_C   := $(MOD_NAME)_glue.c
GEN_DIR  := gen
GEN_ZIG  := $(GEN_DIR)/$(MOD_NAME).zig
GEN_ABI  := $(GEN_DIR)/$(MOD_NAME)_abi.zig
SO       := $(MOD_NAME).so

ZIGFLAGS := -dynamic -fPIC -lc -O ReleaseSmall --name $(MOD_NAME)
FSLIBS   := -L$(FS_LIB) -lfreeswitch

# C ABI 适配层的内容（由 $(file ...) 写到 $(GEN_ABI)）
define MOD_CATBASE_ABI_ZIG
// 本文件由 Makefile 生成，请勿手工修改。
// catbasecc 只生成 pub fn（不是 export fn），C 链接不到 CatBase 编译出来的函数，
// 所以这里用 export fn 把它们暴露成 C ABI，并把「写一行到 stream」作为 function
// 参数传给 CatBase（见 mod_catbase.cat: catbase_api）。
const std = @import("std");
const cb = @import("mod_catbase.zig");

// 由 mod_catbase_glue.c 实现
extern fn cb_mod_catbase_write_line(handle: i64, data: [*c]const u8, len: usize) callconv(.C) void;

fn write_line(handle: i64, data: []u8) void {
    cb_mod_catbase_write_line(handle, data.ptr, data.len);
}

export fn cb_mod_catbase_load(module_interface: i64, pool: i64) callconv(.C) i64 {
    return cb.mod_catbase_load(module_interface, pool);
}

export fn cb_mod_catbase_shutdown() callconv(.C) i64 {
    return cb.mod_catbase_shutdown();
}

export fn cb_mod_catbase_api(handle: i64, cmd: [*c]const u8) callconv(.C) i64 {
    return cb.catbase_api(handle, @constCast(std.mem.span(cmd)), write_line);
}
endef

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

# 2. 生成 C ABI 适配层
$(GEN_ABI): $(GEN_ZIG) Makefile
	$(file >$@,$(MOD_CATBASE_ABI_ZIG))

# 3. 适配层 + C 模块外壳 -> mod_catbase.so
#    zig 编译 mod_catbase_glue.c 时用 -I$(FS_INC) 找 switch.h，链接时找 libfreeswitch
$(SO): $(GLUE_C) $(GEN_ABI)
	$(ZIG) build-lib $(GEN_ABI) -cflags -I$(FS_INC) -- $(GLUE_C) $(ZIGFLAGS) $(FSLIBS)
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
