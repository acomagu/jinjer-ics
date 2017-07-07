require 'mechanize'
require 'json'
require 'webrick'

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
  body = agent.post(
    'https://kintai.jinjer.biz/v1/manager/shifts/schedule_month_for_web',
    {
      :shop_ids => ENV['JINJER_SHOP_ID'],
      :month => '7',
      :year => '2017'
    }, {
      'Api-Token' => api_token
    }
  ).body
  data = JSON.parse(body)

  user = data['data'][0]['users'].find do |user|
    user['user_info']['code'] == user_code
  end

  shifts = user['days'].map{ |day|
    day['shifts'].map do |shifts|
      Shift.new(Time.at(shifts['time_attend']), Time.at(shifts['time_out']))
    end
  }.flatten

  return ([
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//hacksw/handcal//NONSGML v1.0//EN",
    "X-WR-TIMEZONE:UTC"
  ] + shifts.reduce([]){ |prev, shift|
      prev + [
        "BEGIN:VEVENT",
        "DTSTAMP;VALUE=DATE-TIME:" + Time.now.iso8601,
        "DTSTART;TZID=UTC;VALUE=DATE-TIME:" + shift.start.iso8601,
        "DTEND;TZID=UTC;VALUE=DATE-TIME:" + shift.end.iso8601,
        "SUMMARY:アルバイト",
        "END:VEVENT",
      ]
  } + ["END:VCALENDAR", ""]).join("\n")
end

server = WEBrick::HTTPServer.new(:Port => ENV['PORT'])
server.mount_proc('/') do |req, res|
  res['Content-Type'] = 'text/calendar'
  res.body = main(req.query['usercode'])
end
server.start
