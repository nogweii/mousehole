require 'json'

class Time
  def to_json(*a)
    "new Date(#{to_i*1000})"
  end
end

module JSON
  class Parser
    DATE = /new Date\((\d+)\)/
    alias_method :parse_value2, :parse_value
    def parse_value
      case
      when scan(DATE)
        Time.at(self[1].to_i/1000)
      else
        parse_value2
      end
    end
  end
end
