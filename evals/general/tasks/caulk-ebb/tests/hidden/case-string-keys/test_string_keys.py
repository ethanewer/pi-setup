import math

import networkx as nx


def test_string_keys_soft_configuration_no_crash():
    # kappas keys are node labels (strings); the hidden degrees are the
    # values.  The generator must average the degree values and construct
    # the graph, whatever the node labels look like.
    n = 40
    kappas = {f"node_{i:02d}": 1 + (i % 4) for i in range(n)}
    G = nx.geometric_soft_configuration_graph(beta=2.5, kappas=kappas, seed=11)
    assert len(G) == n
    assert set(G.nodes) == set(kappas)
    assert max(deg for _, deg in G.degree) <= n
    for node, kappa in kappas.items():
        assert G.nodes[node]["kappa"] == kappa
        assert "theta" in G.nodes[node]
        assert "radius" in G.nodes[node]


def test_string_keys_mean_of_values_not_hardcoded():
    # The hidden degrees average to exactly 2.5 here (values 1..4 in a
    # cycle).  The radial layout is determined by the mean hidden degree
    # through mu, so the per-node radius attributes expose WHICH mean was
    # used: the true mean of the VALUES (2.5), not a hardcoded constant,
    # not the mean of the keys (uncomputable for strings), and not the
    # wrong-value mean of 1.0 that a dishonest fix might substitute.
    n = 40
    kappas = {f"node_{i:02d}": 1 + (i % 4) for i in range(n)}
    beta = 2.5
    G = nx.geometric_soft_configuration_graph(beta=beta, kappas=kappas, seed=11)
    assert abs(sum(kappas.values()) / len(kappas) - 2.5) < 1e-12

    mean_degree = sum(kappas.values()) / len(kappas)
    mu = beta * math.sin(math.pi / beta) / (2 * math.pi * mean_degree)
    zeta = 1 if beta > 1 else 1 / beta
    kappa_min = min(kappas.values())
    R_c = 2 * max(1, beta) / (beta * zeta)
    R_hat = (2 / zeta) * math.log(n / math.pi) - R_c * math.log(mu * kappa_min)
    expected = {node: R_hat - R_c * math.log(kappa) for node, kappa in kappas.items()}
    for node, radius in expected.items():
        assert math.isclose(G.nodes[node]["radius"], radius, rel_tol=1e-12)

    # Density is also only right for the true mean: with the values' mean of
    # 2.5 this seed produces 45 edges; substituting a mean of 1.0 pushes the
    # count to 116 and a mean of 3.0 drops it to 39.  The band below admits
    # the true value with generous slack and excludes both wrong substitutions.
    e = G.number_of_edges()
    assert 25 <= e <= 65, f"edge count {e} is not the density the degree values imply"