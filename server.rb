require 'bundler/setup'

require 'sinatra'
require 'tzinfo'
require 'net/http'
require 'uri'
require 'ri_cal'
require 'yaml'
require 'rdiscount'

configure do
  set :allow_html, (ENV['ALLOW_HTML'] || false)
  set :twitter, ENV['TWITTER']
end

class Calendar
  def initialize(timezone, days_lookahead)
    @timezone = timezone
    @days_lookahead = days_lookahead

    parse
  end
  attr_reader :timezone, :days_lookahead, :name, :today, :events

  def gcal
    ENV['GCAL_CALENDAR_ID']
  end

  def gcal_url
    "http://www.google.com/calendar/ical/#{gcal}/public/basic.ics"
  end

  def gcal_feed_url
    "http://www.google.com/calendar/feeds/#{gcal}/public/basic"
  end

  def parse
    ical_string = Net::HTTP.get URI.parse(gcal_url)
    components = RiCal.parse_string ical_string
    calendar = components.first
    @name = calendar.x_properties['X-WR-CALNAME'].first.value
    @today = to_timezone_date(DateTime.now)
    occurrences = calendar.events.map do |e|
      e.occurrences(:starting => @today, :before => @today + days_lookahead)
    end
    @events = occurrences.flatten.sort { |a,b| a.start_time <=> b.start_time }
  end

  def to_timezone_date(datetime)
    current = to_timezone(datetime)
    Date.new(current.year, current.month, current.day)
  end

  # FIXME: DRY
  def to_timezone(datetime)
    timezone.utc_to_local(datetime.new_offset(0))
  end
end

helpers do
  def format_time_range(start_time, end_time)
    output = format_time(start_time)
    output << " &mdash; #{format_time(end_time)}" unless end_time.nil?
    output << ", #{to_timezone(start_time).strftime('%d %b %Y')}"
  end

  def markdown(text)
    content = settings.allow_html ? text : escape_html(text)
    RDiscount.new(content).to_html
  end

  def format_time(datetime)
    to_timezone(datetime).strftime('%I:%M%p')
  end

  def to_timezone(datetime)
    timezone.utc_to_local(datetime.new_offset(0))
  end

  def timezone
    TZInfo::Timezone.get(ENV['TIMEZONE'])
  end

  def days_lookahead
    (ENV['DAYS_LOOKAHEAD'] || 30).to_i
  end

  alias_method :h, :escape_html
end

# TODO: Add caching support

get '/' do
  # TODO: Tidy, separate out, error handling support
  @calendar = Calendar.new(timezone, days_lookahead)
  erb :events
end

get '/stylesheet.css' do
  content_type 'text/css'
  sass :stylesheet
end
