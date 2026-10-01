# rmcdhf_test

轨道优化程序、测试和网格工具已迁入相邻的
[`grasp-atomic-suite`](../grasp-atomic-suite/README_ZH.md)，后续开发使用该仓库。
当前工作目录及其 Git 历史保留作为迁移前的参考。

这是一个用于测试 GRASP 中 `rmcdhf` 程序不同实现方案的独立仓库。
仓库只保留 `rmcdhf` 的串行、MPI 和内存版本，以及这些程序所需的
Fortran 库和测试代码。

## 编译前准备

每次配置或编译前，先在当前 shell 中加载 MPI 工具链：

```sh
source /usr/share/Modules/init/zsh
module load mpi/openmpi-x86_64
```

## CMake 构建

```sh
./configure.sh --debug
cmake --build build-debug -j4
ctest --test-dir build-debug --output-on-failure
cmake --install build-debug
```

Release 构建可直接运行 `./configure.sh`，然后将上面的
`build-debug` 替换为 `build`。

构建结果位于 `bin/` 和 `lib/`；未安装时的可执行文件位于构建目录下的
`build-*/bin/`。

## 目标程序

本仓库使用 `rmcdhf_orbopt` 系列名称，表示轨道优化版本，并与原版 GRASP 的命令区分。
源码目录和计算文件名（例如 `rmcdhf.sum`、`rmcdhf.log`）保留原有约定。

- `rmcdhf_orbopt`：串行版本
- `rmcdhf_orbopt_mpi`：MPI 并行版本
- `rmcdhf_orbopt_mem`：内存管理版本
- `rmcdhf_orbopt_mem_mpi`：MPI 内存管理版本

旧构建或安装目录中可能仍有原名可执行文件；重新构建后请调用上述新名称，
并更新外部脚本中的命令路径。新的构建不生成原名兼容别名。

## 测试代码

外部原版 GRASP 的径向网格可通过本仓库的
[`scripts/patch_grasp_grid.py`](scripts/README.md) 批量预览、修改、检查和恢复，
无需手工同步各程序的默认值。脚本默认不写入，修改后需全量重编译 GRASP。

`test/` 中包含 `lib9290` 基础测试和 `rmcdhf` 回归测试辅助脚本。
测试输入、输出和比较逻辑均应放在该目录中，计算生成的大型数据不会同步到仓库。

## 目录结构

```text
src/appl/rmcdhf90*   rmcdhf 程序源代码
src/lib/             rmcdhf 所需库源代码
test/                测试代码和测试输入
```
