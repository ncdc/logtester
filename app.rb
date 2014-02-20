require 'sinatra/base'
require 'haml'

class App < Sinatra::Base
  set :environment, :development
  get "/" do
    haml :index
  end
end
