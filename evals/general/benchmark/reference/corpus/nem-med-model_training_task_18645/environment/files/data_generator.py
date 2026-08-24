import numpy as np
import torch
from sklearn.datasets import make_classification
from sklearn.preprocessing import StandardScaler
import os

def generate_dataset(seed=42):
    """Generate synthetic classification dataset with imbalance."""
    np.random.seed(seed)
    torch.manual_seed(seed)
    
    # Generate synthetic data with 50 features, 2 informative, some redundancy
    X, y = make_classification(
        n_samples=10000,
        n_features=50,
        n_informative=10,
        n_redundant=5,
        n_clusters_per_class=2,
        weights=[0.6],  # 60% class 0, 40% class 1
        flip_y=0.05,  # 5% label noise
        random_state=seed
    )
    
    # Convert to float32 for PyTorch compatibility
    X = X.astype(np.float32)
    y = y.astype(np.float32).reshape(-1, 1)
    
    # Create output directory
    os.makedirs('/app/data', exist_ok=True)
    
    # Save data
    np.save('/app/data/train_data.npy', X)
    np.save('/app/data/train_labels.npy', y)
    
    print(f"Dataset generated:")
    print(f"  - Samples: {X.shape[0]}")
    print(f"  - Features: {X.shape[1]}")
    print(f"  - Class distribution: {np.mean(y==0)*100:.1f}% class 0, {np.mean(y==1)*100:.1f}% class 1")
    
    return X, y

if __name__ == "__main__":
    generate_dataset(42)