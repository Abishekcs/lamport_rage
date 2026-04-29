class EventLog
  attr_reader :entries

  def initialize(process_id)
    @process_id = process_id
    @entries = []
    @mutex = Mutex.new
  end

  def record(event)
    @mutex.synchronize do
      @entries << event.merge(logged_at: Time.now.iso8601)
    end
  end

  def all
    @mutex.synchronize { @entries.dup }
  end

  def ordered
    all.sort_by { |e| e[:timestamp] }
  end
end
