import random
random.seed(20260212)
word="MAJESTIC"
msg=[ord(c)-65 for c in word]
lines=["# M-IIF fused-filament machine runner 1.4",
 "# filament: REF-2400 gauge feeder",
 "# part: 'nameplate' 24 x 32 mm, petal base",
 "M104 S215", "M140 S50", "G92 X0 Y0 Z0", "M73 P0", "G28 X0 Y0 Z0"]
x=0.0; y=0.0; z=0.0
def travel_noise(x,y,z):
    for _ in range(random.randint(25,60)):
        x += random.uniform(0.05,3.2); y += random.uniform(-1.5,1.5)
        lines.append(f"G0 X{x:.2f} Y{y:.2f} Z{z:.1f}")
    return x,y
for ch in msg:
    lines.append(f"; LAYER:{z:.1f}  BAND CUT  DIM{z:.1f}")
    lines.append(f"G0 Z{z:.1f}")
    for _ in range(random.randint(3,7)):
        lines.append(f"M553 S{random.randint(150,260)} E{random.randint(60,120)} ; heater feedback")
        lines.append(f"M140 S{random.randint(40,64)}")
    x,y=travel_noise(x,y,z)
    for _ in range(random.randint(1,3)):
        dx=x+random.uniform(0,2.0); dy=y+random.uniform(0,5.0)
        lines.append(f"G1 X{dx:.2f} Y{dy:.2f} F{random.randint(1,5):.1f} (contour/corner, no part feed)")
    x,y=travel_noise(x,y,z)
    feed=float(ch)+0.5
    lines.append(f"G1 X{x:.2f} Y{y:.2f} E{feed:.1f} FILE.{ch} ; low feed fill seg")
    z += 0.4
lines += ["M104 S0","G28 Z0","M31 P0 ; motor park","G1 Z4.0 X0.0 Y0.0 F1.0",
          "# job complete: nameplate banded 8-cell"]
open('/app/job.gcode','w').write("\n".join(lines)+"\n")
print("TOTAL LINES:",len(lines))
