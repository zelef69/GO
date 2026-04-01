import os
import shutil
import stat

location = shutil.which("luci-auth")
print("PATH=" + os.environ.get("PATH", ""))
print("which=" + str(location))
if location:
    mode = oct(os.stat(location).st_mode)
    print("mode=" + mode)
