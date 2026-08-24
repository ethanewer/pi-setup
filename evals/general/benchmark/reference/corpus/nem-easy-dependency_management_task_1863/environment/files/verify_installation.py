#!/usr/bin/env python3
"""
Verification script for package installation.
This script tests that pandas, numpy, and matplotlib are correctly installed.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import os

def main():
    """Test all three packages."""
    print("Testing package imports...")
    
    # Test numpy
    print("Creating random data with numpy...")
    data = np.random.rand(10, 10)
    print(f"Data shape: {data.shape}")
    
    # Test pandas
    print("Creating DataFrame with pandas...")
    df = pd.DataFrame(data, columns=[f'col_{i}' for i in range(10)])
    print(f"DataFrame shape: {df.shape}")
    print(f"Mean of column 0: {df['col_0'].mean():.4f}")
    
    # Test matplotlib
    print("Creating plot with matplotlib...")
    plt.figure(figsize=(8, 6))
    plt.plot(df.mean(), marker='o')
    plt.title('Mean of each column')
    plt.xlabel('Column index')
    plt.ylabel('Mean value')
    plt.grid(True, alpha=0.3)
    
    # Save plot
    plot_path = '/app/test_plot.png'
    plt.savefig(plot_path, dpi=100, bbox_inches='tight')
    plt.close()
    
    print(f"Plot saved to: {plot_path}")
    print("All packages installed successfully")

if __name__ == '__main__':
    main()