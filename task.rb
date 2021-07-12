# frozen_string_literal: true

require 'json'
require 'date'
require 'minitest/autorun'

class Parser
  USER_FIELDS = %w[id first_name last_name age].freeze
  SESSION_FIELDS = %w[user_id session_id browser time date].freeze
  FIELD_LIST = %w[user_fields session_fields].freeze

  FIELD_LIST.each do |arr|
    define_method "parse_#{arr}" do |line|
      fields = line.split(',')
      list = Parser.const_get(arr.upcase)
      list.each_with_object({}).with_index { |(key, res), index| res[key] = fields[index + 1] }
    end
  end
end

def collect_stats_from_user(report, user, &block)
  user_key = "#{user[:attributes]['first_name']} #{user[:attributes]['last_name']}"
  report['usersStats'][user_key] ||= {}
  report['usersStats'][user_key] = report['usersStats'][user_key].merge(block.call(user))
end

def count_uniq_browsers(sessions)
  sessions.each_with_object([]) do |session, unique_browser|
    unique_browser.push(session['browser']) unless unique_browser.include? session['browser']
  end.count
end

def read_file(name)
  users = []
  sessions = []
  parser = Parser.new

  File.foreach(name) do |line|
    cols = line.split(',')
    users.push(parser.parse_user_fields(line)) if cols[0] == 'user'
    sessions.push(parser.parse_session_fields(line)) if cols[0] == 'session'
  end

  [users, sessions]
end

def work
  return unless File.file? 'data.txt'

  users, sessions = read_file 'data.txt'

  report = {}
  report['totalUsers'] = users.count
  report['uniqueBrowsersCount'] = count_uniq_browsers(sessions)
  report['totalSessions'] = sessions.count
  report['allBrowsers'] = sessions.map { |s| s['browser'].upcase }.sort.uniq.join(',')
  report['usersStats'] = {}

  users.each do |user|
    user_sessions = sessions.select { |session| session['user_id'] == user['id'] }
    collect_stats_from_user(report, { attributes: user, sessions: user_sessions }) do |u|
      user_time = u[:sessions].map { |s| s['time'].to_i }
      user_browsers = u[:sessions].map { |s| s['browser'].upcase }
      {
        'sessionsCount' => u[:sessions].count,
        'totalTime' => "#{user_time.sum} min.",
        'longestSession' => "#{user_time.max} min.",
        'browsers' => user_browsers.sort.join(', '),
        # Use IE?
        'usedIE' => user_browsers.any? { |b| b =~ /INTERNET EXPLORER/ },
        # Always only Chrome?
        'alwaysUsedChrome' => user_browsers.all? { |b| b =~ /CHROME/ },
        # Sessions dates separate by comma, in reverse order, iso8601
        'dates' => u[:sessions].map { |s| Date.parse(s['date']).iso8601 }.sort_by.reverse!
      }
    end
  end
  File.write('result.json', "#{report.to_json}\n")
end

class TestMe < Minitest::Test
  def setup
    File.write('result.json', '')
    File.write('data.txt',
               'user,0,Leida,Cira,0
session,0,0,Safari 29,87,2016-10-23
session,0,1,Firefox 12,118,2017-02-27
session,0,2,Internet Explorer 28,31,2017-03-28
session,0,3,Internet Explorer 28,109,2016-09-15
session,0,4,Safari 39,104,2017-09-27
session,0,5,Internet Explorer 35,6,2016-09-01
user,1,Palmer,Katrina,65
session,1,0,Safari 17,12,2016-10-21
session,1,1,Firefox 32,3,2016-12-20
session,1,2,Chrome 6,59,2016-11-11
session,1,3,Internet Explorer 10,28,2017-04-29
session,1,4,Chrome 13,116,2016-12-28
user,2,Gregory,Santos,86
session,2,0,Chrome 35,6,2018-09-21
session,2,1,Safari 49,85,2017-05-22
session,2,2,Firefox 47,17,2018-02-02
session,2,3,Chrome 20,84,2016-11-25
')
  end

  def test_result
    work
    expected_result = '{"totalUsers":3,"uniqueBrowsersCount":14,"totalSessions":15,"allBrowsers":"CHROME 13,CHROME 20,CHROME 35,CHROME 6,FIREFOX 12,FIREFOX 32,FIREFOX 47,INTERNET EXPLORER 10,INTERNET EXPLORER 28,INTERNET EXPLORER 35,SAFARI 17,SAFARI 29,SAFARI 39,SAFARI 49","usersStats":{"Leida Cira":{"sessionsCount":6,"totalTime":"455 min.","longestSession":"118 min.","browsers":"FIREFOX 12, INTERNET EXPLORER 28, INTERNET EXPLORER 28, INTERNET EXPLORER 35, SAFARI 29, SAFARI 39","usedIE":true,"alwaysUsedChrome":false,"dates":["2017-09-27","2017-03-28","2017-02-27","2016-10-23","2016-09-15","2016-09-01"]},"Palmer Katrina":{"sessionsCount":5,"totalTime":"218 min.","longestSession":"116 min.","browsers":"CHROME 13, CHROME 6, FIREFOX 32, INTERNET EXPLORER 10, SAFARI 17","usedIE":true,"alwaysUsedChrome":false,"dates":["2017-04-29","2016-12-28","2016-12-20","2016-11-11","2016-10-21"]},"Gregory Santos":{"sessionsCount":4,"totalTime":"192 min.","longestSession":"85 min.","browsers":"CHROME 20, CHROME 35, FIREFOX 47, SAFARI 49","usedIE":false,"alwaysUsedChrome":false,"dates":["2018-09-21","2018-02-02","2017-05-22","2016-11-25"]}}}' + "\n"
    assert_equal expected_result, File.read('result.json')
  end
end
