#!/usr/bin/env python3
"""
Example verification script structure.
This is just an example - you need to write your own.
"""

# Import both required packages
import numpy as np
import matplotlib.pyplot as plt

# Create a 50x50 array of random numbers
data = np.random.rand(50, 50)

# Calculate and print the mean
mean_value = np.mean(data)
print(mean_value)

# Create a simple plot (don't save to disk)
fig, ax = plt.subplots()
ax.hist(data.flatten())
# Close the figure to free memory
plt.close(fig)