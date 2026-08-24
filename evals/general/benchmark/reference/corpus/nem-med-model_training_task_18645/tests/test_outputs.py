import os
import json
import torch
import numpy as np
from pathlib import Path

def test_output_exists():
    """Verify all required output files were created."""
    assert os.path.exists('/app/output/training_log.json'), "training_log.json missing"
    assert os.path.exists('/app/output/best_model.pth'), "best_model.pth missing"
    assert os.path.exists('/app/output/summary.txt'), "summary.txt missing"

def test_training_log_structure():
    """Verify training log has correct structure and content."""
    with open('/app/output/training_log.json', 'r') as f:
        log = json.load(f)
    
    assert isinstance(log, list), "Log should be a list of epochs"
    assert len(log) > 0, "Log should contain at least one epoch"
    
    # Check required keys in first epoch
    required_keys = {'epoch', 'train_loss', 'val_loss', 'learning_rate', 'grad_norm', 'epoch_time'}
    assert all(key in log[0] for key in required_keys), f"Missing keys in log entry. Found: {set(log[0].keys())}"
    
    # Check data types
    assert isinstance(log[0]['epoch'], int), "Epoch should be integer"
    assert isinstance(log[0]['train_loss'], (int, float)), "Train loss should be numeric"
    assert isinstance(log[0]['val_loss'], (int, float)), "Val loss should be numeric"
    assert isinstance(log[0]['learning_rate'], (int, float)), "Learning rate should be numeric"
    assert isinstance(log[0]['grad_norm'], (int, float)), "Gradient norm should be numeric"
    assert isinstance(log[0]['epoch_time'], (int, float)), "Epoch time should be numeric"
    
    # Check learning rate decreases (adaptive LR test)
    lr_values = [entry['learning_rate'] for entry in log]
    if len(lr_values) > 5:
        # Learning rate should either stay same or decrease
        for i in range(1, len(lr_values)):
            assert lr_values[i] <= lr_values[i-1] + 1e-9, f"LR increased unexpectedly: {lr_values[i]} > {lr_values[i-1]}"

def test_model_checkpoint():
    """Verify model checkpoint contains required components."""
    checkpoint = torch.load('/app/output/best_model.pth', map_location='cpu', weights_only=False)
    
    required_keys = {'model_state_dict', 'optimizer_state_dict', 'epoch', 'val_loss'}
    assert all(key in checkpoint for key in required_keys), f"Missing keys in checkpoint. Found: {set(checkpoint.keys())}"
    
    # Check model can be loaded
    from model import SimpleNN  # Assume model is defined in train_model.py
    model = SimpleNN(input_size=50, dropout_rate=0.3)
    model.load_state_dict(checkpoint['model_state_dict'])
    
    # Quick forward pass test
    test_input = torch.randn(1, 50)
    output = model(test_input)
    assert output.shape == (1, 1), f"Model output shape incorrect: {output.shape}"
    assert 0 <= output.item() <= 1, f"Model output not in [0,1]: {output.item()}"

def test_summary_file():
    """Verify summary file contains required information."""
    with open('/app/output/summary.txt', 'r') as f:
        content = f.read()
    
    required_metrics = [
        'validation_accuracy',
        'total_training_time', 
        'epochs_trained',
        'lr_reductions',
        'early_stopping_triggered'
    ]
    
    lines = content.strip().split('\n')
    metrics = {}
    for line in lines:
        if ':' in line:
            key, value = line.split(':', 1)
            metrics[key.strip()] = value.strip()
    
    missing = [m for m in required_metrics if m not in metrics]
    assert len(missing) == 0, f"Missing metrics in summary: {missing}"
    
    # Check data types
    try:
        accuracy = float(metrics['validation_accuracy'])
        assert 0 <= accuracy <= 1, f"Accuracy out of range: {accuracy}"
    except ValueError:
        assert False, f"validation_accuracy not numeric: {metrics['validation_accuracy']}"
    
    try:
        time = float(metrics['total_training_time'])
        assert time > 0, f"Training time should be positive: {time}"
    except ValueError:
        assert False, f"total_training_time not numeric: {metrics['total_training_time']}"
    
    try:
        epochs = int(metrics['epochs_trained'])
        assert 1 <= epochs <= 50, f"Epochs out of range: {epochs}"
    except ValueError:
        assert False, f"epochs_trained not integer: {metrics['epochs_trained']}"
    
    try:
        lr_red = int(metrics['lr_reductions'])
        assert lr_red >= 0, f"LR reductions negative: {lr_red}"
    except ValueError:
        assert False, f"lr_reductions not integer: {metrics['lr_reductions']}"
    
    # Early stopping should be boolean
    est = metrics['early_stopping_triggered'].lower()
    assert est in ['true', 'false'], f"early_stopping_triggered not boolean: {est}"

def test_gradient_accumulation_logic():
    """Verify gradient accumulation was implemented correctly."""
    # Import the training script to test functions directly
    import sys
    sys.path.insert(0, '/app')
    
    # Try to import train_model to access helper functions
    try:
        import train_model as tm
        # Check if accumulation steps are handled
        assert hasattr(tm, 'accumulate_gradients') or hasattr(tm, 'train_epoch'), "Gradient accumulation not found"
    except ImportError:
        # If we can't import, at least verify the training log shows accumulation effects
        with open('/app/output/training_log.json', 'r') as f:
            log = json.load(f)
        
        # Gradient norms should be reasonable (clipped at 1.0)
        for entry in log:
            if 'grad_norm' in entry:
                norm = entry['grad_norm']
                # Norm should be <= 1.0 + epsilon due to clipping
                assert norm <= 1.5, f"Gradient norm too large (clipping not working): {norm}"

def test_early_stopping_behavior():
    """Verify early stopping logic was implemented."""
    with open('/app/output/summary.txt', 'r') as f:
        content = f.read().lower()
    
    # Check if early stopping is mentioned
    if 'early_stopping_triggered: true' in content:
        with open('/app/output/training_log.json', 'r') as f:
            log = json.load(f)
        
        # If early stopping triggered, epochs should be < 50
        epochs = len(log)
        assert epochs < 50, f"Early stopping triggered but trained {epochs} epochs"
        
        # Check validation loss plateau detection
        val_losses = [entry['val_loss'] for entry in log]
        # Should have some epochs without improvement before stopping
        # This is a heuristic check
        if len(val_losses) > 10:
            # Count epochs without improvement in last 10 epochs
            improvements = sum(1 for i in range(1, min(10, len(val_losses))) 
                            if val_losses[-i] < val_losses[-i-1])
            assert improvements < 3, "Early stopping triggered but validation loss still improving"