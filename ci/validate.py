#!/usr/bin/python3
# Validate basic syntax of shell script and yaml.

import os
import stat
import subprocess
import yaml

validated = 0


def openat(dirfd, name, mode="r"):
    def opener(path, flags):
        return os.open(path, flags, dir_fd=dirfd)

    return open(name, mode, opener=opener)


def validate_shell(rootfd, name):
    subprocess.check_call(["bash", "-n", name], preexec_fn=lambda: os.fchdir(rootfd))
    global validated
    validated += 1


def validate_yml(rootfd, name):
    with open(os.open(name, dir_fd=rootfd, flags=os.O_RDONLY)) as f:
        yaml.safe_load(f)
    result = subprocess.run(
        ["grep", "-RniEv", "^(  )*[a-z#/-]|^$|^#", name], encoding="UTF-8"
    )
    if result.returncode == 0:
        raise Exception(
            "Found likely invalid indentation in YAML file: {}".format(name)
        )


for root, dirs, files, rootfd in os.fwalk("."):
    # Skip .git, repo, cache, tmp, logs, fedora-comps
    for d in [".git", "repo", "cache", "tmp", "logs", "fedora-comps", "ci"]:
        if d in dirs:
            dirs.remove(d)
    for name in files:
        if name == ".zuul.yaml":
            continue
        if name.endswith((".yaml", ".yml")):
            print("Validating:", name)
            validate_yml(rootfd, name)
            validated += 1
            continue
        elif name.endswith(".sh"):
            print("Validating:", name)
            validate_shell(rootfd, name)
            continue
        stbuf = os.lstat(name, dir_fd=rootfd)
        if not stat.S_ISREG(stbuf.st_mode):
            continue
        if not stbuf.st_mode & stat.S_IXUSR:
            continue
        mimetype = subprocess.check_output(
            ["file", "-b", "--mime-type", name],
            encoding="UTF-8",
            preexec_fn=lambda: os.fchdir(rootfd),
        ).strip()
        if mimetype == "text/x-shellscript":
            print("Validating:", name)
            validate_shell(rootfd, name)

print(f"Validated {validated} files")
