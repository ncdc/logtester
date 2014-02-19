#!/bin/env ruby

require 'open3'
require 'thor'
require 'tempfile'
require 'json'

class ProducerLoggerExecutor
  def initialize(options)
    producer_command = "producer.rb #{options[:message_length]} #{options[:message_rate]}"
    @temp_config = Tempfile.open('logshifter.conf')
    config_data = <<EOF
queuesize=#{options[:queue_size]}
inputbuffersize=#{options[:input_buffer_size]}
outputtype=syslog
EOF

    @temp_config.write(config_data)
    @temp_config.close
    logger_command = "logshifter -config #{@temp_config.path}"
    @wait_threads = Open3.pipeline_start(producer_command, logger_command)
  end

  def stop
    @temp_config.unlink
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

  def initialize(name, logger_pid, channel=nil)
    @name = name
    @io = IO.popen("pidstat -p #{logger_pid} -h -r -u -w 1")
    @pid = @io.pid
    @metrics = {}
    @channel = channel
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
      @channel.push(JSON.generate({name: @name, stats: stats})) if @channel

      # throw out the blank
      @io.readline
    end
  end
end

class Driver
  def initialize(options)
    @channel = options[:channel]
    Thread.new do
      `echo '' | sudo tee /var/log/messages`
      `sudo service rsyslog restart`
      start_time = Time.now

      producer_logger = ProducerLoggerExecutor.new(options)

      logger_pidstat = PidstatExecutor.new('logshifter', producer_logger.logger_pid, @channel)
      producer_pidstat = PidstatExecutor.new('producer', producer_logger.producer_pid, @channel)
      rsyslog_pid = `pgrep rsyslog`.to_i
      rsyslog_pidstat = PidstatExecutor.new('rsyslog', rsyslog_pid, @channel)

      sleep options[:test_length]

      logger_pidstat.stop
      producer_pidstat.stop
      rsyslog_pidstat.stop
      producer_logger.stop

      end_time = Time.now

      puts "Start time: #{start_time}"
      puts "End time: #{end_time}"
      puts "Total time (seconds): #{end_time - start_time}"

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
  end
end

MyCLI.start(ARGV)
