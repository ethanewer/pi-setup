"""Build-time fixture generator for coral-basin.

From fixed seeds only:
  /app/triage_model.pt      -- frozen risk net Linear(20->32), ReLU, Linear(32->2)
  /app/data/sensor_bags.csv -- visible bag file: 8 bags, 40,000 patches total
"""
import os

import numpy as np
import pandas as pd
import torch
import torch.nn as nn

F, HID, C = 20, 32, 2
FEATS = [f"x{i}" for i in range(F)]
DATA = "/app/data"
os.makedirs(DATA, exist_ok=True)

# 1) frozen model snapshot (weights only; the fleet serves exactly this net).
torch.manual_seed(5100)
net = nn.Sequential(nn.Linear(F, HID), nn.ReLU(), nn.Linear(HID, C))
torch.save(net.state_dict(), "/app/triage_model.pt")

# 2) visible bag file: bag ids arbitrary/non-monotonic, same-bag rows contiguous.
rng = np.random.default_rng(5101)
bags = [(17, 9000), (3, 12000), (42, 2000), (7, 5000),
        (91, 4000), (5, 3000), (23, 4000), (8, 1000)]
frames = []
for bid, n in bags:
    df = pd.DataFrame(rng.uniform(-1.0, 1.0, (n, F)), columns=FEATS)
    df.insert(0, "bag_id", bid)
    frames.append(df)
pd.concat(frames, ignore_index=True).round(6).to_csv(
    os.path.join(DATA, "sensor_bags.csv"), index=False)

sd = torch.load("/app/triage_model.pt", map_location="cpu")
print("triage model tensors:", sorted(sd.keys()))
print("visible bags:", [(b, n) for b, n in bags])
