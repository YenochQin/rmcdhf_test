# 批量修改外部 GRASP2018 径向网格

`patch_grasp_grid.py` 保存在本仓库，操作 `--grasp` 指定的外部源码树。
不需要重构 GRASP 或手工逐个修改程序，也不自动运行编译或提交代码。
脚本只使用 Python 标准库；本工作区仍使用 `graspkit-tools/.venv`。

在 `rmcdhf_test/` 下预览一个示例配置：

```bash
../graspkit-tools/.venv/bin/python scripts/patch_grasp_grid.py \
  --grasp ../grasp --nnnp 1990 --n 1179 --h 0.025 \
  --rnt-scale 2e-6 --hp 0 --diff
```

这是用法示例，不是已验证适合任何元素的推荐网格。
`--nnnp` 设置编译容量，`--n` 设置有限核模型实际点数。
`--rnt-scale 2e-6` 表示 `RNT=2e-6/Z`，不是绝对半径。
未指定的数值保留；有限核的 `N=NNNP` 默认会跟随新的容量。
`--h/--n/--rnt-scale` 只改变有限核分支。
点核分支需要显式使用 `--point-h/--point-n/--point-rnt-scale`；
`--hp` 位于公共赋值处，因此同时影响两种核模型。
`--accy` 可指定独立的数值阈值，否则保留原有公式或固定值（原版为 `H**6`）。

在相同命令后追加 `--apply` 写入；可用 `--backup-dir /path/to/new-directory`
指定一个尚不存在的备份目录，否则备份保存到系统临时目录。
需要长期保存恢复能力时，应明确指定持久化的备份目录。
每次应用保存所有被修改文件的原始字节和校验和。

```bash
../graspkit-tools/.venv/bin/python scripts/patch_grasp_grid.py \
  --grasp ../grasp --nnnp 1990 --n 1179 --h 0.025 \
  --rnt-scale 2e-6 --hp 0 --apply --backup-dir /path/to/new-backup
```

把 `--apply` 换成 `--check` 可以验证补丁已完整应用：一致时退出 0，
仍有待修改文件时退出 1，布局无法识别或参数不合法时退出 2。
重复应用相同配置不会重复插入代码或重新创建备份。

预览恢复，然后追加 `--apply` 执行恢复：

```bash
../graspkit-tools/.venv/bin/python scripts/patch_grasp_grid.py \
  --restore /path/to/new-backup --diff
```

如果源码在应用后又被修改，恢复会拒绝覆盖后续改动。
完整修改计划在写入前生成；已知源码结构不匹配、缺少文件、未处理的径向
容量定义或未知网格初始化会使整个计划失败。
写入使用逐文件原子替换，正常异常会回滚已完成的文件；掉电或强制终止
时可利用备份人工恢复。脚本不支持并发编辑同一个源码树。

脚本覆盖 17 个径向应用入口、`rwfnrotate/rwfnrelabel` 和
`rwfnestimate` 中重复的容量声明。它还恢复 `rwfnrelabel` 被注释的网格
初始化，并在 RMCDHF 的运行时 ACCY 提示前重新计算默认 ACCY，保留用户
随后显式输入 ACCY 的能力。指定 `--accy` 时也更新 RCI 恢复路径的数值阈值。
不指定 `--rnt-scale` 时，`rwfnrotate` 原有未除以 Z 的 RNT 默认值仍保留。

独立的非相对论 HF、旧 MCHF 绘图/转换工具 `wfnplot/rwfnmchfmcdf`
不在作用范围内。旧 RCI `.res` 恢复时仍读取文件内的网格；要测试新网格应
在新的计算目录启动新计算。交互输入也能覆盖新源码默认值。

修改后需要全量重编译并安装所有实际使用的程序，确保 CMake 找到 MPI：

```bash
cmake --build ../grasp/build --clean-first --parallel 4
cmake --install ../grasp/build
```

这里假设 `build/` 已正确配置；编译器和 MPI 初始化沿用 GRASP 的构建说明。
确认 PATH 或绝对路径指向新安装的可执行文件，然后检查各阶段 `.sum`
中实际使用的 `RNT/H/HP/N/ACCY`。补丁通过检查仅证明源码配置一致，
不证明实际二进制已更新，也不证明物理量已达到网格收敛。

离线验证脚本：

```bash
../graspkit-tools/.venv/bin/python test/test_patch_grasp_grid.py
```
