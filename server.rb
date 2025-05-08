# server.rb
require 'sinatra'
require 'faye/websocket'
require 'json'
require 'thread'
require 'set'

data = {
  name: "my_project",
  version: "1.0.0",
  description: "This is a sample JSON config",
  dependencies: {
    "sinatra" => "~> 2.1"
  }
}

File.open("project.json", "w") do |f|
  f.write(JSON.pretty_generate(data))
end

set :public_folder, File.dirname(__FILE__) + '/public'
connections = []
message_history = []
rate_limits = {}

mutex = Mutex.new

# Serve the index.html directly
get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end

# WebSocket endpoint
get '/ws' do
  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    client_id = SecureRandom.hex(8)

    mutex.synchronize do
      connections << ws
      rate_limits[client_id] = []
    end

    # Send message history on connect
    ws.on :open do |_|
      ws.send(message_history.to_json)
    end

    ws.on :message do |event|
      begin
        data = JSON.parse(event.data)
        timestamp = Time.now.to_i
        messages = rate_limits[client_id].select { |t| timestamp - t < 10 }

        if messages.size >= 5
          ws.send({ text: 'You are sending messages too fast. Stop spamming.', type: 'rate_limit' }.to_json)
          next
        end

        rate_limits[client_id] = messages << timestamp

        # Sanitize input (lightweight)
        text = data['text'].to_s.strip[0..500]
        image = data['image'].to_s if data['image']

        message = {
          text: text.empty? ? nil : text,
          image: image,
          timestamp: Time.now.strftime('%H:%M')
        }.compact

        mutex.synchronize do
          message_history << message
          message_history.shift if message_history.size > 30
        end

        connections.each { |conn| conn.send(message.to_json) }
      rescue => e
        puts "Error: #{e.message}"
      end
    end

    ws.on :close do |_|
      mutex.synchronize do
        connections.delete(ws)
        rate_limits.delete(client_id)
      end
      ws = nil
    end

    # Return async Rack response
    ws.rack_response
  else
    halt 400, 'WebSocket only'
  end
end
