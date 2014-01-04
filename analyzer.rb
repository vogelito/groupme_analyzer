#!/usr/bin/ruby

require 'json'

# you need to set these 2 vars
$access_token = "" # obtain this by logging in to groupme.com and observe some HTTP headers
$group_id = "" # set to whatever group is relevant to you

# no need to adjust these
$before_postfix = "?before_id="
$users = Hash.new # will be a user_id to Person.class hash
$total_text = 0
$processed = 0

class Person
  attr_accessor :name, :user_id, :posts, :likes, :attachments, :total_text

  def initialize
    @name = nil
    @user_id = nil
    @posts = 0
    @likes = 0
    @attachments = 0
    @total_text = 0
  end
end

def safe_time_string
  return "#{Time.now.to_i}_" + (0...8).map { (65 + rand(26)).chr }.join
end

$safe_dir = "output/"+safe_time_string

def get_messages(last_id = nil, tries = 0)
  if tries > 5
    puts "# Unable to process request for last_id #{last_id}. Terminating...."
    return nil
  end
  postfix = ""
  postfix = $before_postfix + last_id if last_id != nil

  cmd = `curl 'https://api.groupme.com/v3/groups/#{$group_id}/messages#{postfix}' -H 'Origin: https://app.groupme.com' -H 'Accept-Encoding: gzip,deflate,sdch' -H 'Host: api.groupme.com' -H 'Accept-Language: en-US,en;q=0.8' -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/31.0.1650.63 Safari/537.36' -H 'Accept: application/json, text/plain, */*' -H 'Referer: https://app.groupme.com/chats' -H 'Connection: keep-alive' -H 'X-Access-Token: #{$access_token}' --compressed -s`

  begin
    Dir.mkdir($safe_dir) if !Dir.exists?($safe_dir)
    f = File.open("#{$safe_dir}/#{safe_time_string}.json", "w")
    f.write(cmd)
    f.close
  rescue
    puts "# unable to write file, exiting"
    Process.exit
  end

  begin
    resp = JSON.parse(cmd)
    return resp
  rescue JSON::ParserError
    puts "# Unable to parse curl response. Retrying #{tries+1}."
    puts "# Response was: #{cmd}"
    return get_messages(last_id, tries+1)
  end
end

def process_message(msg)
  last_id = nil
  puts "# Total: " + msg["response"]["count"].to_s
  puts "# Processed: " + $processed.to_s
  messages = msg["response"]["messages"]
  messages.each do |m|
    $processed += 1
    last_id = m["id"]
    user_id = m["user_id"]
    p = $users[user_id]
    if p == nil
      p = Person.new
      $users[user_id] = p
    end
    p.posts += 1
    p.name = m["name"]
    p.user_id = user_id
    p.attachments += 1 if m["attachments"].length > 0

    # process text size
    text = m["text"]
    text_size = 0
    text_size = text.length if text != nil
    $total_text += text_size
    p.total_text += text_size

    # process likes
    likes = m["favorited_by"]
    likes.each do |l|
      p = $users[l]
      if p == nil
        p = Person.new
        $users[l] = p
      end
      p.user_id = l
      p.likes += 1
    end
  end
  return last_id
end

# get first set of messages
resp = get_messages
# now get all the next set of messages
while true
  break if resp == nil
  last_id = process_message(resp)
  break if last_id == nil
  resp = get_messages(last_id)
end

puts "Name|User_id|Posts|Likes|Attachments|Text"
$users.each do |key, value|
  puts "#{value.name}|#{value.user_id}|#{value.posts}|#{value.likes}|#{value.attachments}|#{value.total_text}"
end
puts "Total_Text:#{$total_text}"
