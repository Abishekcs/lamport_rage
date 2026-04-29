# Implements Lamport's Logical Clock (1978)
# Rules:
#   1. Each process increments its clock before every event
#   2. On send: increment clock, attach timestamp to message
#   3. On receive: clock = max(local, received) + 1

class LamportClock
  attr_reader :time, :process_id

  def initialize(process_id)
    @process_id = process_id
    @time = 0
    @mutex = Mutex.new
  end

  # Rule 1: Local event — just tick
  def tick
    @mutex.synchronize { @time += 1 }
    @time
  end

  # Rule 2: Sending — tick then stamp
  def send_event
    @mutex.synchronize { @time += 1 }
    { timestamp: @time, sender: @process_id }
  end

  # Rule 3: Receiving — max(local, received) + 1
  def receive_event(received_timestamp)
    @mutex.synchronize do
      @time = [@time, received_timestamp].max + 1
    end
    @time
  end
end
