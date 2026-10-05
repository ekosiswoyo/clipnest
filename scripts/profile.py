import os, pathlib, subprocess, time
root = pathlib.Path(__file__).resolve().parent.parent
proc = subprocess.Popen([str(root/'build/ClipNest.app/Contents/MacOS/ClipNest'), '--diagnostics'], env=dict(os.environ, CLIPNEST_DATA_DIR=str(root/'build/benchmark-mixed100')))
try:
    time.sleep(6)
    subprocess.run(['sample',str(proc.pid),'3','-file',str(root/'build/profile.txt')],check=True)
finally:
    proc.terminate();proc.wait(timeout=10)
