require 'rack'
require './app'
require './websocket_backend'

Faye::WebSocket.load_adapter('thin')
use WebsocketBackend
run App
