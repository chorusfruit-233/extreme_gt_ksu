# Extreme GT · KernelSU 双版本补丁

基于指定的 [Extreme GT 更新 JSON](https://vtools.oss-cn-beijing.aliyuncs.com/addin/extreme_gt.json) 拉取上游 4.2.1，构建两个独立版本：

| 版本后缀 | 模块 ID | 挂载方式 | 前提 |
| --- | --- | --- | --- |
| `hybrid_mount` | `extreme_gt_hybrid_mount` | 所有覆盖交给 meta-hybrid_mount，模块没有挂载入口 | KernelSU + 已启用的 Hybrid Mount |
| `susfs` | `extreme_gt_susfs` | `skip_mount` 明确跳过元模块，模块自行逐文件 bind 并协同 SUSFS | KernelSU + SUSFS 内核 + 已安装的 `ksu_susfs` |

对应产物为 `extreme_gt-4.2.1-ksu.4-hybrid_mount.zip` 和 `extreme_gt-4.2.1-ksu.4-susfs.zip`。两者修改相同配置，**只能启用其中一个**。

## 安装与切换

1. 先禁用旧版 `extreme_gt` 或另一个版本并重启，再安装选定版本。新 ID 不会自动覆盖或删除旧 ID；安装器拒绝与其他已启用版本共存。每次重装、更新或切换也应先禁用并重启，避免在已修改配置上重复提高阈值。
2. `hybrid_mount` 版：先安装、启用 [meta-hybrid_mount](https://github.com/Hybrid-Mount/meta-hybrid_mount) 并重启。要求安装器导出 `KSU_METAMODULE=hybrid_mount`（兼容 `meta-hybrid_mount`）或 `HYBRID_MOUNT=true`。
3. `susfs` 版：先安装与内核匹配的 [SUSFS 用户空间模块](https://github.com/sidex15/ksu_module_susfs)，确认 `/data/adb/ksu/bin/ksu_susfs` 可运行并重启。无需元模块；已安装元模块时也明确跳过本模块。
4. 在 KernelSU 管理器安装 ZIP，重启。在模块「操作」按钮比对覆盖内容。内容一致不能独立证明挂载来源；Hybrid 版在 Hybrid Mount 界面查看来源，SUSFS 版查看 `/data/adb/extreme_gt_susfs/mount.log`。

两个版本均移除了上游 `updateJson`，避免管理器用未适配版本覆盖。仅支持 KernelSU 管理器安装，不支持 Recovery 或 Magisk。

保留的上游行为包括提高充电温度阈值、修改 OEM 温控与锁帧配置、向部分温度传感器写入模拟温度和天玑节点调节。这会改变温控保护行为，兼容改造不代表这些策略已在你的机型验证。

## SUSFS 版的具体行为

- ZIP 内携带 `skip_mount`。安装时覆盖文件直接生成到 `payload/`，不提供可供元模块扫描的 `system/` 或顶层分区目录，也不调用元模块挂载接口。
- 在 KernelSU `post-mount.sh` 阶段自行挂载：该阶段位于元模块挂载之后、Zygote 启动之前；无元模块时仍由 KernelSU 调用。不会在晚启动服务中补挂载。自动标记模式拒绝 late-load 和启动完成后补挂载，必须正常重启。
- 安装与启动时均检查 `ksu_susfs show enabled_features`，要求 `CONFIG_KSU_SUSFS_SUS_MOUNT`。读取 `show version` 和工具帮助：SUSFS 2.x 使用内核 KSU-domain 挂载/克隆钩子的自动标记，不调用已移除的 `add_sus_mount`；旧版必须确实提供该命令才使用手动注册。
- 如果内核有 `CONFIG_KSU_SUSFS_TRY_UMOUNT` 且工具确实提供 `add_try_umount`，调用 `add_try_umount <目标> 1`；否则要求设备的 `/data/adb/ksud` 支持 `kernel umount add`，用 `--flags 2` 注册卸载规则。未满足接口条件则明确失败，不以普通 bind 冒充 SUSFS 协同。
- 所有覆盖为只读 bind（`ro,nosuid,nodev,noexec`），保留原配置 SELinux 标签。不下载、替换 SUSFS 二进制，不更改 SUSFS 全局隐藏设置。
- 先检查全部清单，再开始挂载。任意挂载或注册失败，按逆序卸载本次已挂载文件并记录日志。已登记的 SUSFS 卸载路径不会主动清除全局列表，重启后清空本次内核状态。无法保证在进程被强制杀死或内核异常时完成回滚。
- `/dev/extreme_gt_susfs.lock` 防止同一启动过程重复叠加挂载。只有挂载全部成功，`service.sh` 才继续执行上游节点调节；`system.prop` 仍由 KernelSU 独立加载。

**目标文件必须已存在。** SUSFS 版使用逐文件 bind，不在只读系统中创建挂载点，也不覆盖整个父目录。若上游天玑资源对应的 `.tp` 等目标不存在，安装会明确报错；此类 ROM 可使用 Hybrid Mount 版提供新增文件覆盖。内核缺少上述 SUSFS 接口、SELinux 拒绝操作或 ROM 提前读取配置时，需要实机排查，不能仅凭 ZIP 构建成功判断效果。

## 共同配置适配

- 移除上游 Magisk `META-INF` 入口、原始 `post-fs-data.sh` 和分区搬移逻辑。
- 支持 `/system`、`/vendor`、`/product`、`/system_ext`、`/odm`、`/my_product`、`/my_stock`、`/my_heytap` 配置路径。安装时解析现有文件的设备符号链接，对清单去重；Hybrid 版输出 `system/<partition>/...`，SUSFS 版输出 `payload/<partition>/...`。
- 安装过程只写模块目录与临时目录。即时 `setprop` 改为 `system.prop`，不再直接修改 `/data/system/refresh_rate_config.xml`，不依赖未定义的 `START_DIR`。
- 生成文件保留 ROM 的 SELinux 标签；文件 `0644`、目录 `0755`、启动入口 `0755`。
- 修复天玑脚本未读取 `soc`、PPM 索引截断、缺失节点写入、`fix_ttj_85.conf` 覆盖文件名错误。
- 修复 XML 贪婪替换、JSON 逗号丢失，充电配置仅修改数字行，支持含空格路径。

ROM 如果优先读取已有 `/data/system` 刷新率缓存，效果可能与上游不同。原版已直接修改的缓存、持久属性不会自动恢复。禁用或卸载后重启，文件覆盖与运行时节点修改才会撤销。

## 构建与源码

只需 Python 3 标准库即可打包：

```sh
python3 scripts/build.py                       # 同时构建两个版本
python3 scripts/build.py --variant hybrid_mount
python3 scripts/build.py --variant susfs
python3 scripts/build.py --fetch               # 重新下载并校验锁定上游版本
```

- `upstream/`：原始 ZIP、更新 JSON 和版本/SHA256 锁定记录。
- `module/`：共用源码及默认 Hybrid Mount 配置。
- `variants/susfs/`：SUSFS 版本元数据、挂载脚本、协同接口和 `skip_mount`。
- `patches/0001-kernelsu-<版本>.patch`：从原始 ZIP 到各版本完整源码的可重放补丁。
- `scripts/build.py`：合并共用源码与版本覆盖，确定性构建两个 ZIP 和 SHA256。
- `scripts/ci.py`：脚本语法、安装与实际隔离挂载测试、双版本补丁重放、ZIP 完整性和可复现校验。

锁定上游 4.2.1，不自动接受 JSON 中未审查的新版本。上游包未附完整许可证；作者与原始资源声明保留，不能据此推定任意再分发许可。

## GitHub Actions 与验证

推送、Pull Request 或 Actions → **Build KernelSU variants** → **Run workflow** 会触发构建。流程上传两个独立 artifact：

- `extreme-gt-hybrid_mount-运行编号`
- `extreme-gt-susfs-运行编号`

各自包含安装 ZIP、SHA256 和对应补丁，保留 30 天。解压 artifact 后安装里面的模块 ZIP，不要直接安装 artifact 外层 ZIP。手动构建时可勾选 **发布 Release**（`publish_release`，默认关闭）。勾选后，仅当测试、双版本构建及 artifact 上传全部成功，才创建 Release，附带两个安装 ZIP、各自 SHA256 和补丁。发布前再次校验 SHA256，先上传到草稿，上传成功后公开并标记为 Latest。

Release 标签为 `extreme-gt-运行ID-尝试次数`，指向本次构建提交；重跑使用新标签，不覆盖旧 Release。普通推送、PR 和未勾选的手动构建仅生成 artifacts。若发布在草稿阶段中断，可在 Releases 中检查该草稿。

本地执行与 CI 相同的验证（需 Linux、bubblewrap、patch、KernelSU x86_64 BusyBox）：

```sh
BUSYBOX=/path/to/KernelSU/userspace/ksud/bin/x86_64/busybox python3 scripts/ci.py
```

测试使用独立 user/mount 命名空间中的模拟 Android 分区，覆盖两种布局、元模块跳过、依赖拒绝、冲突检查、真实 bind/只读重挂载、SUSFS 调用、失败回滚和重复挂载保护。SUSFS/ksud 内核接口及 SELinux 使用测试替身；尚未在实体 Android 设备验证，不声称已经证明 SUSFS 隐藏或卸载效果。

协议参考：

- [KernelSU 模块指南](https://kernelsu.org/guide/module.html)、[元模块指南](https://kernelsu.org/guide/metamodule.html)。
- Hybrid Mount `b48729c3555734fac48e9898429505e19f277c7d` 的 `module/metainstall.sh` 与分区规划实现。
- SUSFS 用户空间模块 `c6a1c065efff9eaead049acf529a10bc93d34e75` 的特性检测与卸载登记。
- [SUSFS 通用工具](https://github.com/sidex15/susfs4ksu-binaries/tree/universal-binary) `041f69d7fe23a7bd928f9bd90eb3535774d00456` 的 `show enabled_features`、`add_sus_mount`、`add_try_umount` 接口。

### ksu.3 修复

修复内核启用 `SUS_MOUNT` 但用户空间工具已移除 `add_sus_mount` 时，全量覆盖被回滚的问题。兼容依据是 SUSFS **`gki-android14-6.1`** 分支提交 `273ae364c5b7c92ceb15634c9f075b6fc0501048`（v2.3.0）的 `clone_mnt()`、`susfs_is_current_ksu_domain()` 与 Kconfig；不是默认 master 的旧接口。启动日志会打印内核版本、挂载处理模式和卸载后端。

### ksu.4 执行按钮

两个版本使用各自独立的 `action.sh`。Hybrid Mount 版只展示元模块相关的文件比对；SUSFS 版展示 `skip_mount`、本次启动完成标记、文件比对和自行挂载日志。按钮均只用于诊断，不在启动完成后补挂载。SUSFS 日志在每次取得启动挂载锁后重新写入，避免旧版错误与本次结果混在一起；同一启动过程的重复调用不清空日志。
