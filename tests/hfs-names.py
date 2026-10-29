#!/usr/bin/env python3
"""hfs-names.py BACKING MOUNTPOINT: a read-only view of BACKING that names files as the Linux
hfsplus driver does when a name holds a character outside Unicode's BMP (an emoji): the folder
lists each such character as "??", and a lookup of that listed name finds nothing (ENOENT),
because the driver cannot turn "??" back into the name on disk. Everything else passes through,
inode numbers and extended attributes included. Runs in the foreground until unmounted.

For the loop tests (unreadable-names.sh); needs mfusepy (pip) and libfuse3."""
import errno
import os
import sys

from mfusepy import FUSE, FuseOSError, Operations

BACKING = os.path.realpath(sys.argv[1])


def shown(name):
    """The name as hfsplus lists it: each UTF-16 code unit it cannot convert becomes '?'."""
    return "".join("??" if ord(c) > 0xFFFF else c for c in name)


def oserror(fn):
    def call(self, path, *a):
        try:
            return fn(self, BACKING + path, *a)
        except OSError as e:
            raise FuseOSError(e.errno or errno.EIO) from None
    return call


class HfsNames(Operations):
    use_ns = True

    @oserror
    def getattr(self, path, fh=None):
        st = os.lstat(path)
        d = {k: getattr(st, k) for k in ("st_mode", "st_ino", "st_nlink", "st_uid", "st_gid", "st_size", "st_blocks")}
        d.update(st_atime=st.st_atime_ns, st_mtime=st.st_mtime_ns, st_ctime=st.st_ctime_ns)
        return d

    @oserror
    def readdir(self, path, fh):
        # With each entry's type, as hfsplus gives it from the catalog, even for a name it cannot look up.
        with os.scandir(path) as it:
            return [".", ".."] + [(shown(e.name), {"st_mode": e.stat(follow_symlinks=False).st_mode, "st_ino": e.inode()}, 0) for e in it]

    @oserror
    def readlink(self, path):
        return os.readlink(path)

    @oserror
    def open(self, path, flags):
        if flags & (os.O_WRONLY | os.O_RDWR):
            raise OSError(errno.EROFS, "read-only")
        return os.open(path, os.O_RDONLY)

    def read(self, path, size, offset, fh):
        return os.pread(fh, size, offset)

    def release(self, path, fh):
        os.close(fh)
        return 0

    @oserror
    def listxattr(self, path):
        return os.listxattr(path, follow_symlinks=False)

    @oserror
    def getxattr(self, path, name, position=0):
        return os.getxattr(path, name, follow_symlinks=False)

    @oserror
    def statfs(self, path):
        v = os.statvfs(path)
        return {k: getattr(v, k) for k in ("f_bsize", "f_frsize", "f_blocks", "f_bfree", "f_bavail", "f_files", "f_ffree", "f_favail", "f_namemax")}


if __name__ == "__main__":
    FUSE(HfsNames(), sys.argv[2], foreground=True, ro=True, use_ino=True, allow_other=True, fsname="hfsnames")
