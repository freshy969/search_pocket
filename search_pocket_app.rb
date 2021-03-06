require 'sinatra/base'
require 'haml'
require 'sinatra/config_file'
require 'omniauth'
require 'omniauth-pocket'
require 'sequel'
require 'riddle'

class SearchPocketApp < Sinatra::Base
  # version number
  VERSION = '0.0.1'

  # application config file
  register Sinatra::ConfigFile
  config_file 'config/config.yml'

  enable :sessions
  enable :logging
  set :views, ['views/layouts', 'views/pages', 'views/partials']
  set :haml, {:format => :html5, :layout => :layout }

  # include helpers
  Dir["./app/helpers/*.rb"].each { |file| require file }
  helpers ViewDirectoriesHelper, SessionHelper, LinkHelper
  # include models
  db = settings.db
  Sequel.connect("mysql2://#{db[:username]}:#{db[:password]}@#{db[:host]}:#{db[:port]}/#{db[:database]}")
  Dir["./app/models/*.rb"].each { |file| require file }

  # use the omniauth-pocket middleware
  pocket = settings.pocket
  use OmniAuth::Builder do
    provider :pocket, pocket[:client_id], pocket[:client_secret]
  end

  before '/search' do
    if current_user.nil?
      redirect to('/')
    end
  end

  # routers

  get '/' do
    if signed_in? 
      user = current_user
      message = nil
      if user.since.nil? || Link.where(user_id: user.id, status: 2).empty?
        message = 'Your links will be ready for search in several minutes.'
      end
      haml :search, :locals => {message: message}
    else # user not logged in
      haml :index, :layout => :home
    end
  end

  get '/auth/:provider/callback' do
    uid = env['omniauth.auth'].uid
    token = env['omniauth.auth'].credentials.token   
    sign_in(uid)
    user = User[:name => uid]
    if user.nil? # it is a new user
      user = User.create({:name => uid, :token => token, :register_at => DateTime.now,
                          :login_at => DateTime.now})
      # spawn a process to retrieve and parse links
      logger.info "spawn a retrieval process for user #{user.name}"
      e = ENV['RACK_ENV'] || 'development'
      logger.info "Environment: #{e}"
      pid = Process.spawn("script/bootstrap.rb -c config/config.yml -s config/sphinx.conf -e #{e} -u #{user.name} -b",
                   :chdir => File.expand_path(File.dirname(__FILE__)), :err => :out)
      Process.detach(pid)
    else
      user.set(login_at: DateTime.now)
      user.set(token: token) unless user.token.eql?(token)
      user.save
    end
    redirect to('/')
  end

  get '/auth/failure' do
    logger.error "Pocket auth failed: #{params[:message]}"
    [400, haml(:error, :locals => 
               { message: "Failed because of #{params[:message]}" })]
  end

  get '/logout' do
    sign_out
    redirect to('/');
  end

  get '/search' do
    q = params[:q]
    page = (params[:p] || 1).to_i
    per_page = 10
    if q.nil? || q.empty?
      haml :search, :locals => {:message => nil}
    else
      index = 'main'
      client = Riddle::Client.new
      client.filters << Riddle::Client::Filter.new('user_id', [current_user.id])
      client.offset = (page - 1) * per_page
      client.limit = per_page
      results = client.query(q, index)
      ids = results[:matches].map { |match| match[:doc] }
      unless ids.empty?
        links = Link.where(:id => ids).all
        docs = links.map(&:content)
        excerpts = client.excerpts(:docs => docs, :index => index, :words => q)
        links.each_index do |i|
          links[i].excerpt = excerpts[i]
        end
      else
        links = []
      end
      haml :results, :locals => {:q => q, 
                                 :total => results[:total],
                                 :time => results[:time],
                                 :links => links, 
                                 :per_page => per_page, 
                                 :page => page}
    end
  end

  get '/terms' do
    haml :terms
  end

  get '/privacy' do
    haml :privacy
  end

  not_found do
    [404, haml(:error, locals: { message: "Page Not Found" })]
  end

  error do
    logger.error env['sinatra.error'].name
    [500, haml(:error, locals: { message: "Something went wrong on server"})]
  end

  # Run this application
  run! if app_file == $0
end
