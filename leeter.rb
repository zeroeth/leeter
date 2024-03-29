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
          mission_timestamp = " #{mission.timestamp.strftime("%b %d, %Y %H:%M:%S")} ".bg(:gray).fg(:black)
          puts "%s%s%s%s" % [mission_timestamp, mission.present_name, mission.present_source, mission.present_states]
        end
      end
    end

    def print_market_transactions
      event_whitelist = ['MarketBuy', 'MarketSell']
      market_events = self.log_entries.select{ |entry| event_whitelist.include? entry['event'] }

      market_event_map = { 'MarketBuy' => 'Buy', 'MarketSell' => 'Sell'}
      market_colors = {
        'time'       => { fg: :black, bg: :gray         },
        'name'       => { fg: :gray,  bg: :purple       },
        'star'       => { fg: :gray,  bg: :orange       },
        'item'       => { fg: :gray,  bg: :yellow       },
        'qty'        => { fg: :black, bg: :turquoise    },
        'total'      => { fg: :gray,  bg: :midnightblue },
        'MarketBuy'  => { fg: :black, bg: :pink         },
        'MarketSell' => { fg: :gray,  bg: :blue         },
      }

      market_lookup = {}

      # market event didnt capture all names using dock instead
      docks = self.log_entries.select{ |entry| entry['event'] == "Docked" }
      docks.each{ |dock| market_lookup[dock["MarketID"]] = dock }

      market_events.each do |market_event|
        market_time  = " #{market_event['timestamp'].strftime("%b %d, %Y %H:%M:%S")} "
        market_name  = " %s " % self.truncpad(20, market_lookup[market_event['MarketID']]['StationName'])
        market_star  = " %s " % self.truncpad(10, market_lookup[market_event['MarketID']]['StarSystem'])
        market_item  = " %s " % self.truncpad(25, market_event['Type_Localised'] || market_event['Type'])
        market_tran  = " %s " % self.truncpad(4,  market_event_map[market_event['event']])
        market_qty   = " %s " % self.truncpad(4,  market_event['Count'])
        market_total = " %s " % self.truncpad(10,  market_event['TotalSale'] || market_event['TotalCost'] )

        market_time  =  market_time.bg(market_colors['time' ][:bg]).fg(market_colors['time' ][:fg])
        market_name  =  market_name.bg(market_colors['name' ][:bg]).fg(market_colors['name' ][:fg])
        market_star  =  market_star.bg(market_colors['star' ][:bg]).fg(market_colors['star' ][:fg])
        market_item  =  market_item.bg(market_colors['item' ][:bg]).fg(market_colors['item' ][:fg])
        market_tran  =  market_tran.bg(market_colors[market_event['event']][:bg]).fg(market_colors[market_event['event']][:fg])
        market_qty   =   market_qty.bg(market_colors['qty'  ][:bg]).fg(market_colors['qty'  ][:fg])
        market_total = market_total.bg(market_colors['total'][:bg]).fg(market_colors['total'][:fg])

        puts "%s%s%s%s%s%s%s" % [market_time, market_name, market_star, market_item, market_tran, market_qty, market_total]

      end
    end

    def truncpad truncate_length, input_string
      if input_string.kind_of? Numeric
	input_string = input_string.to_s
        output_string = input_string.rjust(truncate_length)
      else
        output_string = input_string.ljust(truncate_length)
      end
      if input_string.length > truncate_length
        output_string = input_string.slice(0..truncate_length-4) + "..."
      end

      output_string
    end


    def print_brief_log
      event_blacklist = ['ReceiveText']
      event_dedupes   = ['Scan', 'ShipTargeted', 'FSSSignalDiscovered']
 
      filtered_events = self.log_entries.select { |entry| !event_blacklist.include? entry['event'] }

      available_colors = Rainbow::X11ColorNames::NAMES.dup.keys 

      event_types  = filtered_events.group_by { |entry| entry['event'] }.keys
      event_colors = {}

      event_types.each do |event_type|

        color_index = rand( available_colors.length )
        color = available_colors.delete_at(color_index)
        event_colors[event_type] = {fg: :black, bg: color}

      end


      filtered_events.each_with_index do |event, index|

	if event_dedupes.include?(event['event']) && index > 0 && filtered_events[index-1]['event'] == event['event']
          next
        end

        event_timestamp = " #{event['timestamp'].strftime("%b %d, %Y %H:%M:%S")} ".bg(:gray).fg(:black)
        event_bg = event_colors[event['event']][:bg]
        event_fg = event_colors[event['event']][:fg]
        event_info = (" %s " % self.truncpad(20, event['event'])).bg(event_bg).fg(event_fg)
        puts "%s%s" % [event_timestamp, event_info] 
      end
    end
  end # class reader
end # module leeter



# MISSION CLASSES #######################################################

class Mission
  attr_accessor :mission_id
  attr_accessor :timestamp
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

  def truncpad truncate_length, input_string
    output_string = input_string.ljust(truncate_length)
    if input_string.length > truncate_length
      output_string = input_string.slice(0..truncate_length-4) + "..."
    end

    output_string
  end


  # temporary presenter
  def present_name
    name_string = self.truncpad(30, self.name)

    name_string = " %s " % name_string
    name_string = name_string.fg(self.colors['Name'][:fg])
    name_string = name_string.bg(self.colors['Name'][:bg])
  end

  def present_source
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

    source_string = self.truncpad(30, source_string)

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
      self.timestamp           = event_json['timestamp']
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


# MARKET CLASSES #######################################



leeter_reader = Leeter::ReadLogFile.new


leeter_reader.read_all_log_files
#leeter_reader.print_log_by_event_count
leeter_reader.print_brief_log
leeter_reader.print_mission_status
leeter_reader.print_market_transactions
