import tarfile
import tempfile
import sys
from os.path import exists
import json

if len(sys.argv) > 1:
	repo = sys.argv[1]
else:
	print("error: unset repo value")
	exit(1)

db_list_pkgs = {}
if exists(f"{repo}.json"):
	file = open(f"{repo}.json", "r")
	db_list_pkgs = json.loads(file.readlines()[0])
	file.close()

tar = tarfile.open(f"{repo}.db.tar.gz", "r")
tmp_dir = tempfile.TemporaryDirectory()

# Adding and updating packages
list_namepkg = []
for i in tar.getmembers():
	i_sp = i.name.split("/")
	if i_sp[-1] == "desc":
		i0_sp = i_sp[0].split("-")
		namepkg = ""
		for j in range(len(i0_sp)-2):
			namepkg += i0_sp[j]
			if j+1 != len(i0_sp)-2:
				namepkg += "-"
		list_namepkg.append(namepkg)
		if namepkg not in db_list_pkgs.keys() or i_sp[0] != namepkg+"-"+db_list_pkgs[namepkg]["VERSION"]:
			tar.extract(i.name, path=tmp_dir.name)
			file = open(f"{tmp_dir.name}/{i.name}", "r")
			pkginfo = {}
			index = None
			value = None
			for j in file.readlines():
				j_rig = j.replace("\n", "")
				if "%" in j_rig:
					index = j_rig.replace("%", "")
				elif j_rig != "":
					if value == None:
						value = j_rig
					else:
						if type(value) == str:
							value = [value]
						value += [j_rig]
				else:
					if index != "NAME":
						pkginfo[index] = value
					index = None
					value = None
			file.close()
			db_list_pkgs[namepkg] = pkginfo

# Removing packages
list_delete_pkgs = []
for i in db_list_pkgs.keys():
	if i not in list_namepkg:
		list_delete_pkgs.append(i)
for i in list_delete_pkgs:
	del db_list_pkgs[i]

tar.close()
tmp_dir.cleanup()

with open(f"{repo}.json", "w") as outfile:
    json.dump(db_list_pkgs, outfile)
