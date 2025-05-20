require 'sinatra'
require 'faye/websocket'
require 'json'
require 'thread'
require 'set'
require 'securerandom'

enable :sessions
set :public_folder, File.dirname(__FILE__) + '/public'

$connections = []
$history = []
$throttle = {}
$mutex = Mutex.new
$banned = File.read('bannedWords.txt').split("\n").map(&:strip)
$reactions = {} # message_id => {likes: Set, dislikes: Set, pooped: bool}

# Adjective-Animal anonymized name generator
ADJECTIVES = %w[Brave Clever Calm Swift Silent Lucky Happy Fierce Bright Cool Quiet Noble]
ANIMALS = %w[Fox Tiger Panda Owl Wolf Cat Bear Hawk Falcon Whale Lion Cheetah Rabbit Koala]
$anon_names = {} # email => anon name

helpers do
  def logged_in?
    session[:email] && session[:email].end_with?('@edtools.psd401.net')
  end

  def anon_name_for(email)
    $anon_names[email] ||= begin
      "#{ADJECTIVES.sample}#{ANIMALS.sample}"
    end
  end
end

get '/' do
  redirect '/login' unless logged_in?
  send_file File.join(settings.public_folder, 'index.html')
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
        <h2>Please login with your email</h2>
        <input type="email" name="email" placeholder="you@stuff.thing" required />
        <button type="submit">Enter</button>
      </form>
    </body>
    </html>
  HTML
end

def generate_username
  adjectives = ['quick', 'lazy', 'bright', 'shiny', 'silent']
  animals = ['fox', 'dog', 'cat', 'elephant', 'eagle']
  "#{adjectives.sample}-#{animals.sample}"
end

post '/login' do
  email = params[:email].to_s.strip.downcase
  if email.end_with?('@edtools.psd401.net')
    session[:email] = email
    session[:username] = generate_username  # Store the username in the session
    redirect "/"
  else
    halt 403, "Uh oh, looks like you do not have access to this web service. :("
  end
end

get '/chrome' do
  send_file File.join(settings.public_folder, 'chroma.html')
end

get '/ws' do
  halt 403 unless logged_in?

  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    uid = SecureRandom.hex(8)
    email = session[:email]
    anon_name = anon_name_for(email)

    $mutex.synchronize do
      $connections << ws
      $throttle[uid] = []
    end

    ws.on :open do |_evt|
      ws.send({ type: 'active_users', count: $connections.size }.to_json)
      # Send history with message ids and reaction counts
      history_with_ids = $history.map do |msg|
        msg = msg.dup
        msg[:id] ||= generate_message_id(msg)
        react = $reactions[msg[:id]] || { likes: Set.new, dislikes: Set.new, pooped: false }
        msg[:likes] = react[:likes].size
        msg[:dislikes] = react[:dislikes].size
        msg[:pooped] = react[:pooped]
        msg
      end
      ws.send({ type: 'history', messages: history_with_ids }.to_json)
    end

    ws.on :message do |packet|
      begin
        payload = JSON.parse(packet.data)
        now = Time.now.to_i

        if payload['type'] == 'reaction'
          msg_id = payload['id']
          reaction = payload['reaction']
          $mutex.synchronize do
            $reactions[msg_id] ||= { likes: Set.new, dislikes: Set.new, pooped: false }
            react = $reactions[msg_id]
            # Use uid to prevent multiple likes/dislikes from same user
            if reaction == 'like'
              react[:likes] << uid
              react[:dislikes].delete(uid)
            elsif reaction == 'dislike'
              react[:dislikes] << uid
              react[:likes].delete(uid)
              if react[:dislikes].size >= 2
                react[:pooped] = true
                # Find and update message in $history
                $history.each do |msg|
                  if (msg[:id] || generate_message_id(msg)) == msg_id
                    msg[:pooped] = true
                    msg[:text] = 'pooped to death'
                    msg.delete(:image)
                  end
                end
              end
            end
            # Broadcast reaction update
            $connections.each do |conn|
              conn.send({
                type: 'reaction_update',
                id: msg_id,
                likes: react[:likes].size,
                dislikes: react[:dislikes].size,
                pooped: react[:pooped]
              }.to_json)
            end
          end
          next
        end

        $mutex.synchronize do
          recent = $throttle[uid].select { |t| now - t < 10 }
          if recent.size >= 2
            ws.send({ type: 'rate_limit', text: 'You are sending messages too fast.' }.to_json)
            next
          end
          $throttle[uid] = recent << now
        end

        raw_msg = payload['text'].to_s.strip[0..500]
        maybe_image = payload['image'].to_s if payload['image']

        clean_msg = raw_msg.gsub(/\b\w+\b/) do |w|
          $banned.include?(w.downcase) ? '*' * w.length : w
        end

        msg_to_broadcast = {
          username: anon_name,
          text: clean_msg.empty? ? nil : clean_msg,
          image: maybe_image,
          timestamp: Time.now.strftime('%H:%M')
        }.compact

        # Assign a message id for reactions
        msg_to_broadcast[:id] = generate_message_id(msg_to_broadcast)
        $mutex.synchronize do
          $history << msg_to_broadcast
          $history.shift while $history.size > 30
          $reactions[msg_to_broadcast[:id]] ||= { likes: Set.new, dislikes: Set.new, pooped: false }

          $connections.each do |conn|
            conn.send(msg_to_broadcast.to_json)
          end
        end
      rescue => e
        puts "Error processing message: #{e}"
      end
    end

    ws.on :close do |_evt|
      $mutex.synchronize do
        $connections.delete(ws)
      end
    end

    ws.rack_response
  else
    halt 404, "WebSocket not allowed"
  end
end

# Helper to generate a message id (should match frontend)
def generate_message_id(msg)
  [
    msg[:timestamp] || '',
    msg[:username] || '',
    msg[:text] || '',
    (msg[:image] ? msg[:image][0..10] : '')
  ].join('_')
end

get '/chroma' do
  redirect '/chrome'
end
