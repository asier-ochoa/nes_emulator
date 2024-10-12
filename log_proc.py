import re

buf = []
with open("../Resources/nestest.log", 'r') as f:
    buf = f.readlines()

buf = [f"{x[:73]} CYC:{re.search(r"CYC:(\d+)", x).group(1)}" for x in buf]

print("\n".join(buf))

