require 'sinatra'
require 'faye/websocket'
require 'json'
require 'thread'
require 'set'
require 'securerandom'

enable :sessions

set :public_folder, File.dirname(__FILE__) + '/public'

#boards are right here, dont overdo it
BOARDS = ['all', 'chat', 'memes', 'news', 'free']
$board_state = Hash.new { |h, k| h[k] = { conns: [], history: [], throttle: {} } }
$mutex = Mutex.new
$banned = File.read('bannedWords.txt').split("\n").map(&:strip)

helpers do
  def logged_in?
    session[:email] && session[:email].end_with?('@edtools.psd401.net')
  end
end

get '/' do
  redirect '/login' unless logged_in?
  redirect "/#{BOARDS.first}"
end

get '/login' do
  <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Login</title>
      <style>
        body { background: #111; color: #eee; font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; }
        form { background: #222; padding: 2rem; border-radius: 10px; }
        input { padding: 0.5rem; width: 100%; margin-top: 1rem; }
        button { margin-top: 1rem; padding: 0.5rem 1rem; }
      </style>
    </head>
    <body>
      <form method="POST" action="/login">
        <h2>Please login or create an account</h2>
        <input type="email" name="email" placeholder="you@stuff.thing" required />
        <button type="submit">Enter</button>
      </form>
    </body>
    </html>
  HTML
end

post '/login' do
  email = params[:email].to_s.strip.downcase
  if email.end_with?('@edtools.psd401.net')
    session[:email] = email

    emails = File.exist?('emails.txt') ? File.read('emails.txt').split("\n") : []
    unless emails.include?(email)
      File.open('emails.txt', 'a') { |file| file.puts(email) }
    end

    redirect "/#{BOARDS.first}"
  else
    halt 403, "Uh oh, looks like you do not have access to this web service. :("
  end
end


get '/:board' do |board_name|
  redirect '/login' unless logged_in?
  if BOARDS.include?(board_name)
    send_file File.join(settings.public_folder, 'index.html')
  else
    halt 404, "Board not found"
  end
end

get '/ws/:board' do |board_name|
  halt 403 unless logged_in?

  if BOARDS.include?(board_name) && Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    uid = SecureRandom.hex(8)

    $mutex.synchronize do
      $board_state[board_name][:conns] << ws
      $board_state[board_name][:throttle][uid] = []
    end

    ws.on :open do |_evt|
      ws.send({ type: 'active_users', count: $board_state[board_name][:conns].size }.to_json)
      ws.send({ type: 'history', messages: $board_state[board_name][:history] }.to_json)
    end

    ws.on :message do |packet|
      begin
        payload = JSON.parse(packet.data)
        now = Time.now.to_i

        $mutex.synchronize do
          recent = $board_state[board_name][:throttle][uid].select { |t| now - t < 10 }
          if recent.size >= 5
            ws.send({ type: 'rate_limit', text: 'You are sending messages too fast.' }.to_json)
            next
          end
          $board_state[board_name][:throttle][uid] = recent << now
        end

        raw_msg = payload['text'].to_s.strip[0..500]
        maybe_image = payload['image'].to_s if payload['image']

        clean_msg = raw_msg.gsub(/\b\w+\b/) do |w|
          $banned.include?(w.downcase) ? '*' * w.length : w
        end

        msg_to_broadcast = {
          text: clean_msg.empty? ? nil : clean_msg,
          image: maybe_image,
          timestamp: Time.now.strftime('%H:%M')
        }.compact

        $mutex.synchronize do
          $board_state[board_name][:history] << msg_to_broadcast
          $board_state[board_name][:history].shift while $board_state[board_name][:history].size > 30

          $board_state[board_name][:conns].each do |conn|
            conn.send(msg_to_broadcast.to_json)
          end
        end
      rescue => e
        puts "Error processing message: #{e}"
      end
    end

    ws.on :close do |_evt|
      $mutex.synchronize do
        $board_state[board_name][:conns].delete(ws)
      end
    end

    ws.rack_response
  else
    halt 404, "WebSocket not allowed"
  end
end

get '/chroma'
  send_file File.join(settings.public_folder, 'chroma.html'
    end
end
