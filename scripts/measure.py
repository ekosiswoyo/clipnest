#!/usr/bin/env python3
import json, os, pathlib, subprocess, time
root = pathlib.Path(__file__).resolve().parent.parent
app = root / 'build/ClipNest.app/Contents/MacOS/ClipNest'
results = []
for name in ['empty', 'mixed100']:
    data = root / 'build' / ('benchmark-' + name)
    env = dict(os.environ, CLIPNEST_DATA_DIR=str(data))
    proc = subprocess.Popen([str(app), "--diagnostics"], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        time.sleep(6)
        def sample():
            values = subprocess.check_output(['ps', '-p', str(proc.pid), '-o', 'time=', '-o', 'rss='], text=True).split()
            minutes, seconds = values[0].split(':')
            return int(minutes) * 60 + float(seconds), int(values[1]) / 1024
        start, _ = sample(); began = time.monotonic(); memory = []
        for _ in range(20):
            time.sleep(1); cpu, rss = sample(); memory.append(rss)
        elapsed = time.monotonic() - began
        results.append(dict(history=name, seconds=round(elapsed, 2), cpu_percent_one_core=round((cpu-start)/elapsed*100, 3), rss_mean_MiB=round(sum(memory)/len(memory),2), rss_peak_MiB=round(max(memory),2)))
    finally:
        proc.terminate(); output, _ = proc.communicate(timeout=10)
        results[-1]["panel_closed_at_diagnostic"] = "panelOpen=false" in output
print(json.dumps(results, indent=2))
(root/'build/performance.json').write_text(json.dumps(results, indent=2)+'\n')
