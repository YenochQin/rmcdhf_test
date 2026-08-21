# `rmcdhf90_mpi` 轨道优化调试与改进方案

## 1. 目标与当前判断

目标是解释并修复以下现象：在 Ni-like/Ca-like 与 Cl I 的两组计算中，新增 LBL 轨道不优化（`_no_varied`）时相对能量更接近实验值且 $J$ 顺序正确；启用轨道优化后，能量变差，甚至出现精细结构倒序。计划针对
`${grasp_code_path}/appl/rmcdhf90_mpi`
进行只读基线、最小改动、逐级验证；源码修改应在独立副本或 git 分支完成。

当前优先级最高的可检验假设如下：

1. LBL 输入传给 `GETOLDmpi` 的 varied-orbital 列表不完整，尤其只选择了 $nl$ 而漏掉 $nl-$；源码会把全部轨道先设为 `LCORRE=.TRUE.`，只有第二次选择的“spectroscopic orbitals”才改为 `METHOD=1, NOINVT=.FALSE., ODAMP=0, LCORRE=.FALSE.`（`getoldmpi.f90:150–168`）。
2. 只优化相对论伙伴的一侧，会导致不同 $J$ 块获得不平衡的轨道松弛；报告中多组 `nl` 发生大幅收缩而 `nl-` 保持 Thomas–Fermi 形式，这是最强的关联证据，但仍需由实际输入与运行日志确认。
3. `ORTHY` 按“固定 → 光谱 → 关联”顺序对同 $\kappa$ 轨道 Schmidt 正交化；若伙伴缺失、顺序不稳定或新轨道径向形状近乎塌缩，正交化可能把误差传播到其他轨道。
4. `SOLVE` 失败时 `IMPROVmpi` 自动把 `METHOD` 改为 2 并重试；`DAMPOR` 的阻尼只由单轨道 `SCNSTY` 和 `ODAMP` 控制，而 SCF/EOL 在 `SCFmpi` 中以轨道判据或加权能量相对变化即可停止。这可能接受“总能量收敛、精细结构未收敛”的状态。

不要以总能量降低作为成功标准。对一对精细结构能级定义

$$
\Delta E_J=E(J_1)-E(J_2),\qquad
\delta E_J^{\mathrm{opt}}=\Delta E_J^{\mathrm{opt}}-\Delta E_J^{\mathrm{ref}},
$$

其中 `ref` 优先取 `_no_varied` 和实验/NIST 的可比相对间隔。轨道优化的验收条件必须同时包括 $\Delta E_J$ 的符号、误差、轨道稳定性和可重复收敛。

## 2. 已有证据与需要保留的基线

- `wiki/codes/grasp/rmcdhf90.md` 已重建串行版的 MCDHF 流程：EOL 中先 `MATRIX+NEWCO`，随后每轮 `SETLAG → IMPROV(各变分轨道) → MAXARR/NSIC → ORBOUT → MATRIX+NEWCO`；MPI 版应逐项对照，而不能假定二者完全相同。
- Cl I 报告显示：所有 `_no_varied` 的 ${}^{2}P_{3/2}$ 都低于 ${}^{2}P_{1/2}$，间隔约 $923.81\to921.13\ \mathrm{cm}^{-1}$；优化序列始终倒序，间隔约 $-2479.51\to-1739.74\ \mathrm{cm}^{-1}$。优化额外降低 $J=1/2$ 能量约 $0.012$–$0.016\ E_h$。
- Ni/Ca-like 报告显示普通 LBL 在 AS2 出现 $^3F_J$ 倒序/塌缩，未优化新层的序列更稳；新增轨道与初始估计的重叠可降至 $<0.1$，说明这不是微小数值扰动。
- 这些报告只能证明“优化路径与错误谱相关”，不能单独证明是 `GETOLDmpi`、`ORTHY`、`SOLVE` 或输入包装器中的哪一处导致。
- [[nuclear-polarization-potential-neutral-atom-grasp]] 表明核极化势可以作为短程、球对称的一电子势进入 RMCDHF/RCI，并可通过芯层松弛间接改变其他轨道；但当前 Wiki 没有标准 GRASP2018 已实现该势的证据。其主要直接影响是 $s_{1/2}$ 和 $p_{1/2}$，不支持把它作为当前虚轨道单侧收缩和大幅 $J$ 倒序的首要解释。

每次实验都保存：完整 stdin、`rcsf.inp`/`rwfn.inp`、`mcp.*`、stdout/stderr、`rmcdhf.log`、每轮 `rwfn`/`rmix`、编译器与 git commit；禁止只比较最终 `rmcdhf.sum`。

## 3. 代码路径审计

### 3.1 构建可复现的调用图

入口是 `rscfmpivu.f90:26` 的 `PROGRAM RSCFmpiVU`，输入阶段在 `getscdmpi.f90:218` 调 `GETOLDmpi`，SCF 主循环位于 `scfmpi.f90:176–249`，轨道更新位于 `improvmpi.f90`，链接由 `Makefile` 中的 `rmcdhf_mpi`、`-ldvd90 -lmpiu90 -l9290 -lmod` 决定。先记录实际编译命令、MPI 进程数和运行时环境。

### 3.2 逐项打印并校验轨道状态

在不改变数值逻辑的诊断版本中增加可关闭的 trace（建议 `LDBPR` 新增一个专用开关），每个 SCF 宏迭代打印：

- `NW, NFIX, NSIC, NSCF, ORTHST, LSORT`；
- `IORDER(i), NP(i), NH(i), NAK(i), LFIX(i), LCORRE(i), METHOD(i), NOINVT(i), ODAMP(i)`；
- `SETLAGmpi` 建立的每个同 $\kappa$ Lagrange 乘子对；
- `IMPROVmpi` 的 `ED1/ED2, DNORM, SCNSTY, INV, JP, NNP, METHOD` 变化及是否发生 fallback；
- `ORTHY` 实际正交化的同 $\kappa$ 轨道顺序与每次投影范数。

用一个小脚本把 trace 还原成表格，检查：

$$
\mathcal V_k=\{i:LFIX_i=\mathrm{false}\},\quad
\mathcal S_k=\{i:LCORRE_i=\mathrm{false}\},\quad
\mathcal V_k\cap\mathcal S_k
$$

是否与 LBL 意图一致；对每个 $l>0$ 强制报告 $nl-$ 与 $nl$ 是否同时出现在 $\mathcal V_k$。

### 3.3 MPI/串行一致性审计

对同一输入先运行串行 `rmcdhf90`，再运行 `rmcdhf90_mpi`（1、2、4 个进程）。逐轮比较 `MATRIX/NEWCO` 的能量、本征向量、`UCF`、`SCNSTY`、径向轨道范数。重点检查 `improvmpi.f90` 中 `NDA/DA` 的 gather、去重与 `NDCOF` 更新；若 MPI 与串行已不同，应先修复确定性差异，再研究物理优化。

## 4. 最小诊断实验矩阵

所有实验从同一 AS1（因为 Cl I 在 AS1 已倒序）开始，固定 CSF、EOL 状态、权重、网格、核模型、ACCY、NSCF、NSIC、积分方法和编译器。

| 编号 | 变体 | 目的 | 关键观测 |
|---|---|---|---|
| B0 | 新层全部固定（`_no_varied`） | 基线 | $\Delta E_J$、轨道与 CI 可复现 |
| B1 | 只优化实际 `nl` | 重现当前失败 | 是否复现单侧收缩和错误 $J$ 序 |
| B2 | 只优化 `nl-` | 伙伴单侧反事实 | 观察倒序是否转移/消失 |
| B3 | `nl-` 与 `nl` 成对优化 | 检验伙伴平衡假设 | 间隔符号、差分能量、重叠 |
| B4 | 成对优化但 `ODAMP=-0.2,-0.5,-0.8` | 检验过冲/局部极小 | 每轮 $\Delta E_J$ 与 SCNSTY 轨迹 |
| B5 | 成对优化，`ORTHST=.false.`，仅循环末正交化 | 分离正交化影响 | 若恢复正确顺序，重点审计 `ORTHY` |
| B6 | 成对优化，固定 `METHOD=3`，禁止失败 fallback | 分离求解器分支 | 是否仍出现塌缩/倒序 |
| B7 | 同一最终轨道做独立 CI/RCI | 分离轨道与 CI 影响 | 基组差异是否足以产生 $\Delta E_J$ 变化 |
| B8 | 对称 EOL 权重与不同状态集合 | 检验状态加权偏置 | $J$ 依赖的额外能量降低 |

每个变体至少做 3 个重复（不同 MPI 进程数或同配置重复），并画出

$$
\Delta E_J^{(k)},\quad
\max_i\mathrm{SCNSTY}_i^{(k)},\quad
|S_i^{(k)}|,\quad
\langle r\rangle_i^{(k)},\quad
E_{J_1}^{(k)}-E_{J_1}^{(0)},
$$

随 SCF 轮次 $k$ 的曲线。重点记录 $|S|<0.1$、节点数变化、$\langle r\rangle$ 一个数量级收缩、以及 $J$ 间隔变号。

### 4.1 核极化势作为独立的后续实验轴

核极化势不得加入 B0–B8 的主诊断矩阵。主矩阵的目标是定位现有 Hamiltonian 下的轨道选择、求解、阻尼和正交化问题；此时加入新的物理势会使“优化算法修复”和“Hamiltonian 改变”无法区分。

只有主线修复通过第 7 节验收后，再运行下列独立矩阵：

| 编号 | 核极化势处理 | 轨道处理 | 目的 |
|---|---|---|---|
| NP0 | 关闭 | 使用已验收轨道 | 无核极化基线 |
| NP1 | 后处理一阶期望值 | 固定 NP0 轨道 | 判断符号和数量级是否值得继续 |
| NP2 | RCI Hamiltonian 中加入 | 固定 NP0 轨道、允许 CSF 重混合 | 分离 CI 重混合贡献 |
| NP3 | RMCDHF 与 RCI 均加入 | 重新优化轨道 | 测量完整自洽松弛贡献 |

定义

$$
\delta E_{\mathrm{relax}}
=\Delta E_{\mathrm{NP3}}-\Delta E_{\mathrm{NP2}},
$$

其中 NP2 与 NP3 必须使用相同的核参数、CSF 空间、EOL 权重和最终 RCI 选项。若 NP1 已远小于目标误差预算，则停止，不进入 NP2/NP3。

## 5. 建议的代码改进顺序

### P0：只加诊断，不改物理

1. 添加 `TRACE_ORB_OPT` 编译/运行开关，记录上述状态和每轮轨道摘要。
2. 对输入 varied list 做合法性检查：重复索引、固定轨道、未知轨道、同 $\kappa$ 伙伴缺失都给出明确警告；不要静默修正用户输入。
3. 在 `GETOLDmpi` 返回前输出解析后的 $\mathcal V_k$、$\mathcal S_k$ 和 `IORDER`；在 `SCFmpi` 收敛时同时打印轨道判据与能量判据，明确是哪个条件触发停止。

### P1：安全护栏（默认关闭，先做 A/B）

1. **伙伴成对策略**：提供 `PAIR_ORBITALS` 选项，将同 $n,l$ 的 $nl-$/$nl$ 作为一个不可拆分优化组；若用户只给一侧，默认报错或要求显式 `ALLOW_UNBALANCED`。
2. **渐进阻尼**：对新关联层默认采用固定负 `ODAMP`，例如 $-0.5$；每轮限制径向变化，并在 $|S|<0.1$ 或 $\langle r\rangle$ 突变时回退到上轮轨道。
3. **收敛双门槛**：EOL 只有同时满足轨道变化、加权能量变化和目标精细结构间隔在连续两轮不变才接受；不能把现有 `OR` 语义悄悄改掉，应先用新开关比较。

### P2：算法层改进（仅在 P0/P1 定位后）

- 将新关联轨道和 spectroscopic 轨道分组，使用成组阻尼/正交化，避免 `ORTHY` 在同 $\kappa$ 组内以不稳定顺序重塑轨道。
- 对 `SOLVE` 的节点数、`INV/NOINVT`、`METHOD` fallback 增加失败原因与候选轨道质量检查；禁止“求解成功”但节点数错误的候选进入 `DAMPOR`。
- 研究 EOL 目标函数是否需要状态均衡或 state-specific/MCDHF 分阶段优化；这属于物理模型改变，必须与纯代码修复分开评估。

### P3：可选的核极化势扩展（不属于当前缺陷修复）

在 P0–P2 完成并稳定后，可按 [[nuclear-polarization-potential-neutral-atom-grasp]] 增加

$$
H_{\mathrm{DC+NP}}=H_{\mathrm{DC}}+\sum_i V_{\mathrm{NP}}(r_i),
$$

其中

$$
V_{\mathrm{NP}}(r)=V_1(r)+V_2(r),
\qquad
\langle a|V_{\mathrm{NP}}|b\rangle
=\delta_{\kappa_a\kappa_b}
\int [P_aP_b+Q_aQ_b]V_{\mathrm{NP}}(r)\,dr.
$$

该扩展必须有独立开关，默认关闭；核极化关闭时必须重现 P0–P2 的全部 golden baseline。不能通过修改 Fermi 核半径近似该势，也不能只在 RMCDHF 中加入而在最终 RCI 中遗漏。

## 6. 代码实施过程

实施必须按下面的提交顺序进行。每个提交只解决一个问题；前一阶段未通过回归时，不进入下一阶段。所有新增行为默认关闭，未设置新开关时必须保持当前 `rmcdhf_mpi` 的数值结果和交互输入顺序不变。

### 6.1 实施前准备：冻结基线

1. 在 `${grasp_code_path}` 中记录当前分支、commit、dirty 状态、编译器、MPI 实现和链接库版本。若该目录由 git 管理，创建独立分支，例如 `codex/rmcdhf-orbopt-diagnostics`；若不由 git 管理，先复制为一个独立开发树，不直接覆盖生产程序。
2. 使用现有构建流程编译，不先调整优化级别或数值库：

   ```shell
   make -C "${grasp_code_path}/appl/rmcdhf90_mpi"
   ```

3. 为 Cl I AS1 和 Ni/Ca-like AS2 各冻结一套最小输入。每套输入包含 `isodata`、`rcsf.inp`、`rwfn.inp`、`mcp.*`、完整 stdin 和预期输出摘要。
4. 分别运行 `_no_varied` 和当前 optimized 基线，保存可执行文件校验值、退出码、stdout、`rmcdhf.log`、`rmcdhf.sum`、`rwfn.out`、`rmix.out`。这些结果成为后续的 golden baseline。
5. 在任何物理改动前，先确认相同可执行文件重复运行结果一致；MPI 1、2、4 进程的差异另外记录，不能混入轨道算法改动。

建议在 `${grasp_code_path}/tests/rmcdhf_orbopt/` 建立测试夹具，只存可公开且尺寸足够小的输入。大型计算数据继续放在外部实验目录，测试目录只保存路径清单与结果摘要。

### 6.2 提交 1：新增独立控制模块，不改变数值流程

新增 `${grasp_code_path}/appl/rmcdhf90_mpi/orbopt_control.f90`，定义模块 `ORBOPT_CONTROL_C`。第一版只包含：

```fortran
LOGICAL :: TRACE_ORBOPT = .FALSE.
LOGICAL :: WARN_UNBALANCED_PAIR = .TRUE.
LOGICAL :: REQUIRE_BALANCED_PAIR = .FALSE.
LOGICAL :: ENABLE_ORBITAL_GUARD = .FALSE.
LOGICAL :: STRICT_SCF_CONVERGENCE = .FALSE.
INTEGER :: ORBOPT_TRACE_UNIT
```

实现 `INIT_ORBOPT_CONTROL`：由 rank 0 读取环境变量或一个单独的可选配置文件，再通过 `MPI_Bcast` 同步到全部进程。建议的环境变量为 `GRASP_TRACE_ORBOPT`、`GRASP_REQUIRE_BALANCED_PAIR`、`GRASP_ORBITAL_GUARD` 和 `GRASP_STRICT_SCF`。不得向现有 stdin 中插入新问题，否则历史输入脚本会错位。

具体接线：

1. 在 `Makefile` 的 `OBJS` 中把 `orbopt_control.o` 放在使用它的目标文件之前。
2. 在 `rscfmpivu.f90` 中，于 `startmpi2` 完成、`myid/nprocs` 已确定后调用 `INIT_ORBOPT_CONTROL`。
3. 不复用 `LDBPR(1:30)`：这些编号已被 `solve.f90`、`scfmpi.f90`、`xpot.f90` 和 `ypot.f90` 使用。
4. 默认配置下重新运行两个 golden baseline。要求能量、轨道数组和输出文件在既定浮点容差内不变；否则撤销本提交并定位初始化副作用。

### 6.3 提交 2：记录真实轨道选择与优化状态

新增 `orbopt_trace.f90`，提供 `TRACE_ORBITAL_SELECTION`、`TRACE_SCF_BEGIN`、`TRACE_ORBITAL_UPDATE`、`TRACE_SCF_END` 四个过程。输出采用稳定的 CSV 或 JSONL 字段，不解析人类可读的格式化日志。

修改点如下：

| 文件 | 插入位置 | 记录内容 |
|---|---|---|
| `getoldmpi.f90` | 两次 `GETRSL` 结果广播并完成 `LFIX/LCORRE` 设置后 | 轨道标签、索引、`NP/NH/NAK`、`LFIX`、`LCORRE`、`METHOD`、`NOINVT`、`ODAMP`、`IORDER` |
| `scfmpi.f90` | 每个 `NIT` 开始处 | `NIT, NSCF, NSIC, ACCY, ORTHST, LSORT, WTAEV0` |
| `improvmpi.f90` | `SOLVE` 前、`SOLVE` 后、`DAMPOR` 后 | `J, E_old, E_candidate, METHOD`、fallback、`DNORM`、`SCNSTY`、`ODAMPJ, INV, JP, NNP` |
| `orthy.f90` | `KINDX` 排序完成后 | 当前 $\kappa$ 组的固定/光谱/关联分组与实际 Schmidt 顺序 |
| `scfmpi.f90` | 收敛判断处 | 轨道判据、能量判据、最终触发停止的判据 |

主 trace 只由 rank 0 写入 `orbopt_trace.csv`。为审计 MPI 一致性，每个 rank 另计算关键数组的摘要或校验值；只有摘要不一致时才写 `orbopt_trace.rankNNN.csv`，避免多个进程竞争同一文件。

本提交的验收是“打开 trace 只增加日志，不改变结果”。随后用日志回答两个事实问题：当前 varied list 是否真的只包含 `nl`；发生异常收缩的轨道是否经历了 `METHOD=2` fallback、异常节点计数或特定的 `ORTHY` 顺序。

### 6.4 提交 3：实现相对论伙伴完整性检查

在 `getoldmpi.f90` 完成 varied list 解析后调用新过程 `CHECK_RELATIVISTIC_PAIRS`。配对不能靠字符串是否带 `-` 判断，应使用量子数：对轨道 $i$ 由 `NAK(i)=\kappa_i` 得到

$$
l_i=\begin{cases}
\kappa_i, & \kappa_i>0,\\
-\kappa_i-1, & \kappa_i<0,
\end{cases}
$$

具有相同 $n$、相同 $l>0$ 且 $\kappa=l$ 与 $\kappa=-(l+1)$ 的两个轨道组成一对。检查的是

$$
V_i=\neg LFIX(i),\qquad V_i\oplus V_j,
$$

即一侧可变而另一侧固定的异或情形。

实施行为分两级：

- 默认只警告，输出缺失伙伴和解析后的 varied list，保证兼容旧任务；
- `GRASP_REQUIRE_BALANCED_PAIR=1` 时，在进入 `SCFmpi` 前终止并给出可修正的轨道列表。

这一提交只保证“选择完整”，不改变 `SCFmpi` 逐轨道更新的算法，也不能称为两个伙伴的同时联立优化。使用 B0–B3 验证：B1/B2 应产生警告或在严格模式失败，B3 应通过检查。

### 6.5 提交 4：增加候选轨道质量度量，仍不拒绝更新

新增 `orbopt_metrics.f90`。在 `improvmpi.f90` 中，候选轨道完成归一化后、调用 `DAMPOR` 前，比较候选数组 `P/Q` 与当前已存轨道 `PF(:,J)/QF(:,J)`，计算：

$$
S_J=\int\left[P_J^{\mathrm{cand}}P_J^{\mathrm{old}}+
Q_J^{\mathrm{cand}}Q_J^{\mathrm{old}}\right]dr,
$$

以及候选范数、旧/新节点数、`MF/MTP0`、能量变化、`SCNSTY` 和平均半径 $\langle r\rangle$。积分必须复用 GRASP 的网格权重与 `QUAD/RINT` 约定；先用一个未改变轨道验证 $S_J\approx1$，再与外部 `rwfn` 分析脚本交叉验证。没有完成该交叉验证前，不使用 $S_J$ 或 $\langle r\rangle$ 控制求解流程。

外部新增 `${grasp_code_path}/tests/rmcdhf_orbopt/compare_rmcdhf.py`，负责从保存的每轮输出计算 $\Delta E_J$、$\langle r\rangle$、节点数和径向重叠。运行时 trace 与外部脚本必须对同一轨道给出一致趋势。

### 6.6 提交 5：加入可回退的轨道护栏

只有提交 4 证明“异常轨道指标能够稳定区分失败与正常更新”后，才实现 `GRASP_ORBITAL_GUARD=1`。第一版阈值不要写死为最终物理常数，而应由配置读取并写入日志，例如 `MIN_ORBITAL_OVERLAP`、`MAX_RADIUS_RATIO` 和 `MAX_REJECTS_PER_ORBITAL`。

在 `improvmpi.f90` 中的控制流程明确为：

1. `SOLVE` 前保存 `E_old=E(J)`、`MF_old`、`PZ_old`；当前已接受轨道仍保存在 `PF/QF`。
2. `SOLVE` 得到并归一化候选轨道后计算质量指标。
3. 指标正常：保持原路径，调用 `DAMPCK → DAMPOR → ORTHY`。
4. 指标异常：不调用 `DAMPOR`，不调用 `ORTHY`，恢复 `E(J)=E_old`、`MF/PZ` 等被 `SOLVE` 改写的标量；`PF/QF` 本来没有被接受，因此保持旧轨道。
5. 将该轨道标为未收敛，增加拒绝计数，并尝试更强固定阻尼或替代 `METHOD`。超过最大拒绝次数时明确停止，不能让 SCF 把“反复拒绝、轨道未更新”误判为收敛。

必须为“接受”“拒绝后成功”“连续拒绝后终止”各准备一个小测试。B4 用于选择阻尼，不允许仅凭一次 Cl I 结果确定默认值。

### 6.7 提交 6：拆分并收紧收敛判据

在 `scfmpi.f90` 中将当前混合变量 `CONVG` 拆成：

```fortran
CONVG_ORBITAL
CONVG_ENERGY
CONVG_LEGACY
CONVG_STRICT
```

对应关系为

$$
C_{\mathrm{legacy}}=C_{\mathrm{orb}}\lor C_E,
\qquad
C_{\mathrm{strict}}=C_{\mathrm{orb}}\land C_E.
$$

默认仍使用 legacy；`GRASP_STRICT_SCF=1` 时要求 strict 条件连续满足两轮才退出。程序内部暂不直接以特定 $\Delta E_J$ 收敛，因为目标能级对随计算任务变化；目标间隔稳定性由外部测试驱动检查。日志必须输出每个布尔量和连续满足次数。

回归要求：默认模式重现 golden baseline；strict 模式允许多做 SCF 轮次，但不得因为 `WTAEV0=0` 的首轮状态错误触发能量收敛。

### 6.8 提交 7：证据驱动的算法修改

前六个提交完成后，根据实验结果只选择一个分支实施：

| 证据 | 下一项改动 | 涉及文件 |
|---|---|---|
| varied list 确实漏掉伙伴，B3 恢复正确结果 | 将严格伙伴检查用于生产输入；暂不改求解器 | `getoldmpi.f90`, `orbopt_control.f90` |
| 选择完整但 `ORTHY` 后才出现异常 | 增加可选的稳定同 $\kappa$ 顺序，比较即时与轮末正交化 | `orthy.f90`, `improvmpi.f90`, `scfmpi.f90` |
| 异常总与 `METHOD=2` fallback/节点错误同现 | 增加 strict fallback 和节点验收；失败时保留旧轨道 | `solve.f90`, `improvmpi.f90` |
| 串行正确、MPI 多进程错误 | 单独修复 `NDA/DA` gather、去重或归约，先恢复进程数不变性 | `improvmpi.f90`, `cofpotmpi.f90` |
| 所有数值路径一致，但 EOL 权重改变结论 | 转入状态权重/目标函数实验，不把它包装成软件缺陷 | `getoldwt.f90`, `newcompi.f90` 及输入方案 |

真正的“伙伴联立更新”需要同时保存两条候选轨道、成组正交化并共同接受或回退，属于新的优化算法，不应与输入成对检查放在同一个提交。只有 B3 仍失败且证据明确指向逐轨道更新顺序时，才单独设计这一改动。

### 6.9 自动化回归与提交门槛

新增 `tests/rmcdhf_orbopt/run_matrix.sh` 或等价驱动，按以下顺序运行：

1. 编译诊断版；
2. 运行 Cl I AS1 的 B0–B6；
3. 运行 Ni/Ca-like AS2 的关键子集 B0、B1、B3、B4；
4. 对通过的候选运行 MPI 1、2、4 进程；
5. 用 `compare_rmcdhf.py` 生成统一 CSV 和 Markdown 汇总；
6. 检查默认关闭所有开关时是否重现 golden baseline。

每个提交必须附带：修改文件、开关值、输入摘要、运行命令、退出码、能量差、$\Delta E_J$、轨道指标、MPI 一致性和结论。若某阶段失败，保留日志并停止；不要同时调整伙伴选择、阻尼、正交化和 EOL 权重，否则无法归因。

### 6.10 主线稳定后的核极化势实施

此阶段是独立功能分支，建议分支名为 `codex/grasp-nuclear-polarization`，不得与轨道优化修复提交混合。源码静态追踪给出的接入链为：

```text
getscdmpi.f90: CALL NUCPOT
  -> lib/lib9290/nucpot.f90: 生成 ZZ(r) = -r V_nuc(r)
  -> ypot.f90: YP(:N) = ZZ(:N) / NPROCS，进入径向 SCF 方程
  -> lib/lib9290/rinti.f90: MODE=0 时加入核势一电子积分
  -> setham.f90: RINTI(a,b,0) 进入 CI Hamiltonian
```

因此实现应分四个提交：

1. **NP 提交 1：参数与势函数。** 新增共享模块，例如 `NUCPOL_C`，保存 `ENABLE_NP`、E1/E2 开关、$\alpha_0^{EL}$、$b$、$\tilde b$ 和单位信息。输入参数必须显式记录同位素、质量数和来源；所有以 $\mathrm{fm}$ 给出的长度在进入 GRASP 网格前换算为 $a_0$。
2. **NP 提交 2：只生成势并验证。** 计算 $V_1(r)$、$V_2(r)$ 和

   $$
   ZZ_{\mathrm{NP}}(r)=-rV_{\mathrm{NP}}(r),
   \qquad
   ZZ_{\mathrm{total}}=ZZ_{\mathrm{nuc}}+ZZ_{\mathrm{NP}}.
   $$

   先只输出网格表，不进入 SCF。检查符号、$r\rightarrow0$ 有限性、远区 $r^{-4}/r^{-6}$ 渐近行为和核附近网格收敛。E1 与 E2 分开验证。
3. **NP 提交 3：固定轨道/RCI 路径。** 先实现同一 $\kappa$ 的一电子矩阵元或后处理期望值，完成 NP1/NP2。使用类氢或其他有参考数据的体系验证 $1s$、$2s$、$2p_{1/2}$ 能移；当前 Wiki 尚无已经验证的中性多电子 GRASP 算例，所以不能直接以 Cl I 的谱改善作为正确性证明。
4. **NP 提交 4：自洽 RMCDHF 路径。** 在 `CALL NUCPOT` 之后、任何 `YPOT/RINTI` 消费 `ZZ` 之前组合 `ZZ_{\mathrm{total}}`，再运行 NP3。最终 RCI 必须使用同一势和同一参数。分别报告直接固定轨道修正、CSF 重混合和轨道松弛：

   $$
   \Delta E_{\mathrm{NP}}^{\mathrm{total}}
   =\Delta E_{\mathrm{direct}}
   +\Delta E_{\mathrm{CI-mix}}
   +\Delta E_{\mathrm{relax}}.
   $$

不要直接永久修改全局 `lib/lib9290/nucpot.f90` 的默认行为。原型阶段应由独立开关在调用 `NUCPOT` 后叠加势；确认 `rmcdhf`、`rci` 和其他使用 `lib9290` 的程序均需要该能力后，再决定是否下沉为共享库接口。

核极化扩展的通过条件是：关闭开关时结果与基线一致；E1/E2 分项可复现；固定轨道和自洽结果差异可解释；核网格、活动空间和参数不确定度均有收敛记录。它是否改善实验能级只能作为物理结果，不能替代这些实现验证。

## 7. 验收标准与停止规则

修复候选只有在以下条件全部满足时才可进入更大 AS：

- Cl I AS1–AS5 保持正确的 ${}^{2}P_{3/2}<{}^{2}P_{1/2}$ 顺序，且不依赖 MPI 进程数；
- Ni/Ca-like AS2 不再出现 $^3F_J$ 倒序或异常塌缩；
- 变分能量仍下降，但 $J$ 间的额外降低不再达到足以翻转 $\Delta E_J$ 的量级；
- 新轨道与初始估计的重叠、节点数和 $\langle r\rangle$ 变化有可解释记录，异常会触发回退而非静默接受；
- 串行与 MPI 在数值容差内一致，运行可由保存的输入和 commit 完全复现。

若只能恢复 $J$ 顺序而不能改善实验误差，应保留该版本作为“稳定基线”，不要宣称轨道波函数更准确；后续应进入 CI/RCI、Breit/QED、CSF 平衡或 EOL 权重的物理验证。

## 8. 预期交付物

1. `trace/`：每个实验的输入快照、日志和轨道质量 CSV；
2. `scripts/compare_rmcdhf.py`：计算 $\Delta E_J$、能量差、径向重叠、节点数、$\langle r\rangle$ 并生成图表；
3. 一份“输入选择错误 / MPI 差异 / 正交化问题 / 求解器问题 / 物理模型偏置”的证据表；
4. 仅在证据支持时提交 P1/P2 代码补丁，并附逐项回归结果。

## 9. 相关资料

- Wiki 代码分析：`wiki/codes/grasp/rmcdhf90.md`
- Ni/Ca-like 计算分析：`wiki/outputs/cal-report-analysis-cal-report-analysis-ni-ca-like-2026-08-19.md`
- Cl I LBL 分析：`wiki/outputs/cal-report-analysis-cl-i-lbl-orbital-optimization-2026-08-18.md`
- 核极化势与 GRASP：[[nuclear-polarization-potential-neutral-atom-grasp]]
- MPI 源码：`${grasp_code_path}/appl/rmcdhf90_mpi`
