#! /usr/bin/ruby
# A script to fetch my steps from Oura and update my beeminder step goal
# If run with no arguments it fetches the last 5 days from Oura, and updates
# beeminder datapoints.
# Alternately can take one arg -- a date in YYYY-MM-DD format -- and will
# fetch the Oura steps for that specific day (so i can backdate stuff or
# if i just want to verify a specific date 

# TODO: probably there are timezone issues here?

require 'httparty'

OURL= "https://api.ouraring.com/v2/"
BURL= "https://www.beeminder.com/api/v1/"
SID = 24*60*60
DAYS = 5 # number of days to fetch


now = Time.now

if ARGV.length > 0
  start = ARGV[0]
  fin = start
  # whether to actually update
  up = ARGV[1] == "up"
else
  start = (now - SID*DAYS).strftime('%F')
  fin = (now + SID).strftime('%F')
  up = true
end

params = {
  start_date: start, 
  end_date: fin 
} 

headers = {"Authorization": "Bearer #{OPAT}"}
oresp = HTTParty.get(OURL+"usercollection/daily_activity", headers: headers, query: params).parsed_response
#sleep = HTTParty.get(OURL+"sleep", headers: headers, query: params).parsed_response["sleep"]

activity = oresp["data"].map{|act|
  [Date.parse(act["day"]), act["steps"]]
}

if !up
  puts "OURA SAYS:"
  activity.each{|act|
    puts act.join(": ")
  }
  exit
end

stepurl = BURL+"users/b/goals/42steps"
minstep = BURL+"users/b/goals/42steps-min"
data = HTTParty.get(stepurl+"/datapoints.json", query: {auth_token: BPAT, count: DAYS+1, sort: "daystamp"}).parsed_response

#data.map{|dat| puts "#{dat["daystamp"]}: #{dat["value"]}"}

activity.each {|date,steps|
  datapt = data.select{|dat| dat["daystamp"] == date.strftime('%Y%m%d')}.first
  if datapt == nil
    # add a datapoint
    puts "no datapoint!"
    resp = HTTParty.post(stepurl + "/datapoints.json", body: {
      auth_token: BPAT, 
      value: steps, 
      daystamp: date.strftime('%Y%m%d'), 
      comment: "From Oura. Entered at #{Time.now.iso8601}"
    })
    puts resp.parsed_response
  elsif datapt && datapt["value"] < steps
    # ok, but there is a datapoint and it has less steps than oura 
    puts "found datapoint #{datapt["value"]}" 
    resp = HTTParty.put(stepurl + "/datapoints/#{datapt["id"]}.json", body: {
      auth_token: BPAT,
      value: steps,
      daystamp: date.strftime('%Y%m%d'),
      comment: "#{datapt["comment"]}; Up:#{Time.now.strftime('%H:%M')}"
    })
    puts resp.parsed_response
  else
    puts "#{date} #{steps}"
  end
}

# okay, let's do a second pass to update the min-goal, which has different rules
# this only looks at today's data
mingol = HTTParty.get(minstep+".json", query: {auth_token: BPAT}).parsed_response
rcur = mingol["currate"]
tddate,tdsteps = activity.select{|date,steps| date.strftime('%F') == now.strftime('%F')}.first

# enter it to the minstep goal; 0 if < min, else actual value
resp = HTTParty.post(minstep + "/datapoints.json", body: {
  auth_token: BPAT, 
  value: (tdsteps >= rcur ? tdsteps : 0),
  daystamp: tddate.strftime('%Y%m%d'),
  requestid: "oura_#{tddate}",
  comment: "MIN (rcur): #{rcur}"
})
puts "entering data: #{tddate}: #{rcur}<>#{tdsteps}"
puts "resp code: #{resp.code}"

