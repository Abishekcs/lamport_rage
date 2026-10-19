# Event-loop utilization monitor (opt-in: ELU=1).
#
# Iodine tracks how much time the event loop spends genuinely waiting in the
# event provider vs. working (running handlers, fibers, timers). ELU is that
# busy fraction: 0 = loop parked, 1 = saturated, requests queuing behind the
# reactor.
#
# Enable before boot, so every forked worker inherits it with a fresh window;
# the reset in on_start discards the boot segment, which would otherwise read
# as "busy".
if ENV["ELU"] == "1"
  Iodine::Perf.enable_idle_time!

  Iodine.on_state(:on_start) do
    Iodine::Perf.event_loop_utilization(reset: true)
:e end

  # Sample at >=1s intervals: long in-flight waits land in the next sample.
  Rage::Telemetry.every(1_000) do
    elu = Iodine::Perf.event_loop_utilization
    next if elu.nil?

    if elu > 0.9
      puts "[#{Process.pid}] EVENT LOOP saturated: ELU=#{elu.round(3)} - handlers are hogging the reactor"
    else
      puts "[#{Process.pid}] event loop: ELU=#{elu.round(3)}"
    end
  end
end
