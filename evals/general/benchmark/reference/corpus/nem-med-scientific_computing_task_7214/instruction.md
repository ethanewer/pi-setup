## Pendulum Dynamics Simulation with Parameter Sensitivity Analysis

You are a computational physicist studying the behavior of a driven, damped pendulum. Your task is to implement a numerical simulation and perform sensitivity analysis on the system parameters.

## System Description

The pendulum follows the equation of motion:

θ''(t) + b·θ'(t) + (g/L)·sin(θ(t)) = F·cos(ω_d·t)

Where:
- θ(t): Angular displacement (radians)
- b: Damping coefficient (s⁻¹)
- g: Gravitational acceleration (9.81 m/s²)
- L: Pendulum length (m)
- F: Driving force amplitude (rad/s²)
- ω_d: Driving frequency (rad/s)
- t: Time (s)

## Your Task

1. **Implement Numerical Solver**: Read simulation parameters from `/app/parameters.json` and implement a numerical solver using the 4th-order Runge-Kutta method to simulate the pendulum from t=0 to t=T.

2. **Perform Sensitivity Analysis**: For each parameter in the sensitivity study, run multiple simulations with perturbed values and compute the effect on the final state.

3. **Generate Output Files**: Create two output files with specific formats.

## Detailed Requirements

### 1. Read Input Configuration
- Parse `/app/parameters.json` containing base parameters and sensitivity study configuration
- The file contains:
  - `base_params`: Base values for simulation (b, L, F, ω_d, T, dt, initial_conditions)
  - `sensitivity`: List of parameters to analyze with perturbation ranges

### 2. Implement Numerical Integration
- Use 4th-order Runge-Kutta (RK4) method with fixed time step `dt`
- Convert the 2nd-order ODE to two 1st-order ODEs:
  - dθ/dt = ω
  - dω/dt = -b·ω - (g/L)·sin(θ) + F·cos(ω_d·t)
- Store results at every 100th time step to manage file size

### 3. Perform Sensitivity Analysis
- For each parameter in the sensitivity list:
  - Create 5 equally spaced values between [base_value ± range]
  - Run simulation for each perturbed value while keeping other parameters fixed
  - Compute sensitivity metric: S = (θ_final - θ_base)/θ_base × 100%
  - Record maximum absolute deviation across all time steps

### 4. Output Requirements

**Output File 1: `/app/simulation_results.json`**
- JSON format with structure:
```json
{
  "time_series": {
    "time": [t0, t1, ..., tn],
    "angle": [θ0, θ1, ..., θn],
    "angular_velocity": [ω0, ω1, ..., ωn]
  },
  "final_state": {
    "angle": θ_final,
    "angular_velocity": ω_final,
    "energy": 0.5*m*ω_final² + m*g*L*(1-cos(θ_final))
  }
}
```

**Output File 2: `/app/sensitivity_analysis.csv`**
- CSV format with headers:
  `parameter,perturbed_value,angle_deviation_percent,max_abs_deviation`
- One row for each parameter perturbation (5 rows per parameter)
- Values formatted to 4 decimal places
- Use comma as delimiter, no index column

## Expected Outputs
- `/app/simulation_results.json`: Time series and final state for base parameters
- `/app/sensitivity_analysis.csv`: Sensitivity analysis results for all perturbed parameters

## Success Criteria
1. Both output files must exist and be in correct format
2. JSON must be valid and parseable by `json.load()`
3. CSV must have exactly the specified headers and correct number of rows
4. Numerical results must be physically plausible (angles reasonable, energy positive)
5. Sensitivity analysis must cover all specified parameters with correct perturbations