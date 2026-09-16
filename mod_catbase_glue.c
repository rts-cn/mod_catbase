/*
 * mod_catbase_glue.c -- mod_catbase 的 FreeSWITCH 模块外壳（C）
 *
 * 模块逻辑（load / shutdown / catbase 命令）写在 mod_catbase.cat 里，由 catbasecc 编译成
 * Zig 源码，再由 zig 编成目标文件。本文件只负责 FreeSWITCH 认的那一层 C ABI：
 * 模块接口表 + load/shutdown + 注册 API，然后把控制权交给 CatBase。
 *
 * 关于 gen/mod_catbase_abi.zig（由 Makefile 生成的那几行 Zig）：
 *   catbasecc 0.0.10 生成的入口都是 pub fn 而不是 export fn，Zig 不会把 pub 声明导出成
 *   C 符号（没被引用的还会被整个丢掉，即使被引用，符号名也会被 mangle 成
 *   "mod_catbase.xxx"），所以 C 无法直接链接到 CatBase 编译出来的函数。
 *   等 catbasecc 能导出 C 符号后，那个适配文件和下面的 extern 声明都可以删掉。
 */

#include <switch.h>
#include <stdint.h>

/* mod_catbase.cat 里的模块逻辑，由 ABI 适配层导出成 C 符号 */
extern int64_t cb_mod_catbase_load(int64_t module_interface, int64_t pool);
extern int64_t cb_mod_catbase_shutdown(void);
extern int64_t cb_mod_catbase_api(int64_t handle, const char *cmd);

/*
 * 给 CatBase 的回调：把一行写到 stream。
 * 往 stream 写字要调 switch_stream_handle_t::write_function（函数指针），CatBase 调不了，
 * 所以这一小段留在 C 侧，由 ABI 适配层把它作为 function 参数传给 CatBase。
 */
void cb_mod_catbase_write_line(int64_t handle, const char *data, size_t len)
{
	switch_stream_handle_t *stream = (switch_stream_handle_t *) (intptr_t) handle;

	if (!stream || !stream->write_function) {
		return;
	}

	stream->write_function(stream, "%.*s\n", (int) len, data);
}

/*
 * 对应 SWITCH_STANDARD_API(catbase_api)。
 * 命令逻辑在 mod_catbase.cat 里：这里只把 stream 句柄交过去，输出由 CatBase 通过上面的
 * 回调写回来。
 */
SWITCH_STANDARD_API(catbase_api)
{
	(void) session;

	cb_mod_catbase_api((int64_t) (intptr_t) stream, cmd ? cmd : "");

	return SWITCH_STATUS_SUCCESS;
}

SWITCH_MODULE_LOAD_FUNCTION(mod_catbase_load);
SWITCH_MODULE_SHUTDOWN_FUNCTION(mod_catbase_shutdown);
SWITCH_MODULE_DEFINITION(mod_catbase, mod_catbase_load, mod_catbase_shutdown, NULL);

SWITCH_MODULE_LOAD_FUNCTION(mod_catbase_load)
{
	switch_api_interface_t *api_interface;

	/* 模块必须把 module_interface 建出来并写回，否则加载器会拒绝：
	 * "Module failed to initialize its module_interface. Is this a valid module?" */
	*module_interface = switch_loadable_module_create_module_interface(pool, modname);

	if (!*module_interface) {
		return SWITCH_STATUS_MEMERR;
	}

	/* fs_cli -x "catbase <cmd>" */
	SWITCH_ADD_API(api_interface, "catbase", "mod_catbase API", catbase_api, "<cmd>");

	/* 交给 CatBase 侧的 mod_catbase_load(module_interface, pool)，返回值即模块状态 */
	return (switch_status_t) cb_mod_catbase_load((int64_t) (intptr_t) *module_interface, (int64_t) (intptr_t) pool);
}

SWITCH_MODULE_SHUTDOWN_FUNCTION(mod_catbase_shutdown)
{
	/* 交给 CatBase 侧的 mod_catbase_shutdown() */
	cb_mod_catbase_shutdown();

	return SWITCH_STATUS_SUCCESS;
}
