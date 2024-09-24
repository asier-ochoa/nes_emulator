import re

buf = []
with open("../Resources/nestest.log.txt", 'r') as f:
    buf = f.readlines()

buf = [f"C{x[x.index('CYC'):-1].split(':')[1]} - T1; A=0x{re.search(r"A:([0-9A-F]{2}) ", x).group(1)}, X=0x{re.search(r"X:([0-9A-F]{2}) ", x).group(1)}, Y=0x{re.search(r"Y:([0-9A-F]{2}) ", x).group(1)}, PC=0x{x[0:4]}, SP=0x{re.search(r"SP:([0-9A-F]{2}) ", x).group(1)}, IR=0x{x[6:8]}({x[16:19]}), S=0x{re.search(r" P:([0-9A-F]{2})", x).group(1)}" for x in buf]

print("\n".join(buf))

