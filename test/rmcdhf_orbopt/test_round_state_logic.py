"""Offline checks for CI-root assignment and target-state gating.

The production implementation lives in ``orbopt_round_state.f90`` and uses
the same Hungarian assignment recurrence exercised here.  These small tests
keep the edge cases executable without launching an MPI calculation:
identity, a legal root swap, a non-greedy overlap matrix, and target states
that span different Jπ blocks while an unrelated auxiliary root moves badly.
"""

from __future__ import annotations

from math import isclose


def max_weight_assignment(weights: list[list[float]]) -> list[int]:
    """Return the zero-based column assigned to each row."""

    n = len(weights)
    if n == 0 or any(len(row) != n for row in weights):
        raise ValueError("weights must be a non-empty square matrix")
    u = [0.0] * (n + 1)
    v = [0.0] * (n + 1)
    p = [0] * (n + 1)
    way = [0] * (n + 1)
    for row in range(1, n + 1):
        p[0] = row
        column0 = 0
        minimum = [float("inf")] * (n + 1)
        used = [False] * (n + 1)
        while True:
            used[column0] = True
            row0 = p[column0]
            delta = float("inf")
            column1 = 0
            for column in range(1, n + 1):
                if used[column]:
                    continue
                current = -weights[row0 - 1][column - 1] - u[row0] - v[column]
                if current < minimum[column]:
                    minimum[column] = current
                    way[column] = column0
                if minimum[column] < delta:
                    delta = minimum[column]
                    column1 = column
            for column in range(n + 1):
                if used[column]:
                    u[p[column]] += delta
                    v[column] -= delta
                else:
                    minimum[column] -= delta
            column0 = column1
            if p[column0] == 0:
                break
        while True:
            column1 = way[column0]
            p[column0] = p[column1]
            column0 = column1
            if column0 == 0:
                break
    assignment = [0] * n
    for column in range(1, n + 1):
        assignment[p[column] - 1] = column - 1
    return assignment


def target_order_changed(
    targets: list[int], old_energies: list[float], new_energies: list[float], assignment: list[int]
) -> bool:
    """Compare energies after mapping each old target to its current root."""

    old_order = sorted(targets, key=lambda state: old_energies[state])
    current_for_old = {old: current for current, old in enumerate(assignment)}
    new_order = sorted(
        targets,
        key=lambda state: new_energies[current_for_old[state]],
    )
    return old_order != new_order


def target_min_overlap(
    block_matrices: list[list[list[float]]], targets: set[int]
) -> tuple[float, list[int]]:
    """Match each block and return the overlap over selected global rows."""

    minimum = 1.0
    global_assignment: list[int] = []
    offset = 0
    for matrix in block_matrices:
        assignment = max_weight_assignment(matrix)
        global_assignment.extend(offset + old for old in assignment)
        for row, old in enumerate(assignment):
            if offset + row in targets:
                minimum = min(minimum, matrix[row][old])
        offset += len(matrix)
    return minimum, global_assignment


def test_identity_assignment() -> None:
    assignment = max_weight_assignment([[1.0, 0.0], [0.0, 1.0]])
    assert assignment == [0, 1]
    assert not target_order_changed([0, 1], [0.0, 100.0], [0.0, 100.0], assignment)


def test_legal_root_swap_preserves_target_identity() -> None:
    weights = [[0.1, 0.95], [0.9, 0.2]]
    assignment = max_weight_assignment(weights)
    assert assignment == [1, 0]
    # The roots exchange row numbers, but mapping by overlap keeps the
    # physical target energies in the original order.
    assert not target_order_changed([0, 1], [0.0, 100.0], [100.0, 0.0], assignment)


def test_hungarian_beats_greedy_choice() -> None:
    weights = [[0.90, 0.80], [0.85, 0.10]]
    assignment = max_weight_assignment(weights)
    assert assignment == [1, 0]
    assert isclose(sum(weights[row][column] for row, column in enumerate(assignment)), 1.65)


def test_target_order_can_span_blocks_and_auxiliary_root_is_ignored() -> None:
    matrices = [
        [[0.99, 0.01], [0.01, 0.99]],
        [[0.98]],
    ]
    minimum, assignment = target_min_overlap(matrices, {0, 2})
    assert isclose(minimum, 0.98)
    assert assignment == [0, 1, 2]
    # Global target states 0 and 2 reside in different blocks.
    assert target_order_changed([0, 2], [0.0, 50.0, 100.0], [120.0, 50.0, 80.0], assignment)


def test_bad_untracked_auxiliary_root_does_not_fail_target_gate() -> None:
    matrices = [
        [[0.99, 0.01], [0.01, 0.10]],
    ]
    minimum, assignment = target_min_overlap(matrices, {0})
    assert assignment == [0, 1]
    assert isclose(minimum, 0.99)


if __name__ == "__main__":
    tests = [
        test_identity_assignment,
        test_legal_root_swap_preserves_target_identity,
        test_hungarian_beats_greedy_choice,
        test_target_order_can_span_blocks_and_auxiliary_root_is_ignored,
        test_bad_untracked_auxiliary_root_does_not_fail_target_gate,
    ]
    for test in tests:
        test()
    print(f"passed {len(tests)} round-state logic tests")
