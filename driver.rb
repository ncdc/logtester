#!/bin/env ruby

require 'open3'
require 'thor'

class ProducerLoggerExecutor
  def initialize(message_length, delay, queue_size)
    producer_command = "producer.rb #{message_length} #{delay}"
    logger_command = "gologger -queuesize #{queue_size}"
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

class PidstatExecutor
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

  attr_reader :metrics, :pid

  def initialize(logger_pid)
    @io = IO.popen("pidstat -p #{logger_pid} -h -r -u -w 1")
    @pid = @io.pid
    @metrics = []
    Thread.new { process() }
  end

  def stop
    Process.kill("TERM", @pid)
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

class MyCLI < Thor
  default_task :execute

  desc "execute", "run the logging test"
  option :logger_queue_size, type: :numeric, default: 100, aliases: :q
  option :message_length, type: :numeric, default: 100, aliases: :m
  option :message_rate, type: :numeric, default: 0.0005, aliases: :r
  option :test_length, type: :numeric, default: 10, aliases: :t
  def execute
    `echo '' | sudo tee /var/log/messages`
    `sudo service rsyslog restart`
    start_time = Time.now

    producer_logger = ProducerLoggerExecutor.new(options[:message_length],
                                                 options[:message_rate],
                                                 options[:logger_queue_size])

    logger_pidstat = PidstatExecutor.new(producer_logger.logger_pid)
    producer_pidstat = PidstatExecutor.new(producer_logger.producer_pid)
    rsyslog_pid = `pgrep rsyslog`.to_i
    rsyslog_pidstat = PidstatExecutor.new(rsyslog_pid)

    sleep options[:test_length]

    logger_pidstat.stop
    producer_pidstat.stop
    rsyslog_pidstat.stop
    producer_logger.stop

    end_time = Time.now

    puts "Start time: #{start_time}"
    puts "End time: #{end_time}"
    puts "Total time (seconds): #{end_time - start_time}"
    puts "Logger pidstat"
    puts logger_pidstat.metrics
    puts "Rsyslog pidstat"
    puts rsyslog_pidstat.metrics
    puts "Producer pidstat"
    puts producer_pidstat.metrics
  end
end

MyCLI.start(ARGV)
