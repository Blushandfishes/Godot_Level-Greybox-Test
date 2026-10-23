# MCP 接入与编辑器验收

本工程使用 Godot 4.7.2、Godot AI 插件/服务4.3.0，连接127.0.0.1:8001与9501。Codex沿用已验证的本机虚拟环境启动桥；安装器首次启动产生的默认uvx客户端条目已恢复为原有本机桥，其他配置未更改。重新启动编辑器后连接已验证。

编辑器选中瓦片层时，初版预设图案触发了Godot原生崩溃。根因是 TileMapPattern.set_cell() 的默认alternative_tile为-1，与 TileMapLayer.set_cell() 的默认0不同。生成器初版未显式传0，图案中出现不存在的替代编号65535，编辑器异步图案缩略图绘制因此崩溃。

最终修复：两个pattern生成函数均显式传alternative_tile=0，并重新生成图案。验证器也检查每个图案单元的source、atlas坐标和alternative有效性。排查过程中对MCP handler的临时修改已全部恢复；最终Godot AI插件保持原版。

生成场景显式引用 tilesets/ 中的外部资源，避免内嵌独立副本，确保以后修改瓦片集能同步到使用它的各关卡。
