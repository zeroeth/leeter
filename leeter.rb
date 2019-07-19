# encoding: UTF-8 is over 9000

require 'bundler/setup'
require 'pry'
require 'json'
require 'time'
require 'awesome_print'

require 'rainbow'
require 'rainbow/refinement'
using Rainbow



module Leeter
  class ReadLogFile
    attr_accessor :log_entries
    attr_accessor :event_blacklist
    attr_accessor :correlation_matrix
    attr_accessor :mission_logs

    def initialize
      self.log_entries = []
      self.event_blacklist = ['Music']
      self.mission_logs = MissionLogs.new
    end


    def read_all_log_files
      log_file_names = Dir.glob File.join("logs", "*.log")

      log_file_names.each do |log_file_name|
        file_logs = read_log_file log_file_name
        self.log_entries.push *file_logs
      end

      self.log_entries.sort_by! { |entry| entry['timestamp'] }
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

      log_groups = self.log_entries.group_by { |entry| entry['event'] }

      event_sizes = log_groups.collect do |event, logs_for_event|
        {event: event, log_count: logs_for_event.length}
      end

      event_sizes.sort_by { |event| event[:log_count] }.each do |event|
        puts "%6d %s" % [event[:log_count], event[:event]]
      end
    end


    def print_mission_status
      event_whitelist = ['MissionAbandoned', 'MissionAccepted', 'MissionCompleted', 'MissionFailed', 'MissionRedirected']
      mission_events = self.log_entries.select{ |entry| event_whitelist.include? entry['event'] }

      # do something with bulk mission data? Does it contain missed state values

      mission_events.each do |mission_event|
        mission = self.mission_logs.find_mission mission_event['MissionID']
        mission = mission || Mission.new

        mission.parse_event mission_event

        self.mission_logs.save_mission mission
      end


      self.mission_logs.logs.each do |mission_id, mission|
        # temporary skip for those without earlier states
        unless mission.name == ""
          puts "%s%s%s" % [mission.present_name, mission.present_source, mission.present_states]
        end
      end
    end
  end
end



# MISSION CLASSES #######################################################

class Mission
  attr_accessor :mission_id
  attr_accessor :name
  attr_accessor :faction
  attr_accessor :destination_system
  attr_accessor :destination_station
  attr_accessor :history

  def initialize
    self.name = ""
    self.history = {}
  end

  def colors
    {
      "Name"              => { fg: :black, bg: :orange  },
      "Faction"           => { fg: :gray,  bg: :purple  },
      "Source"            => { fg: :black, bg: :skyblue },
      "MissionCompleted"  => { fg: :black, bg: :green   },
      "MissionAccepted"   => { fg: :black, bg: :gray    },
      "MissionRedirected" => { fg: :black, bg: :blue    },
      "MissionFailed"     => { fg: :gray, bg: :red      },
      "MissionAbandoned"  => { fg: :gray, bg: :brown    }
    }
  end


  # temporary presenter
  def present_name
    truncate_length = 60
    name_string = ("%d %s" % [self.mission_id, self.name]).ljust(truncate_length)
    if name_string.length > truncate_length
      name_string = name_string.slice(0..truncate_length-4) + "..."
    end

    name_string = " %s " % name_string
    name_string = name_string.fg(self.colors['Name'][:fg])
    name_string = name_string.bg(self.colors['Name'][:bg])
  end

  def present_source
    truncate_length = 60

    source_string = "%s" % self.faction

    if self.destination_system || self.destination_station
      source_string = "%s:" % [source_string]

      if self.destination_system
        source_string = "%s %s" % [source_string, self.destination_system.gsub("$MISSIONUTIL_MULTIPLE_FINAL_SEPARATOR;"," | ").gsub("$MISSIONUTIL_MULTIPLE_INNER_SEPARATOR;"," - ")]
      end

      if self.destination_station
        source_string = "%s (%s)" % [source_string, self.destination_station]
      end
    end

    source_string = source_string.ljust(truncate_length)
    if source_string.length > truncate_length
      source_string = source_string.slice(0..truncate_length-4) + "..."
    end

    source_string = " %s " % source_string
    source_string = source_string.fg(self.colors['Source'][:fg])
    source_string = source_string.bg(self.colors['Source'][:bg])
  end

  def present_states
    event_map = {
      "MissionCompleted"  => "Complete  ",
      "MissionFailed"     => "Failed    ",
      "MissionAbandoned"  => "Abandoned ",
      "MissionRedirected" => "Redirected"
    }


    self.history.collect do |event_state, event|

      state_string = " %s " % event_map[event['event']]
      state_string = state_string.fg(self.colors[event['event']][:fg])
      state_string = state_string.bg(self.colors[event['event']][:bg])

    end.join("")

    # get last history's value? or just loop them and print.
  end

  def parse_event event_json
    lookup_key = "%d %s %s" % [event_json['MissionID'], event_json['event'], event_json['timestamp'].to_s]
    if self.history[lookup_key]
      raise "Already have event #{event_json['event']} for mission #{event_json['MissionID']}"
    else
      if event_json['event'] != 'MissionAccepted'
        self.history[lookup_key] = event_json
      end
    end

    case event_json['event']
    when 'MissionAccepted'
      self.mission_id          = event_json['MissionID']
      self.name                = event_json['LocalisedName']
      self.faction             = event_json['Faction']
      self.destination_system  = event_json['DestinationSystem']
      self.destination_station = event_json['DestinationStation']
    when 'MissionCompleted'
    when 'MissionAbandoned'
    when 'MissionFailed'
    when 'MissionRedirected'
    else
      raise "Dont know what event #{event_json['event']} for mission #{event_json['MissionID']}is"
    end
  end
end



class MissionLogs
  attr_accessor :logs

  def initialize
    self.logs = {}
  end

  def find_mission mission_id
    return self.logs[mission_id]
  end

  def save_mission mission
    self.logs[mission.mission_id] = mission
  end
end


leeter_reader = Leeter::ReadLogFile.new


leeter_reader.read_all_log_files
#leeter_reader.print_log_by_event_count
leeter_reader.print_mission_status
