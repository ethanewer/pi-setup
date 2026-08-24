# Numerical Integration of Measurement Data

You are analyzing experimental measurement data that contains periodic sensor readings. The data consists of timestamp-value pairs collected at irregular intervals. Your task is to compute the integral of these measurements over time using numerical integration.

## Your Task

1. **Read the input data** from `/app/measurements.json`. The file contains an array of objects, each with:
   - `timestamp`: float representing time in seconds
   - `value`: float representing sensor reading

2. **Perform numerical integration** to compute the total area under the value-time curve using the trapezoidal rule:
   ```
   integral = Σ_{i=1}^{n-1} 0.5 * (value_i + value_{i+1}) * (timestamp_{i+1} - timestamp_i)
   ```
   where `n` is the number of data points.

3. **Calculate additional statistics**:
   - Mean value (average of all values)
   - Time-weighted average (integral divided by total time span)

4. **Output the results** to `/app/integration_results.json` with the following structure:
   ```json
   {
     "total_integral": float,
     "mean_value": float,
     "time_weighted_average": float,
     "total_time_span": float,
     "data_points": integer
   }
   ```
   All float values must be rounded to 4 decimal places.

## Expected Outputs

- `/app/integration_results.json`: JSON file with the specified structure containing the integration results

## Notes

- The trapezoidal rule approximates the integral by summing the areas of trapezoids between consecutive data points
- If there's only one data point, the integral should be 0
- Input data is guaranteed to be sorted by timestamp in ascending order
- Use Python's built-in `json` module for reading and writing JSON