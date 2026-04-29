require_relative "../../lib/lamport_clock"
require_relative "../../lib/event_log"
require_relative "../../lib/process_node"


class SimulationController < RageController::API

  # Shared simulation state (in production, use Redis or a store)
  @@nodes = {}
  @@global_log = []
  @@mutex = Mutex.new

  def initialize_nodes
    @@mutex.synchronize do
      @@nodes = {
        "P1" => ProcessNode.new("P1"),
        "P2" => ProcessNode.new("P2"),
        "P3" => ProcessNode.new("P3")
      }
      @@global_log = []
    end
    render json: { status: "initialized", nodes: @@nodes.keys }
  end

  # POST /simulation/local_event
  # Body: { process: "P1", description: "write to disk" }
  def local_event
    node = @@nodes[params[:process]]
    return render json: { error: "Node not found" }, status: 404 unless node

    result = node.local_event(params[:description] || "local event")
    @@mutex.synchronize { @@global_log << result }

    render json: result
  end

  # POST /simulation/send_message
  # Body: { from: "P1", to: "P2", message: "hello" }
  def send_message
    from_node = @@nodes[params[:from]]
    to_node   = @@nodes[params[:to]]

    unless from_node && to_node
      return render json: { error: "Invalid process IDs" }, status: 422
    end

    result = from_node.send_message(to_node, params[:message] || "msg")
    @@mutex.synchronize { @@global_log << result }

    render json: result
  end

  # GET /simulation/state
  def state
    nodes_state = @@nodes.transform_values do |node|
      {
        clock: node.clock.time,
        events: node.event_log.ordered
      }
    end

    render json: {
      nodes: nodes_state,
      global_log: @@global_log.sort_by { |e| e[:timestamp] },
      happened_before: compute_happened_before
    }
  end

  private

  # Compute happened-before (→) relationships from the global log
  def compute_happened_before
    events = @@global_log.dup
    relations = []

    events.each_with_index do |e1, i|
      events.each_with_index do |e2, j|
        next if i >= j

        # Same process: earlier index → later index
        if e1[:process] == e2[:process]
          relations << { from: event_label(e1), to: event_label(e2), reason: "same process" }
        end

        # Message passing: send → receive
        if e1[:type] == :send && e2[:type] == :receive &&
           e1[:to] == e2[:process] && e1[:message] == e2[:message]
          relations << { from: event_label(e1), to: event_label(e2), reason: "message" }
        end
      end
    end

    relations
  end

  def event_label(e)
    "#{e[:process]}@t#{e[:timestamp]}"
  end
end
