# rmcdhf_test

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

- `rmcdhf`：串行版本
- `rmcdhf_mpi`：MPI 并行版本
- `rmcdhf_mem`：内存管理版本
- `rmcdhf_mem_mpi`：MPI 内存管理版本

## 测试代码

`test/` 中包含 `lib9290` 基础测试和 `rmcdhf` 回归测试辅助脚本。
测试输入、输出和比较逻辑均应放在该目录中，计算生成的大型数据不会同步到仓库。

## 目录结构

```text
src/appl/rmcdhf90*   rmcdhf 程序源代码
src/lib/             rmcdhf 所需库源代码
test/                测试代码和测试输入
```
