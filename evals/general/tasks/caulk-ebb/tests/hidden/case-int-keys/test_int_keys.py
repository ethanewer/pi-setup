import math

import networkx as nx


def test_int_keys_mean_degree_uses_values_not_keys():
    # The node ids happen to be large numbers while every hidden degree is 1,
    # so the degrees' mean is 1.  Averaging the node ids instead (a mean of
    # ~1019) collapses mu and leaves the graph essentially EDGE-LESS, while
    # averaging the values must produce the ~20 edges the model predicts for
    # 40 nodes of mean degree 1.
    n = 40
    kappas = {1000 + i: 1 for i in range(n)}
    G = nx.geometric_soft_configuration_graph(beta=2.5, kappas=kappas, seed=42)
    assert G.number_of_edges() >= 5
    assert G.number_of_edges() < n * (n - 1) // 2
    assert all(deg < n - 1 for _, deg in G.degree)


def test_radial_layout_reflects_mean_of_values():
    # The radial layout depends on the mean hidden degree through mu.  Recompute
    # the documented radius attributes from the mean of the VALUES and require
    # the generated attributes to match exactly.
    n = 40
    kappas = {1000 + i: 1 for i in range(n)}
    beta = 2.5
    G = nx.geometric_soft_configuration_graph(beta=beta, kappas=kappas, seed=42)
    mean_degree = sum(kappas.values()) / len(kappas)
    mu = beta * math.sin(math.pi / beta) / (2 * math.pi * mean_degree)
    zeta = 1 if beta > 1 else 1 / beta
    kappa_min = min(kappas.values())
    R_c = 2 * max(1, beta) / (beta * zeta)
    R_hat = (2 / zeta) * math.log(n / math.pi) - R_c * math.log(mu * kappa_min)
    expected = {node: R_hat - R_c * math.log(kappa) for node, kappa in kappas.items()}
    for node, radius in expected.items():
        assert math.isclose(G.nodes[node]["radius"], radius, rel_tol=1e-12)