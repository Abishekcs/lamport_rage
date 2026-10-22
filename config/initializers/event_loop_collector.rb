# Time-series sampler for the ELU lab - one JSONL row per second.
#
# Each row is self-contained: timestamp, ELU, process CPU%, RSS. CPU is a
# delta over the /proc stat clock ticks for the same ~1s window the ELU was
# sampled in, so the two columns pair naturally: x=ts, y1=elu, y2=cpu_pct.
#
# One file per worker process (data/elu_<pid>.jsonl), so a -w N run never
# mixes workers up. Files are gitignored.
require "json"
require "fileutils"

data_dir = File.join(Rage.root, "data")
FileUtils.mkdir_p(data_dir)
out = File.open(File.join(data_dir, "elu_#{Process.pid}.jsonl"), "a")

clk_tck = Integer(`getconf CLK_TCK`.strip) rescue 100

cpu_ticks = lambda do
  stat = File.read("/proc/self/stat")
  fields = stat[(stat.rindex(")") + 2)..].split
  # fields 14/15 utime+stime, re-indexed after stripping pid and comm
  [fields[11].to_f, fields[12].to_f]
end

prev = [Process.clock_gettime(Process::CLOCK_MONOTONIC), *cpu_ticks.call]

Rage::Telemetry.every(1_000) do
  now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  elapsed = now - prev[0]
  next if elapsed <= 0

  ut, st = cpu_ticks.call
  cpu_pct = (ut - prev[1] + st - prev[2]) / clk_tck / elapsed * 100
  prev = [now, ut, st]

  elu = Iodine::Perf.event_loop_utilization(key: :collector)
  rss_kb = File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i

  out.puts({ ts: Time.now.to_f, pid: Process.pid, elu: elu&.round(4),
             cpu_pct: cpu_pct.round(2), rss_kb: rss_kb }.to_json)
  out.flush
end
