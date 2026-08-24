import random
random.seed(20240815)
stations = [f"st{i:02d}" for i in range(40)]
with open('/app/data/measurements.txt', 'w') as f:
    for _ in range(1000000):
        s = random.choice(stations)
        t = random.randint(-400, 400) / 10.0
        f.write(f"{s};{t:.1f}\n")
print("generated")