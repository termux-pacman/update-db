# pacman-update-db
The core of this repo is the steps to update db packages for pacman

### Service:
main:
```bash
[main]
Server = https://s3.amazonaws.com/termux-main.pacman/$arch
```
x11:
```bash
[x11]
Server = https://s3.amazonaws.com/termux-x11.pacman/$arch
```
root:
```bash
[root]
Server = https://s3.amazonaws.com/termux-root.pacman/$arch
```

### List of action files:
 - [main-db.yml](.github/workflows/main-db.yml)
 - [x11-db.yml](.github/workflows/x11-db.yml)
 - [root-db.yml](.github/workflows/root-db.yml)
