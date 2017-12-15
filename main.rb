require 'mechanize'
require 'json'
require 'webrick'
require 'date'
require 'parallel'

Shift = Struct.new(:start, :end)

class InvalidQueryError < StandardError
end

def main(email)
  agent = Mechanize.new
  login =  agent.post(
    "https://kintai.jinjer.biz/v1/manager/sign_in",
    :company_code => ENV['JINJER_COMPANY_CODE'],
    :email => ENV['JINJER_EMAIL'],
    :password => ENV['JINJER_PASSWORD'],
  ).body
  api_token = JSON.parse(login)['data']['token']
  p api_token

  shifts = Parallel.map(0..1, in_threads: 2) { |i|
    body = agent.post(
      'https://kintai.jinjer.biz/v1/manager/shifts/schedule_month_for_web',
      {
        :shop_ids => ENV['JINJER_SHOP_ID'],
        :month => (DateTime.now >> i).to_time.month.to_s,
        :year => (DateTime.now >> i).to_time.year.to_s,
      }, {
        'Api-Token' => api_token
      }
    ).body
    next JSON.parse(body)
  }.map{ |data|
    data['data'][0]['users'].find do |user|
      user['user_info']['email'] == email
    end
  }.map{ |user|
    if user.nil?
      raise InvalidQueryError
    end
    user['days'].map{ |day|
      day['shifts'].map do |shifts|
        Shift.new(Time.at(shifts['time_attend']), Time.at(shifts['time_out']))
      end
    }
  }.flatten

  p shifts

  return ([
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//hacksw/handcal//NONSGML v1.0//EN",
    "X-WR-TIMEZONE:UTC"
  ] + shifts.reduce([]){ |prev, shift|
      prev + [
        "BEGIN:VEVENT",
        "DTSTAMP;VALUE=DATE-TIME:" + formatdate(Time.now),
        "DTSTART;TZID=UTC;VALUE=DATE-TIME:" + formatdate(shift.start),
        "DTEND;TZID=UTC;VALUE=DATE-TIME:" + formatdate(shift.end),
        "SUMMARY:アルバイト",
        "END:VEVENT",
      ]
  } + ["END:VCALENDAR", ""]).join("\n")
end

def formatdate(d)
  d.getutc.strftime('%Y%m%dT%H%M%S%z')
end

def get_email(req)
  raise InvalidQueryError unless req.query.has_key?('account')
  return req.query['account'] + ENV['JINJER_EMAIL_SUFFIX']
end

server = WEBrick::HTTPServer.new(:Port => ENV['PORT'])
server.mount_proc('/') do |req, res|
  begin
    body = main(get_email(req))
  rescue InvalidQueryError
    res.body = 'Invalid query.'
  else
    res['Content-Type'] = 'text/calendar'
    res.body = body
  end
end
server.start
