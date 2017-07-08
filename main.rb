require 'mechanize'
require 'json'
require 'webrick'
require 'date'

Shift = Struct.new(:start, :end)

def main(user_code)
  agent = Mechanize.new
  p agent.post(
    "https://kintai.jinjer.biz/v1/manager/sign_in",
    :company_code => ENV['JINJER_COMPANY_CODE'],
    :email => ENV['JINJER_EMAIL'],
    :password => ENV['JINJER_PASSWORD'],
  )
  p agent.get('https://kintai.jinjer.biz/manager/top')
  cookies = agent.cookie_jar.cookies
  api_token = cookies.find{|cookie| cookie.name == 'api_token'}.value
  p api_token

  shifts = (0..1).map{ |i|
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
      user['user_info']['code'] == user_code
    end
  }.map{ |user|
    if user.nil?
      raise InvalidUserCodeError
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

server = WEBrick::HTTPServer.new(:Port => ENV['PORT'])
server.mount_proc('/') do |req, res|
  res['Content-Type'] = 'text/calendar'
  res.body = main(req.query['usercode'])
end
server.start
