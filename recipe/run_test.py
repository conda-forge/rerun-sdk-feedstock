import platform
import subprocess

from packaging import version


def main():

    
    if platform.system() == "Linux":
        libc_ver = version.parse(platform.libc_ver()[1])
        if libc_ver < version.parse("2.27"):
            print("WARNING: Skipping runtime tests since GLIBC version is lower than 2.27")
            return True

    # Version we can import rerun
    import rerun

    # Verify we can run rerun as an executable
    subprocess.run(["rerun", "--version"], check=True)

if __name__ == '__main__':
    main()
