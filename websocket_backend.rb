require 'faye/websocket'
require './driver'

class WebsocketBackend
  def initialize(app)
    @app = app
    @clients = []
    @channel = EventMachine::Channel.new
    @sid = @channel.subscribe do |msg|
      @clients.each {|ws| ws.send(msg)}
    end
  end

  def call(env)
    if Faye::WebSocket.websocket?(env)
      ws = Faye::WebSocket.new(env, nil, {})
      ws.on :open do |event|
        @clients << ws
      end

      ws.on :message do |event|
        params = Rack::Utils.parse_query(event.data)
        Driver.new(channel: @channel,
                   message_length: params['messageLength'].to_i,
                   message_rate: params['messageRate'].to_i,
                   queue_size: params['queueDepth'].to_i,
                   test_length: params['testLength'].to_i,
                   input_buffer_size: params['inputBufferSize'].to_i)

      end

      ws.on :close do |event|
        @clients.delete(ws)
        ws = nil
      end

      ws.rack_response
    else
      @app.call(env)
    end
  end
end
