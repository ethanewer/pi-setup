# This is a template for the verification script
# Replace with your implementation

try:
    import pandas as pd
    import numpy as np
    
    print(f"pandas version: {pd.__version__}")
    print(f"numpy version: {np.__version__}")
    
    # Create a simple 3x2 DataFrame
    df = pd.DataFrame({
        'A': [1, 2, 3],
        'B': [4, 5, 6]
    })
    
    print(f"DataFrame shape: {df.shape}")
    
except ImportError as e:
    print(f"Import error: {e}")
    exit(1)
except Exception as e:
    print(f"Error: {e}")
    exit(1)