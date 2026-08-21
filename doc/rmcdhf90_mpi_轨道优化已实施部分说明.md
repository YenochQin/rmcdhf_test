# `rmcdhf90_mpi` 轨道优化已实施部分说明

## 1. 文档目的

本文记录截至 2026-08-21 已经在当前仓库中实现并取得实验结果的
`rmcdhf_mpi` 轨道优化诊断与保护功能。原始设计与完整实施顺序见
[`rmcdhf90_mpi_轨道优化调试方案.md`](./rmcdhf90_mpi_轨道优化调试方案.md)。

当前实现对应提交：

```text
b30a1e3 Add RMCDHF orbital optimization safeguards
bbf6d01 Import remaining GRASP source baseline
```

当前分支为 `rmcdhf_mpi_test`。本实现的状态可以概括为：

- P0 诊断基础设施已经基本完成；
- P1 的伙伴检查、固定阻尼和候选轨道护栏已经编码并完成部分 A/B 实验；
- 伙伴完整性与固定阻尼获得了正面证据；
- 候选护栏仍有已知局限，保持默认关闭；
- 严格 SCF 收敛、Cl I 验收、B5–B8 和算法层 P2 尚未完成。

因此，这一版本应视为“可用于定位问题和继续实验的诊断版本”，不能视为已经完成全部验收的生产修复版本。

## 2. 已实施范围总览

| 原方案阶段 | 当前状态 | 已实施内容 |
| --- | --- | --- |
| 6.1 冻结基线 | 部分完成 | 导入 Ni I、Ni/Ca-like 的归档输入、波函数和结果；建立独立测试分支与 Debug 构建 |
| 6.2 独立控制模块 | 已完成 | 环境变量控制、rank 0 读取、MPI 广播、默认关闭可改变数值路径的功能 |
| 6.3 轨道选择与优化 trace | 已完成 | 稳定 CSV、轨道选择、SCF、求解、指标、正交化、能级和 MPI 摘要事件 |
| 6.4 相对论伙伴检查 | 已完成 | 按 `n`、`l`、`kappa` 配对；默认警告；严格模式终止 |
| 6.5 候选轨道质量度量 | 已完成 | 范数、重叠、平均半径、节点数、径向范围和能量变化 |
| 6.6 可回退轨道护栏 | 实验实现 | 可拒绝异常原始候选、恢复关键状态、累计拒绝并显式停止；尚不适合默认启用 |
| 6.7 严格收敛 | 未完成 | 已有环境变量和 trace 字段，但严格 `AND` 判据及连续两轮逻辑尚未接入 SCF 退出路径 |
| 6.8 证据驱动修改 | 部分完成 | 已完成成对选择和固定阻尼实验；尚未形成最终生产策略 |
| 6.9 自动化回归 | 部分完成 | Ni I、Ni/Ca-like AS1/AS2 数据驱动及结果比较脚本；尚无 Cl I 和 B5–B8 全矩阵 |
| 6.10 核极化势 | 未开始 | 不在本次已实施范围内 |

## 3. 运行时控制模块

### 3.1 模块与初始化位置

新增文件：

```text
src/appl/rmcdhf90_mpi/orbopt_control.f90
```

该文件定义 `ORBOPT_CONTROL_C` 模块。程序在 `startmpi2` 返回、已经取得
`myid`、`nprocs` 和启动目录后调用：

```fortran
CALL SET_ORBOPT_TRACE_DIRECTORY(startdir)
CALL INIT_ORBOPT_CONTROL
```

控制参数只由 rank 0 读取环境变量，随后通过 `MPI_Bcast` 同步到全部进程。
实现没有向原有 stdin 增加交互问题，因此不会使历史输入脚本错位。

### 3.2 已实现的环境变量

| 环境变量 | 默认值 | 作用 | 当前建议 |
| --- | ---: | --- | --- |
| `GRASP_TRACE_ORBOPT` | `0` | 输出 `orbopt_trace.csv` 及必要的 rank 差异文件 | 诊断运行时启用 |
| `GRASP_REQUIRE_BALANCED_PAIR` | `0` | 发现单侧变分或缺少伙伴时终止 | B3/严格输入检查时启用 |
| `GRASP_ORBITAL_DAMPING` | `0` | 给所有非固定轨道设置固定负 `ODAMP`，合法范围为 `(-1,0)` | 已验证 `-0.5` 有稳定作用，但未设为默认 |
| `GRASP_ORBITAL_GUARD` | `0` | 在 `DAMPOR` 前检查并拒绝异常原始候选 | 保持关闭，仅用于实验 |
| `GRASP_MIN_ORBITAL_OVERLAP` | `0.1` | 护栏允许的最小绝对重叠 | 仅 guard 启用时生效 |
| `GRASP_MAX_RADIUS_RATIO` | `10` | 护栏允许的新旧平均半径最大对称比值 | 仅 guard 启用时生效 |
| `GRASP_REJECT_NODE_CHANGE` | `1` | 节点数变化时拒绝候选 | 仅 guard 启用时生效 |
| `GRASP_MAX_REJECTS_PER_ORBITAL` | `3` | 单轨道可容许的拒绝次数 | 超限后显式停止 |
| `GRASP_STRICT_SCF` | `0` | 预留严格收敛控制 | 已读取和广播，但尚未真正改变收敛逻辑 |

逻辑环境变量接受 `1/0`、`true/false`、`yes/no`、`on/off`。非法的阻尼、
重叠、半径比或拒绝次数会输出提示并恢复安全默认值。

### 3.3 默认兼容性

可能改变数值流程的功能默认均关闭：固定阻尼为零、guard 为假、严格伙伴要求为假。
默认情况下仍使用历史求解、阻尼、正交化和 SCF 退出路径。伙伴检查默认会输出警告，
但不会自动扩展 varied list，也不会改变轨道选择。

## 4. 稳定的轨道优化 trace

### 4.1 输出位置与格式

新增文件：

```text
src/appl/rmcdhf90_mpi/orbopt_trace.f90
```

启用 `GRASP_TRACE_ORBOPT=1` 后，rank 0 在程序启动目录写入：

```text
orbopt_trace.csv
```

CSV 固定为 50 列，所有事件共用同一表头，某一事件不使用的字段留空。主要字段包括：

```text
event, iteration, rank, index, index2, position, group,
np, nh, nak, lfix, lcorre, method, noinvt, odamp, odamp_used,
scnsty, energy_old, energy_candidate, dnorm, inv, jp, nnp,
fallback, solve_failed, nw, nfix, nsic, nscf, accy,
orthst, lsort, wtaev, wtaev0, dampmx,
convg_orbital, convg_energy, convg_final,
overlap, detail, candidate_norm, old_norm,
radius_old, radius_candidate, nodes_old, nodes_candidate,
mf_old, mtp_candidate, energy_delta, level_weight
```

这种格式避免依赖面向人的 stdout 排版，便于 Python 脚本稳定解析和跨运行比较。

### 4.2 已接入的事件

| 事件 | 插入位置 | 记录内容 |
| --- | --- | --- |
| `control` | 首次打开 trace | 阻尼、guard、阈值和拒绝策略 |
| `selection` | `GETOLDmpi` 完成轨道属性设置后 | `IORDER`、分组、`LFIX`、`LCORRE`、`METHOD`、`NOINVT`、`ODAMP` |
| `pair_check` | 相对论伙伴检查 | 单侧选择或缺失伙伴及其索引/期望 `kappa` |
| `scf_begin` | 每个 SCF 宏迭代开始 | `NIT`、`NW`、`NFIX`、`NSIC`、`NSCF`、`ACCY`、`ORTHST`、`LSORT` |
| `lagrange_pair` | `SETLAGmpi` 建立约束后 | 每一对同 `kappa` 的 Lagrange 乘子轨道 |
| `solve_result` | `SOLVE` 返回后 | 能量、方法 fallback、`INV`、`JP`、`NNP` 和失败标志 |
| `candidate` | 候选归一化前后 | 候选范数、自洽性相关状态和求解元数据 |
| `orbital_metrics` | `DAMPOR` 前 | 原始候选相对旧轨道的重叠、平均半径和节点数 |
| `rejected` | guard 拒绝候选时 | 拒绝原因、累计次数和下次阻尼建议 |
| `accepted` | `DAMPOR` 接受轨道后 | 实际使用的阻尼和接受后的能量状态 |
| `accepted_metrics` | `DAMPOR` 后 | 实际接受轨道相对更新前轨道的质量指标 |
| `orthy_order` | `ORTHY` 排序后 | 同 `kappa` 组的固定/光谱/关联分组和 Schmidt 顺序 |
| `orthy_projection` | 每次 Schmidt 投影 | 被投影轨道、参考轨道和投影重叠 |
| `level_energy` | `NEWCOmpi` 输出能级时 | 能级索引、块、能量和 EOL 权重 |
| `scf_end` | SCF 收敛判断处 | 轨道判据、能量判据、当前最终判据和停止原因 |

### 4.3 MPI 状态摘要

每轮结束后，每个 rank 分别对以下数据计算加权摘要：

- 轨道能量 `E`；
- 自洽指标 `SCNSTY`；
- 大、小分量径向数组 `PF/QF`；
- 广义占据数 `UCF`；
- 本征向量 `EVEC`。

通过 `MPI_Allreduce` 比较各 rank 的最小值和最大值。相对差异不超过
`1e-12` 时不产生额外文件；只有出现不一致时，各 rank 才追加写入：

```text
orbopt_trace.rankNNN.csv
```

这避免了正常运行中多个进程竞争同一个日志文件，同时保留 MPI 状态分叉证据。

## 5. 相对论伙伴完整性检查

### 5.1 配对规则

伙伴检查在 `GETOLDmpi` 完成 varied list 解析和 `LFIX/LCORRE` 设置后执行。
配对不依赖轨道标签中是否含有 `-`，而是根据 `NAK=kappa` 推导轨道角动量：

$$
l=\begin{cases}
\kappa,&\kappa>0,\\
-\kappa-1,&\kappa<0.
\end{cases}
$$

具有相同主量子数 $n$、相同 $l>0$，且
$\kappa=l$ 与 $\kappa=-(l+1)$ 的两个轨道构成一对。`s` 轨道的 $l=0$，
不存在另一相对论伙伴，因此不进入单侧配对检查。

### 5.2 检查行为

对于一对轨道，程序比较：

$$
V_i=\neg LFIX(i),\qquad V_i\oplus V_j.
$$

已经实现两级行为：

1. 默认模式输出明确警告并继续，不修改用户输入；
2. `GRASP_REQUIRE_BALANCED_PAIR=1` 时，在进入 SCF 前以 `ERROR STOP` 终止。

检查还会识别“轨道可变，但当前轨道集中根本没有对应伙伴”的情况，并在日志中记录
期望的 `kappa`。当前实现只检查和拒绝，不会自动把缺失伙伴加入 varied list，
也不等价于两个伙伴的联立求解。

## 6. 候选轨道质量度量

新增文件：

```text
src/appl/rmcdhf90_mpi/orbopt_metrics.f90
```

指标在 `SOLVE` 返回、候选轨道完成归一化后、`DAMPOR` 修改已存轨道前计算。
积分复用 GRASP 的 `TA`、`QUAD`、`R` 和 `RP` 网格约定。

### 6.1 范数与重叠

候选和旧轨道范数分别为：

$$
N=\int(P^2+Q^2)\,dr.
$$

候选与旧轨道的有符号重叠为：

$$
S=\int\left(P_{\rm cand}P_{\rm old}
 +Q_{\rm cand}Q_{\rm old}\right)dr.
$$

质量判据使用 $|S|$，因此径向函数整体相位翻转不会被误判为轨道塌缩。

### 6.2 平均半径

分别计算：

$$
\langle r\rangle
=\int r(P^2+Q^2)\,dr.
$$

为同时识别收缩和膨胀，比较的是对称半径变化因子：

$$
R_f=\max\left(
\frac{\langle r\rangle_{\rm cand}}{\langle r\rangle_{\rm old}},
\frac{\langle r\rangle_{\rm old}}{\langle r\rangle_{\rm cand}}
\right).
$$

### 6.3 节点和其他状态

节点数复用现有 `COUNT` 过程，对旧轨道和候选轨道分别统计。trace 同时保留：

- `MF_old` 与候选 `MTP0`；
- 候选能量相对旧能量的变化；
- `SCNSTY`、`METHOD`、`INV`、`JP` 和 `NNP`；
- `SOLVE` 是否失败或转入 `METHOD=2` fallback。

除 raw candidate 外，`DAMPOR` 之后还会再次计算 `accepted_metrics`，从而区分：

- 求解器产生的原始候选是否激进；
- 实际经过阻尼、被程序接受的轨道是否稳定。

这一差别对解释 B4 结果非常重要。

## 7. 实验性轨道护栏

### 7.1 拒绝条件

启用 `GRASP_ORBITAL_GUARD=1` 后，满足任一条件即拒绝当前原始候选：

- $|S| < \texttt{GRASP_MIN_ORBITAL_OVERLAP}$；
- $R_f > \texttt{GRASP_MAX_RADIUS_RATIO}$；
- 节点数变化，且 `GRASP_REJECT_NODE_CHANGE=1`。

拒绝原因以 `overlap`、`radius`、`nodes` 或组合形式写入 trace。

### 7.2 拒绝后的状态处理

拒绝时程序不会调用 `DAMPOR`，也不会进入该次更新后的 `ORTHY`。实现会：

1. 恢复该轨道的旧能量 `E(J)`；
2. 恢复 `MF(J)`、`PZ(J)` 和关键自洽状态；
3. 保持当前已接受的 `PF/QF` 不变；
4. 将该轨道标为未收敛，防止拒绝后立即被误认为 SCF 收敛；
5. 增加单轨道拒绝计数；
6. 把下一次负阻尼强度依次提高到约 `0.5`、`0.7`、`0.9`；
7. 超过 `GRASP_MAX_REJECTS_PER_ORBITAL` 后显式 `ERROR STOP`。

一旦轨道更新被接受，其累计拒绝计数清零。

### 7.3 当前已知局限

护栏检查发生在 `DAMPOR` 前。Ni I 实验显示，原始 `4f` 候选可能低于重叠阈值，
但相同候选经过固定阻尼后的实际接受轨道却很稳定。因此，严格拒绝 raw candidate
可能阻止本可由 `DAMPOR` 安全吸收的更新。

基于这一证据，guard 当前必须保持默认关闭。它已经具备“检测、拒绝、恢复、计数、
显式终止”的实验能力，但尚不能作为生产默认策略。

## 8. 固定阻尼

`GRASP_ORBITAL_DAMPING` 为所有 `LFIX=.FALSE.` 的轨道设置同一个负 `ODAMP`。
其接线位置在 `GETOLDmpi` 完成用户输入解析后，因此不增加交互问题，也不会影响固定轨道。

当前重点测试值为：

```shell
GRASP_ORBITAL_DAMPING=-0.5
```

该选项并不改变 `SOLVE` 产生的原始候选，而是通过现有 `DAMPCK/DAMPOR` 路径限制实际
接受的径向更新。trace 中的 `orbital_metrics` 和 `accepted_metrics` 可以直接观察这一差异。

目前证据支持固定阻尼能够使已接受轨道更平滑，但尚未完成 `-0.2/-0.5/-0.8`
全矩阵和 Cl I 验证，因此没有把 `-0.5` 设为程序默认值。

## 9. 数据测试与分析工具

### 9.1 已导入的数据

当前测试数据位于：

```text
test/data/Ni_I/
test/data/Ni_Ca-like/
```

包含归档的 CSF 输入、各活动空间波函数、`.sum`、`.log`、`.level` 和相关输出。
当前 runner 使用归档阶段 `.c` 文件，以隔离 `rmcdhf_mpi` 行为，不把 CSF 生成差异混入
轨道优化诊断。

### 9.2 数据驱动脚本

```text
test/rmcdhf_orbopt/run_data_case.sh
```

当前支持：

- 数据族：`ni_i`、`ni_ca_like`；
- 模式：`optimized`、`nv`、`minus_only`、`balanced`；
- 初始波函数：`estimate`、`archived`；
- 活动空间阶段：AS1、AS2；
- 任意正整数 MPI rank 数。

模式与诊断矩阵的对应关系为：

| runner 模式 | 对应实验 | varied list |
| --- | --- | --- |
| `nv` | B0 | 新层全部固定 |
| `optimized` | B1 | 只优化原输入中的正伙伴 |
| `minus_only` | B2 | 只优化负伙伴 |
| `balanced` | B3 | 两个相对论伙伴均加入 varied list，并启用严格伙伴检查 |

脚本会建立全新的输出目录，拒绝覆盖既有目录；保存完整 stdin、stdout、退出码、
`orbopt_trace.csv`、`rmcdhf.sum` 和比较结果。它还将 `OMP_NUM_THREADS` 与
`OPENBLAS_NUM_THREADS` 默认设为 1，避免 MPI rank 与 OpenMP BLAS 线程乘积造成过度订阅。

### 9.3 分析脚本

已新增：

```text
test/rmcdhf_orbopt/compare_rmcdhf.py
test/rmcdhf_orbopt/compare_sum.py
test/rmcdhf_orbopt/compare_fine_structure.py
```

各脚本职责如下：

- `compare_rmcdhf.py`：校验 trace 表头与行结构，按 SCF 轮次汇总能级间隔、raw/accepted
  最小重叠、最大半径因子、节点变化和 fallback 次数；可与参考 trace 按容差比较；
- `compare_sum.py`：比较 CSF 数、径向网格点数、能级标签和本征能量；默认能量绝对容差
  为 `1e-9` Hartree；
- `compare_fine_structure.py`：提取正宇称最低 `J=2,3,4` 能级，转换为
  $\mathrm{cm}^{-1}$ 相对能量并输出排序。

### 9.4 运行示例

```shell
bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i balanced /tmp/ni-i-b3-as2 4 estimate 2

GRASP_ORBITAL_DAMPING=-0.5 \
bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i balanced /tmp/ni-i-b4-as2 4 estimate 2

GRASP_ORBITAL_DAMPING=-0.5 \
GRASP_ORBITAL_GUARD=1 \
GRASP_EXPECT_RMCDHF_FAILURE=1 \
bash test/rmcdhf_orbopt/run_data_case.sh \
  ni_i balanced /tmp/ni-i-guard-as2 4 estimate 2
```

## 10. 已取得的实验结果

详细归档结果见 [`test/rmcdhf_orbopt/RESULTS.md`](../test/rmcdhf_orbopt/RESULTS.md)。

### 10.1 AS2 B0–B3

| Case | SCF 轮数 | 最小重叠 | 最大半径因子 | 节点变化 | 最终排序 |
| --- | ---: | ---: | ---: | ---: | --- |
| Ni I NV | 1 | 不适用 | 不适用 | 0 | `J4 < J3 < J2` |
| Ni I B1 | 20 | 0.02920 | 8.610 | 2 | `J2 < J3 < J4` |
| Ni I B2 | 12 | 0.03570 | 8.416 | 1 | `J4 < J3 < J2` |
| Ni I B3 | 14 | 0.02902 | 8.630 | 3 | `J4 < J3 < J2` |
| Ni/Ca-like NV | 1 | 不适用 | 不适用 | 0 | `J2 < J3 < J4` |
| Ni/Ca-like B1 | 6 | 0.19329 | 2.781 | 0 | `J2 < J4 < J3` |
| Ni/Ca-like B2 | 7 | 0.29918 | 2.784 | 0 | `J2 < J3 < J4` |
| Ni/Ca-like B3 | 8 | 0.18857 | 2.798 | 0 | `J2 < J3 < J4` |

这些结果支持以下结论：

1. 原 optimized 输入确实只选择了正伙伴；B1 会产生不平衡伙伴警告；
2. B2 和 B3 均改变了错误排序，说明相对论伙伴选择与精细结构排序直接相关；
3. B3 消除了输入不平衡，但 Ni I 仍存在低于 0.1 的重叠和节点变化；
4. 因此，“伙伴缺失”是重要原因，但不是造成所有异常径向候选的唯一原因；
5. 所有已记录运行均未发生 `SOLVE` fallback，当前证据不支持把 `METHOD=2`
   fallback 作为这些 AS2 异常的首要原因。

### 10.2 B4 固定阻尼与 guard

| Case | 轮数 | raw 重叠/半径因子 | accepted 重叠/半径因子 | accepted 节点变化 | 排序 |
| --- | ---: | --- | --- | ---: | --- |
| Ni I B3+B4 | 29 | 0.02847 / 8.588 | 0.71710 / 1.824 | 0 | `J4 < J3 < J2` |
| Ni/Ca-like B3+B4+guard | 17 | 0.19559 / 2.789 | 0.77317 / 1.558 | 0 | `J2 < J3 < J4` |

固定阻尼没有改善 `SOLVE` 的 raw candidate 指标，但显著改善了实际接受轨道：

- Ni I 接受后最小重叠从 raw 的 0.02847 提高到 0.71710；
- 最大半径变化因子从 8.588 降到 1.824；
- 接受轨道没有节点变化，并保持预期排序。

Ni/Ca-like 在默认重叠阈值 0.1 下没有发生拒绝并正常完成。Ni I guard 则拒绝了
`6s`、`5d`、`4f-` 和 `4f`；在拒绝上限设为 2 的实验中，第三次拒绝 `6s` 后明确停止，
没有静默接受异常候选，也没有把反复拒绝误判为收敛。

另一个阈值 0.03 的恢复实验显示，未改变的 `4f` raw candidate 在六次尝试中重叠
从 0.02847 进一步降到 0.02452。这证明当前“先拒绝 raw candidate，再考虑阻尼”的策略
不能保证恢复，形成了第 7.3 节所述限制。

### 10.3 并行性能观察

在 48 核参考主机上，已记录的最快配置是：

```text
4 MPI ranks × 12 OpenMP threads/rank
```

纯 24-rank MPI 受通信限制；强制每个 rank 单线程又无法利用带 OpenMP 的 OpenBLAS。
这属于当前机器上的性能观察，不是跨平台默认配置。

## 11. 构建与基础验证

### 11.1 本轮实际构建

2026-08-21 在当前 HEAD 上执行：

```shell
source /usr/share/Modules/init/zsh
module load mpi/openmpi-x86_64
cmake --build build-debug -j4
```

完整构建成功，`rmcdhf_mpi` 目标成功生成。动态链接检查显示使用：

```text
libflexiblas.so.3
Open MPI Fortran/MPI libraries
```

### 11.2 CTest 与 MPI 工作流

执行完整 CTest 时，8 个测试中的 6 个非受限测试通过；两个 MPI workflow 在受限沙箱中
因为 PMIx 无法创建监听 socket 而失败。随后使用允许 MPI socket 的执行环境直接运行同一
4-rank 集成工作流：

```shell
GRASP_TRACE_ORBOPT=1 \
GRASP_BINDIR=/home/workstation2/AppFiles/grasp_test/build-debug/bin \
bash test/integration/mpitmp/run.sh --preserve-tmp mpi
```

`rangular_mpi` 和 `rmcdhf_mpi` 均正常完成，最终输出 `TESTS SUCCEEDED`，并成功生成
`orbopt_trace.csv`。因此，本轮两个 CTest 失败属于执行环境的 PMIx socket 限制，
不是已观察到的 Fortran 构建或数值流程失败。

这一基础工作流只能证明当前诊断版可构建并可完成一个小型 4-rank MPI 计算；它不能替代
Ni/Cl 科学验收，也不构成 MPI 1/2/4 数值一致性证明。

## 12. 尚未完成的部分与使用边界

以下项目没有包含在“已完成”结论中：

1. **严格 SCF 收敛尚未接线。** `GRASP_STRICT_SCF` 已读取并广播，但
   `SCFmpi` 当前仍以“轨道判据 OR 能量判据”停止；没有实现严格 `AND` 和连续两轮计数。
2. **Cl I 尚无测试夹具和运行记录。** 未完成 Cl I AS1–AS5、B0–B8 和实验/NIST
   精细结构验收。
3. **自动化矩阵不完整。** 当前 runner 只覆盖 Ni I、Ni/Ca-like、AS1/AS2 和 B0–B3，
   B4 通过环境变量人工组合；没有一键运行 B0–B6 或全部 MPI 进程数组合。
4. **B5–B8 尚未执行。** 没有延后正交化、固定求解方法、独立 CI/RCI 或 EOL 权重矩阵。
5. **串行/MPI 一致性尚未证明。** 已实现 rank 间摘要诊断，但没有形成串行版与
   MPI 1/2/4 每轮能量、轨道和本征向量的正式对照报告。
6. **没有自动伙伴扩展或伙伴联立更新。** B3 由 runner 显式生成成对 varied list；
   程序本身只警告或拒绝不平衡输入。
7. **guard 不是生产策略。** 它可能拒绝经过阻尼后本可稳定接受的候选，必须保持默认关闭。
8. **P2 算法修改尚未开始。** 没有改变 `ORTHY` 的正交化时机、`SOLVE` fallback
   验收规则或伙伴成组接受/回退算法。
9. **核极化势未实施。** NP0–NP3 均不属于当前提交。

## 13. 当前可支持的结论

基于现有代码和实验，可以支持：

- 原 LBL varied list 中只选择正相对论伙伴是可检测的真实输入状态；
- 单侧轨道选择会造成不平衡松弛，并与错误的精细结构排序相关；
- 成对选择可以恢复当前 Ni I 和 Ni/Ca-like AS2 实验中的预期排序；
- 成对选择本身不能消除所有低重叠、节点变化和大幅径向更新；
- 固定负阻尼能够显著稳定实际接受的轨道；
- 当前异常没有与 `SOLVE` fallback 同现；
- raw-candidate guard 可以防止异常更新被静默接受，但当前检查时机过早，尚不适合默认启用。

现阶段不能支持：

- 宣称 Cl I AS1–AS5 问题已经修复；
- 宣称串行与 MPI 1/2/4 已完全一致；
- 宣称轨道波函数已达到最终物理精度；
- 把 `-0.5` 阻尼或 guard 固化为所有体系的生产默认值；
- 把整个轨道优化方案标记为完成。

## 14. 后续衔接点

继续实施时，应从以下位置接续，而不需要重做已完成的 P0 基础设施：

1. 接通 `GRASP_STRICT_SCF`，实现轨道与能量判据同时满足且连续两轮稳定；
2. 导入 Cl I AS1 最小夹具，先运行 B0–B4，再扩展到 AS5；
3. 补齐 MPI 1/2/4 和串行逐轮一致性对照；
4. 比较“raw candidate guard”与“先阻尼、再检查 accepted candidate”两种策略；
5. 只有证据指向正交化或求解器时，再分别进入 B5、B6 和 P2 修改；
6. 主线验收通过前，不引入核极化势或其他 Hamiltonian 改动。
