#!/bin/env ruby

require 'open3'

class Executor
  attr_reader :pid

  def initialize(command)
    @io = IO.popen(command)
    @pid = @io.pid
  end

  def stop
    Process.kill("TERM", @pid)
  end
end

class ProducerLoggerExecutor
  def initialize(message_length, delay)
    producer_command = "/root/rubylogger/producer.rb #{message_length} #{delay}"
    logger_command = "/root/go/src/github.com/ncdc/gologger/gologger"
    @wait_threads = Open3.pipeline_start(producer_command, logger_command)
  end

  def stop
    Process.kill("TERM", @wait_threads[0].pid)
  end

  def producer_pid
    @wait_threads[0].pid
  end

  def logger_pid
    @wait_threads[1].pid
  end
end

class PidstatExecutor < Executor
  FIELD_ORDER = [
    :time,
    :pid,
    :user_cpu,
    :system_cpu,
    :guest_cpu,
    :total_cpu_percent,
    :cpu_number,
    :minor_page_faults,
    :major_page_faults,
    :virtual_size,
    :resident_set_size,
    :memory_percent,
    :voluntary_context_switches_per_second,
    :involuntary_context_switches_per_second,
    :command
  ]

  attr_reader :metrics

  def initialize(logger_pid)
    super("pidstat -p #{logger_pid} -h -r -u -w 1")
    @metrics = []
    Thread.new { process() }
  end

  def process
    # throw out the first 2 lines
    2.times { @io.readline }
    loop do
      # throw out the header
      @io.readline

      data = @io.readline
=begin
      #      Time       PID    %usr %system  %guest    %CPU   CPU  minflt/s  majflt/s     VSZ    RSS   %MEM   cswch/s nvcswch/s  Command
             1392404685     24674    0.00    0.00    0.00    0.00     1      0.00      0.00  110188   3756   0.05      0.00      0.00  bash
=end
      stats = {}
      data.split(" ").each_with_index do |value, index|
        stats[FIELD_ORDER[index]] = value
      end
      @metrics << stats

      # throw out the blank
      @io.readline
    end
  end
end

#logger = LoggerExecutor.new
#producer = ProducerExecutor.new(100, 0.01)
producer_logger = ProducerLoggerExecutor.new(100, 0.0005)
logger_pidstat = PidstatExecutor.new(producer_logger.logger_pid)
producer_pidstat = PidstatExecutor.new(producer_logger.producer_pid)
rsyslog_pid = `pgrep rsyslog`.to_i
rsyslog_pidstat = PidstatExecutor.new(rsyslog_pid)
sleep 5
logger_pidstat.stop
producer_pidstat.stop
rsyslog_pidstat.stop
producer_logger.stop
puts "Logger pidstat"
puts logger_pidstat.metrics
puts "Rsyslog pidstat"
puts rsyslog_pidstat.metrics
puts "Producer pidstat"
puts producer_pidstat.metrics
