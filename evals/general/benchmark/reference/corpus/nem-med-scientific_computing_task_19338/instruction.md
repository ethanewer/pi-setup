# Damped Harmonic Oscillator Simulation with Parameter Inference

You are tasked with implementing a scientific simulation and parameter inference pipeline for a damped harmonic oscillator. This requires combining numerical integration, parameter estimation, and structured data handling.

## Physical System

A damped harmonic oscillator follows the differential equation:
```
m * d²x/dt² + b * dx/dt + k * x = 0
```
Where:
- `m` = mass (kg)
- `b` = damping coefficient (N·s/m)
- `k` = spring constant (N/m)
- `x` = position (m)

Given initial conditions: `x(0) = x0`, `v(0) = v0`

## Your Task

You have been provided with an experimental dataset at `/app/experiment_data.json` containing position measurements from a real oscillator. Your goal is to:

1. **Implement the ODE solver** using the 4th order Runge-Kutta (RK4) method to simulate the oscillator
2. **Estimate the parameters** (m, b, k) that best fit the experimental data using gradient descent
3. **Generate comprehensive output** including simulation results and analysis

### Step 1: Read and Parse Input Data
Read `/app/experiment_data.json` which contains:
```json
{
  "measurements": [
    {"time": t1, "position": x1},
    {"time": t2, "position": x2},
    ...
  ],
  "initial_conditions": {
    "x0": 1.0,
    "v0": 0.0
  }
}
```

### Step 2: Implement RK4 Solver
Create a function `solve_oscillator(params, t_span, dt)` that:
- Takes parameters: `m`, `b`, `k`
- Returns arrays: `times`, `positions`, `velocities`
- Uses RK4 integration with fixed time step `dt = 0.01`
- Simulates from `t=0` to maximum time in measurements

### Step 3: Implement Parameter Estimation
Create a function `estimate_parameters(measurements, initial_guess)` that:
- Uses gradient descent to minimize mean squared error between simulated and measured positions
- Initial guess: `m=1.0, b=0.1, k=2.0`
- Runs for maximum 1000 iterations or until loss < 1e-6
- Returns optimized parameters and final loss

### Step 4: Generate Output Files
Create two output files:

1. `/app/estimated_parameters.json` - JSON with structure:
```json
{
  "mass_kg": 1.23,
  "damping_coefficient": 0.45,
  "spring_constant": 2.67,
  "final_loss": 0.0012,
  "iterations": 342
}
```

2. `/app/simulation_results.csv` - CSV file with headers:
```
time,measured_position,simulated_position,simulated_velocity,absolute_error
```
Include all time points from measurements, with simulated values at corresponding times.

### Step 5: Generate Summary Statistics
Calculate and print to stdout (console):
1. Root Mean Square Error (RMSE) between measured and simulated positions
2. Maximum absolute error
3. Oscillation frequency estimate: ω = sqrt(k/m - (b/(2m))²)
4. Whether the system is underdamped, critically damped, or overdamped

## Expected Outputs

The tests will verify:
1. `/app/estimated_parameters.json` exists and contains valid JSON with all required keys
2. `/app/simulation_results.csv` exists with correct headers and row count
3. The estimated parameters produce simulation results within tolerance of reference
4. Console output contains the required summary statistics

**Success Criteria:**
- JSON file must parse with `json.load()` and contain all specified keys
- CSV must have exactly 5 columns and N+1 rows (header + data)
- RMSE must be less than 0.05 (indicating good fit)
- All numerical values must be formatted with 4 decimal places