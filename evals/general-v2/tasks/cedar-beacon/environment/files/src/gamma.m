% gamma.m - Cedar Beacon forward attenuation: three read paths merge to one.
% fin : 1 x n row vector of depth readings (n >= 1)
% leak : scalar half-sheet reflection loss
% Returns g (1 x n row) and, via the endpoint concat, the derived scalar.

function [g, gamma_scalar] = gamma_path(fin, leak)
    n   = numel(fin);
    a   = (fin + leak) .* 1.5;    % control path: leak-boosted depth
    b   = flip(fin);              % reflected path: reversed index order
    ramp = zeros(1, n);
    ramp(1:2:n) = fin(1:2:n);     % keep only the odd-indexed readings on ramp
    g   = a + b + ramp;           % elementwise merge of the three paths
    packed = [g(1) g(end)];       % endpoint concat
    gamma_scalar = sum(g) + packed(1) + packed(2);
end
