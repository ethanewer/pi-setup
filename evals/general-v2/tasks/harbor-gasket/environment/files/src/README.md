# swellkit 2.4.1 -- Tidal analysis toolkit for Harbor Gasket Maritime Analytics
#
# Build and install from source:  pip install /app/src
# The package ships a small compiled C extension (swellkit._core) so the build
# requires a C toolchain (build-essential). swellkit has no runtime
# dependencies: it is pure Python plus the compiled core, all stdlib.
#
# Public API
#   swellkit.height_hours(t_hours, text)   predicted height for a constituent table
#   swellkit.forecast_file(path, t=0)      same, reading the table from a file
#   swellkit.rms_amplitude(series)         RMS via the compiled C core
#   swellkit.mean_slice(series, a, b)      mean of slice
#   swellkit.haversine_km(lon1,lat1,lon2,lat2)
#   swellkit._core.rms(seq)                C core
#   python -m swellkit.tide <file> [<hour>]  CLI
