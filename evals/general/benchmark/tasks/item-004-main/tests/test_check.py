import sys, os
import numpy as np

# The compiled extension should be importable from /app/workbench (built in place).
sys.path.insert(0, '/app/workbench')

def main():
    # Guard: agent must have modernized setup.py off the removed numpy.distutils.
    try:
        with open('/app/workbench/setup.py') as f:
            src = f.read()
        if 'numpy.distutils' in src:
            with open('/logs/verifier/reward.txt', 'w') as f:
                f.write("0")
            return
    except OSError:
        with open('/logs/verifier/reward.txt', 'w') as f:
            f.write("0")
        return

    try:
        import legacy_vec as lv
    except Exception as e:
        with open('/logs/verifier/reward.txt', 'w') as f:
            f.write("0")
        return

    checks = 0
    try:
        v = lv._dotprod(np.array([1.0, 2.0, 3.0]), np.array([4.0, 5.0, 6.0]))
        if abs(v - 32.0) < 1e-9:
            checks += 1
    except Exception:
        pass

    try:
        v = np.asarray(lv._linspace(1.0, 3.0, 5))
        if np.allclose(v, np.array([1.0, 1.5, 2.0, 2.5, 3.0])):
            checks += 1
    except Exception:
        pass

    try:
        v = lv._double_scalar(3.0)
        if abs(float(v) - 6.0) < 1e-9:
            checks += 1
    except Exception:
        pass

    reward = checks / 3.0
    with open('/logs/verifier/reward.txt', 'w') as f:
        f.write(str(reward))


if __name__ == "__main__":
    main()