# Extreme GT · KernelSU / Hybrid Mount 补丁项目

从指定的 [更新 JSON](https://vtools.oss-cn-beijing.aliyuncs.com/addin/extreme_gt.json) 拉取 Extreme GT 4.2.1，改造成面向 **KernelSU + meta-hybrid_mount** 的普通模块。模块自身没有挂载代码，覆盖文件由 Hybrid Mount 统一接管。

## 安装

1. 在 KernelSU 中安装、启用 [meta-hybrid_mount](https://github.com/Hybrid-Mount/meta-hybrid_mount) 并重启。适配依据是其 `b48729c3555734fac48e9898429505e19f277c7d` 提交：安装器导出 `KSU_METAMODULE=hybrid_mount`，或 `HYBRID_MOUNT=true`。未提供这些标记的旧版本会被拒绝，应先升级元模块。
2. 若已安装上游 Extreme GT，先禁用并重启，再安装本包，避免在已覆盖的配置上重复提高阈值。每次重装或更新本模块也按此顺序操作。
3. 安装 `dist/extreme_gt-4.2.1-ksu.1.zip`，重启。
4. 在模块的「操作」按钮比对覆盖文件内容，并在 Hybrid Mount 界面核查实际挂载来源。内容一致只是辅助诊断，不能独立证明挂载成功。

模块 ID 保留 `extreme_gt`，因此会替换同 ID 的上游模块，而不是并行启用两份。更新地址已经移除，避免管理器用未适配的上游包覆盖本版本。不支持 Recovery、Magisk 或未启用 Hybrid Mount 的安装。

**保留的上游行为**包括提高充电温度阈值、修改 OEM 温控与锁帧配置、向部分温度传感器写入模拟温度和天玑节点调节。这会改变温控保护行为；KSU 兼容改造不代表这些策略已在你的机型上验证。

## 适配内容

- 删除 `post-fs-data.sh` 内的逐文件 bind mount；移除 Magisk `META-INF` 安装入口。
- 删除原有 `handle_partition`、目录搬移和自行创建分区别名的代码。文件使用 `system/<partition>/...` 布局，实际挂载与别名由 Hybrid Mount 管理。
- `/vendor`、`/product`、`/system_ext`、`/odm`、`/my_product`、`/my_stock`、`/my_heytap` 配置统一映射；存在的文件先解析设备符号链接，避免重复路径输出到错误分区。`my_heytap` 也加入扫描。
- 安装过程只写模块目录与 KernelSU 临时目录。原来的即时 `setprop` 改为 `system.prop`，不再修改 `/data/system/refresh_rate_config.xml` 或依赖未定义的 `START_DIR`。
- 生成文件保留设备原始 SELinux 标签，文件为 `0644`，目录为 `0755`，运行入口为 `0755`。
- 修复天玑启动脚本未读取 `soc`、PPM 索引截断、缺失节点写入报错、`fix_ttj_85.conf` 未按原文件名覆盖等问题。
- 修复上游 XML 替换吞掉相邻结束标签、FPS 属性贪婪匹配、JSON 逗号丢失；充电配置只修改数字行，文件路径支持空格。

不对 `/data/system` 做 systemless 覆盖，因此 ROM 若优先读取已有刷新率缓存，该项效果可能与上游不同。已有上游模块曾经直接修改的缓存、持久属性，本项目不会猜测原值或自动恢复。禁用/卸载后需要重启；新生成覆盖与本项目的运行时节点修改随重启撤销。

## 项目结构与构建

- `upstream/`：实际下载的原始 ZIP、更新 JSON、版本与 SHA256 锁定记录。
- `module/`：可审查、可编辑的最终模块源码和上游天玑资源。
- `patches/0001-kernelsu-hybrid-mount.patch`：完整原包到最终源码的统一 diff，构建时更新。
- `scripts/build.py`：校验原包并确定性打包，不执行上游脚本。
- `tests/test_install.py`：隔离文件系统中的真实 BusyBox ash 安装测试。
- `dist/`：可安装 ZIP 与 SHA256 校验文件。

只需要 Python 3 标准库：

```sh
python3 scripts/build.py
# 重新下载锁定版本；SHA256 不同则拒绝写入
python3 scripts/build.py --fetch
```

目前有意锁定 4.2.1，不会自动接受 JSON 中未来的任意新版本。更新上游时先审查新脚本，再更新 `upstream/lock.json` 与 `module/`，重跑测试及构建。上游包没有附带完整许可证；作者与资源原始声明保留，不能据此推定获得任意再分发许可。

## 验证

Linux 上安装 `bubblewrap`，将 `BUSYBOX` 指向 KernelSU 的 **x86_64** BusyBox：

```sh
BUSYBOX=/path/to/KernelSU/userspace/ksud/bin/x86_64/busybox \
  python3 -m unittest discover -s tests -v
```

测试在独立命名空间中模拟 Android 分区，验证通用与天玑配置、含空格路径、OPlus 分区、只读系统、JSON/XML、充电配置和错误安装环境拒绝。SELinux 操作使用测试替身，Linux 主机无法验证 Android SELinux 或实际 Hybrid Mount 挂载。尚未在实体设备上验证，因此“完整适配”仍需以目标 ROM 上的安装、启动、覆盖比对及挂载来源检查为准。

协议依据：[KernelSU 模块指南](https://kernelsu.org/guide/module.html)、[元模块指南](https://kernelsu.org/guide/metamodule.html)、Hybrid Mount 的 `module/metainstall.sh`、`src/defs.rs` 与分区规划代码。

## GitHub Actions

仓库推送、Pull Request 或在 Actions → **Build KernelSU module** → **Run workflow** 手动触发时，工作流自动构建。

CI 使用 Ubuntu 22.04、Python 3.12 和锁定提交及 SHA256 的 KernelSU x86_64 BusyBox。依次检查 ash 语法、运行全部安装测试、构建、重放补丁、校验 ZIP 内容与 SHA256，并验证重复构建一致性。依赖缺失或测试被跳过会导致失败。

构建成功后，在对应 Actions 运行页面的 **Artifacts** 下载 `extreme-gt-ksu-运行编号`。解压下载的 artifact，使用其中的 `extreme_gt-*.zip` 安装；不要把 artifact 外层 ZIP 直接交给 KernelSU。构建产物保留 30 天。流程仅上传 artifacts，不自动创建 Release。

本地运行同一 CI 入口：

```sh
BUSYBOX=/path/to/KernelSU/userspace/ksud/bin/x86_64/busybox python3 scripts/ci.py
```
