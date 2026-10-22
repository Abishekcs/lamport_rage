# ELU lab scenarios - deliberately pathological handlers to stress each
# quadrant of the ELU-vs-CPU% diagnostic matrix. One run per scenario,
# separated by idle gaps, makes the segments visible in the JSONL.
require "fileutils"
class LabController < RageController::API
  @@cpu_prev = [Process.clock_gettime(Process::CLOCK_MONOTONIC), nil]

  # CPU ticks (utime+stime) from /proc/self/stat, fields re-indexed after pid+comm
  LAB_CPU_TICKS = lambda do
    stat = File.read("/proc/self/stat")
    fields = stat[(stat.rindex(")") + 2)..].split
    [fields[11].to_f, fields[12].to_f]
  end

  # GET /lab/metrics - Prometheus exposition format, scrape every 1s.
  # elu: rolling window since the previous scrape (key :metrics).
  # idle/elapsed counters: raw cumulative values - rate() of these in
  # PromQL derives ELU natively: 1 - rate(idle)/rate(elapsed).
  def metrics
    idle, elapsed = Iodine::Perf.idle_time_ns, Iodine::Perf.elapsed_ns
    elu = idle&.then { Iodine::Perf.event_loop_utilization(key: :metrics) }

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    tick = LAB_CPU_TICKS.call
    prev = @@cpu_prev
    if prev[1].nil?
      cpu_pct = nil
    else
      dt = now - prev[0]
      cpu_pct = dt.positive? ? (tick[0] - prev[1].first + tick[1] - prev[1].last) / clk_tck / dt * 100 : nil
    end
    @@cpu_prev = [now, tick]

    rss_kb = File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i

    body = +""
    body << "# TYPE iodine_reactor_elu gauge\n"
    body << "iodine_reactor_elu #{elu.nil? ? 'NaN' : format('%.4f', elu)}\n"
    body << "# TYPE iodine_reactor_idle_nanoseconds_total counter\n"
    body << "iodine_reactor_idle_nanoseconds_total #{idle}\n"
    body << "# TYPE iodine_reactor_elapsed_nanoseconds_total counter\n"
    body << "iodine_reactor_elapsed_nanoseconds_total #{elapsed}\n"
    body << "# TYPE iodine_reactor_rss_bytes gauge\n"
    body << "iodine_reactor_rss_bytes #{rss_kb * 1024}\n"
    body << "# TYPE lab_cpu_percent gauge\n"
    body << "lab_cpu_percent #{cpu_pct.nil? ? 'NaN' : format('%.2f', cpu_pct)}\n"
    render plain: body
  end

  def clk_tck
    @clk_tck ||= (Integer(`getconf CLK_TCK`.strip) rescue 100)
  end

  # CPU burn INSIDE the reactor thread: ELU should pin ~1.0, cpu_pct high.
  # The "obvious" overload - both metrics scream.
  def burn
    ms = [params[:ms].to_i, 5_000].min
    puts "[#{Process.pid}] lab: reactor_burn START ms=#{ms}"
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + ms / 1000.0
    i = 0
    i += 1 while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    render json: { scenario: "reactor_cpu_burn", ms: ms }
  end

  # REAL blocking call INSIDE the reactor thread: Process.wait has no fiber
  # scheduler hook (unlike Kernel.sleep, which yields!), so the OS thread and
  # GVL are pinned: ELU pins ~1.0 while cpu_pct stays ~0. The invisible case.
  def sleep_ms
    ms = [params[:ms].to_i, 10_000].min
    puts "[#{Process.pid}] lab: reactor_block START ms=#{ms}"
    child = Process.spawn("sleep", (ms / 1000.0).to_s)
    Process.wait(child)
    puts "[#{Process.pid}] lab: reactor_block END (loop was unresponsive below)"
    render json: { scenario: "reactor_blocked", ms: ms }
  end

  # HOOKLESS freeze INSIDE the reactor thread: File.open on a FIFO with no
  # writer blocks the OS thread in the kernel - no fiber scheduler hook
  # exists for it, so Ruby cannot yield. The loop is frozen: ELU pins ~1.0
  # while cpu_pct stays ~0. Proxy for "a C ext / syscall wedged the reactor".
  def freeze
    ms = [params[:ms].to_i, 20_000].min
    FileUtils.mkdir_p(File.join(Rage.root, "tmp"))
    fifo = File.join(Rage.root, "tmp", "lab_freeze_fifo")
    system("mkfifo #{fifo}") unless File.exist?(fifo)
    raise Errno::ENOENT, "mkfifo failed" unless File.exist?(fifo)
    puts "[#{Process.pid}] lab: reactor_freeze START ms=#{ms}"
    # writer arrives after ms -> open() unblocks
    Thread.new { sleep(ms / 1000.0); File.write(fifo, "x") }
    File.read(fifo)
    File.delete(fifo)
    puts "[#{Process.pid}] lab: reactor_freeze END (loop was frozen above)"
    render json: { scenario: "reactor_frozen", ms: ms }
  end

  # CPU burn on a background OS thread: cpu_pct (whole-process, all threads)
  # should spike while ELU stays at baseline - the reactor is untouched.
  # The false-alarm case: /proc says "loaded", ELU says "reactor fine".
  def thread_burn
    ms = [params[:ms].to_i, 30_000].min
    puts "[#{Process.pid}] lab: thread_burn START ms=#{ms}"
    $burn_count = 0
    $spawn_error = nil
    begin
      $burn_thread = Thread.new do
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + ms / 1000.0
        while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          i = 0; i += 1 while i < 100_000
          $burn_count += 1
        end
        puts "[#{Process.pid}] lab: thread_burn END (burned #{ms}ms)"
      end
    rescue => e
      $spawn_error = "#{e.class}: #{e.message}"
    end
    puts "[#{Process.pid}] lab: thread_burn SPAWNED (burning #{ms}ms; reactor stays responsive)"
    render json: { scenario: "thread_cpu_burn", ms: ms }
  end

  # 1-second progress probe for the burn thread: fps while burning is
  # hundreds; 0 with a live thread means it never gets scheduled.
  def burn_check
    c1 = $burn_count
    sleep 1
    render json: {
      bumping_per_sec: $burn_count - c1,
      thread_status: $burn_thread&.status,
      spawn_error: $spawn_error
    }
  end
end
