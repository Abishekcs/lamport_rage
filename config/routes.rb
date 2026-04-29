Rage.routes.draw do
  root to: ->(env) { [200, {}, ["It works!"]] }

  post "/simulation/init",          to: "simulation#initialize_nodes"
  post "/simulation/local_event",   to: "simulation#local_event"
  post "/simulation/send_message",  to: "simulation#send_message"
  get  "/simulation/state",         to: "simulation#state"
end
