require_relative "./lamport_clock.rb"
require_relative "./event_log.rb"

class ProcessNode
  attr_reader :id, :clock, :event_log

  def initialize(id)
    @id = id
    @clock = LamportClock.new(id)
    @event_log = EventLog.new(id)
  end

  def local_event(description = "internal event")
    ts = @clock.tick
    @event_log.record(type: :local, timestamp: ts, description: description)
    { process: @id, type: :local, timestamp: ts, description: description }
  end

  def send_message(to_process, message)
    stamp = @clock.send_event
    entry = {
      type: :send,
      timestamp: stamp[:timestamp],
      to: to_process.id,
      message: message
    }
    @event_log.record(entry)

    # Deliver the message to the receiving process
    to_process.receive_message(stamp[:timestamp], @id, message)

    entry.merge(process: @id)
  end

  def receive_message(received_ts, from_id, message)
    ts = @clock.receive_event(received_ts)
    entry = {
      type: :receive,
      timestamp: ts,
      from: from_id,
      message: message
    }
    @event_log.record(entry)
    entry.merge(process: @id)
  end
end
