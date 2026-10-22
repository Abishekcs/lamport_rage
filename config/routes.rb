Rage.routes.draw do
  root to: ->(env) { [200, {}, ["It works!"]] }

  post "/simulation/init",          to: "simulation#initialize_nodes"
  post "/simulation/local_event",   to: "simulation#local_event"
  post "/simulation/send_message",  to: "simulation#send_message"
  get  "/simulation/state",         to: "simulation#state"

  # ELU lab: diagnostic matrix + Prometheus exposition
  get  "/lab/burn",       to: "lab#burn"        # CPU burn in the reactor
  get  "/lab/sleep",      to: "lab#sleep_ms"    # blocking call in the reactor
  get  "/lab/thread_burn", to: "lab#thread_burn" # CPU burn on a background thread
  get  "/lab/metrics",    to: "lab#metrics"     # Prometheus scrape target
end
