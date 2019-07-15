# encoding: UTF-8 is over 9000

require 'bundler/setup'
require 'pry'
require 'json'
require 'time'

module Leeter
  class ReadLogFile
    attr_accessor :log_entries
    attr_accessor :event_blacklist
    attr_accessor :correlation_matrix

    def initialize
      self.log_entries = []
      self.event_blacklist = ["Music"]
    end


    def read_all_log_files
      log_file_names = Dir.glob File.join("logs", "*.log")

      log_file_names.each do |log_file_name|
        file_logs = read_log_file log_file_name
        self.log_entries.push *file_logs
      end

      self.log_entries.sort_by{|entry| entry['timestamp']}
    end


    def read_log_file(log_file_name)
      log_file = File.open File.join(log_file_name)

      log_file_entries = []

      log_file.each do |line|
        log_line_json = JSON.parse line

        parsed_time = Time.iso8601 log_line_json['timestamp']
        log_line_json['timestamp'] = parsed_time

        unless self.event_blacklist.include? log_line_json['event']
          log_file_entries.push log_line_json
        end
      end

      return log_file_entries
    end


    def print_log_by_event_count

      log_groups = self.log_entries.group_by{ |entry| entry['event'] }

      event_sizes = log_groups.collect do |event, logs_for_event|
        {event: event, log_count: logs_for_event.length}
      end

      event_sizes.sort_by{|event| event[:log_count]}.each do |event|
        puts "#{event[:event]}: #{event[:log_count]}"
      end
    end


    def print_mission_status
    end
  end
end


leeter_reader = Leeter::ReadLogFile.new


leeter_reader.read_all_log_files
leeter_reader.print_log_by_event_count
leeter_reader.print_mission_status
