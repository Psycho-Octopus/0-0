# server.rb
require 'sinatra'
require 'faye/websocket'
require 'json'
require 'thread'
require 'set'
require 'securerandom'

set :public_folder, File.dirname(__FILE__) + '/public'

# List of boards, add or remove board names from this array as needed
BOARDS = ['all', 'chat', 'memes', 'news']

# Structure: { board_name => { connections: [], history: [], rate_limits: {} } }
boards = Hash.new { |h, k| h[k] = { connections: [], history: [], rate_limits: {} } }
mutex = Mutex.new

# Read banned words from bannedWords.txt into an array
banned_words = File.read('bannedWords.txt').split("\n").map(&:strip)

# Default redirect to the first board (e.g., /b)
get '/' do
  redirect "/#{BOARDS.first}"
end

# Serve index.html for any board path (e.g., /b, /soy, /a)
get '/:board' do |board|
  if BOARDS.include?(board)
    send_file File.join(settings.public_folder, 'index.html')
  else
    halt 404, "Board not found"
  end
end

# WebSocket endpoint for a specific board
get '/ws/:board' do |board|
  if BOARDS.include?(board) && Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    client_id = SecureRandom.hex(8)

    mutex.synchronize do
      boards[board][:connections] << ws
      boards[board][:rate_limits][client_id] = []
    end

    ws.on :open do |_|
      ws.send(boards[board][:history].to_json)
    end

    ws.on :message do |event|
      begin
        data = JSON.parse(event.data)
        timestamp = Time.now.to_i

        mutex.synchronize do
          recent = boards[board][:rate_limits][client_id].select { |t| timestamp - t < 10 }
          if recent.size >= 5
            ws.send({ text: 'You are sending messages too fast. Stop spamming.', type: 'rate_limit' }.to_json)
            next
          end
          boards[board][:rate_limits][client_id] = recent << timestamp
        end

        text = data['text'].to_s.strip[0..500]
        image = data['image'].to_s if data['image']

        # Censor the text based on the banned words
        censored_text = text.split(' ').map { |word| banned_words.include?(word.downcase) ? '*' * word.length : word }.join(' ')

        message = {
          text: censored_text.empty? ? nil : censored_text,
          image: image,
          timestamp: Time.now.strftime('%H:%M')
        }.compact

        mutex.synchronize do
          boards[board][:history] << message
          boards[board][:history].shift if boards[board][:history].size > 30
          boards[board][:connections].each { |conn| conn.send(message.to_json) }
        end
      rescue => e
        puts "Error: #{e.message}"
      end
    end

    ws.on :close do |_|
      mutex.synchronize do
        boards[board][:connections].delete(ws)
        boards[board][:rate_limits].delete(client_id)
      end
    end

    ws.rack_response
  else
    halt 400, 'WebSocket only'
  end
end
