import os
with open("list") as f:
	lines = f.readlines()

for each in lines:
	lib_name = each.strip()
	os.system("./download " + lib_name)
