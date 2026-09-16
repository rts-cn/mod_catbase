// mod_catbase_glue.zig
//
// mod_catbase 的 C ABI 导出层（临时）。
//
// FreeSWITCH 加载模块的过程（src/switch_loadable_module.c）：
//   1. dlopen(模块 .so)
//   2. dlsym() 找数据符号 "<modname>_module_interface"
//      （类型为 switch_loadable_module_function_table_t）
//   3. 调用表里的 load / shutdown 函数指针
//   4. load 返回后检查 *module_interface 是否被初始化，没初始化就拒绝加载
//
// catbasecc 0.0.10 编译共享库时只生成 pub fn / pub const，而 Zig 只会把
// export fn / export const 放进动态符号表（未被引用的 pub 声明会被直接丢掉），
// 所以 `catbasecc -shared` 产出的 .so 里既没有模块接口符号、也没有 DT_NEEDED，
// ldd 会显示 "statically linked"，FreeSWITCH 也找不到入口。
//
// 这里用 Zig 把这一层补齐（导出入口 + 模块接口表 + 创建并写回 module_interface），
// 转发到 mod_catbase.cat 生成的代码（gen/mod_catbase.zig）。模块逻辑写在 mod_catbase.cat。
//
// 等 catbasecc 能导出 C 符号后，本文件和 Makefile 里的 zig 步骤都可以删掉，
// 直接 `catbasecc -shared mod_catbase.cat` 即可。

// 生成的 CatBase 代码（由 Makefile 第一步拷到 gen/ 下）
const cb = @import("gen/mod_catbase.zig");

const SWITCH_STATUS_SUCCESS: c_int = 0;
const SWITCH_STATUS_MEMERR: c_int = 6;

const MODULE_NAME: [*:0]const u8 = "mod_catbase";
const SWITCH_API_VERSION: c_int = 5;

// switch_core.h:
//   switch_loadable_module_interface_t *switch_loadable_module_create_module_interface(
//           switch_memory_pool_t *pool, const char *name);
extern fn switch_loadable_module_create_module_interface(pool: ?*anyopaque, name: [*:0]const u8) ?*anyopaque;

// switch_types.h:
//   typedef switch_status_t (*switch_module_load_t)(switch_loadable_module_interface_t **, switch_memory_pool_t *);
//   typedef switch_status_t (*switch_module_shutdown_t)(void);
//   typedef switch_status_t (*switch_module_runtime_t)(void);
const SwitchModuleLoad = *const fn (?*anyopaque, ?*anyopaque) callconv(.C) c_int;
const SwitchModuleVoid = *const fn () callconv(.C) c_int;

// switch_types.h:
//   typedef struct switch_loadable_module_function_table {
//       int switch_api_version;
//       switch_module_load_t load;
//       switch_module_shutdown_t shutdown;
//       switch_module_runtime_t runtime;
//       switch_module_flag_t flags;      // uint32_t
//   } switch_loadable_module_function_table_t;
const SwitchLoadableModuleFunctionTable = extern struct {
    switch_api_version: c_int,
    load: SwitchModuleLoad,
    shutdown: SwitchModuleVoid,
    runtime: ?SwitchModuleVoid,
    flags: c_uint,
};

export fn mod_catbase_load(module_interface: ?*anyopaque, pool: ?*anyopaque) callconv(.C) c_int {
    // 第一个参数是 switch_loadable_module_interface_t **：模块必须把
    // create_module_interface() 的结果写回这个槽，否则加载器会说
    // "Module failed to initialize its module_interface"。
    const out: *?*anyopaque = @ptrCast(@alignCast(module_interface orelse return SWITCH_STATUS_MEMERR));
    out.* = switch_loadable_module_create_module_interface(pool, MODULE_NAME);
    const created = out.* orelse return SWITCH_STATUS_MEMERR;

    // 把建好的 switch_loadable_module_interface_t * 和 pool 交给 CatBase 侧的模块逻辑
    const interface_addr: i64 = @intCast(@intFromPtr(created));
    const pool_addr: i64 = if (pool) |ptr| @intCast(@intFromPtr(ptr)) else 0;
    return @intCast(cb.mod_catbase_load(interface_addr, pool_addr));
}

export fn mod_catbase_shutdown() callconv(.C) c_int {
    return @intCast(cb.mod_catbase_shutdown());
}

export const mod_catbase_module_interface: SwitchLoadableModuleFunctionTable = .{
    .switch_api_version = SWITCH_API_VERSION,
    .load = mod_catbase_load,
    .shutdown = mod_catbase_shutdown,
    .runtime = null,
    .flags = 0,
};
