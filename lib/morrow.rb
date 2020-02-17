require 'eventmachine'
require 'rack'
require 'yaml'
require 'find'
require 'benchmark'

module Morrow; end
require_relative 'morrow/version'
require_relative 'morrow/logging'

# Morrow MUD server
#
# Example usage:
#
#   # start the server, telnet on port 5000, http on port 8080
#   Morrow.run
#
#   # start the server, telnet on port 6000, no web server
#   Morrow.run(telnet_port: 6000)
#
#   # Complex invocation
#   Morrow.run do |c|
#     c.env = :production   # override APP_ENV environment variable
#     c.host = '0.0.0.0'
#     c.port = 1234
#     c.web_port = 8080
#   end
#
module Morrow
  extend Logging

  class Error < StandardError; end
  class UnknownEntity < Error; end

  @exceptions = []
  @views = {}

  class << self

    # List of exceptions that have occurred in ths system.  When run in
    # development environment, Pry.rescued() can be used to debug these
    # exceptions.
    attr_reader :exceptions, :em, :update_start_time

    # Get the server configuration.
    def config
      @config ||= Configuration.new
    end

    # Load the world.
    #
    # **NOTE** This is automatically called from Morrow#run; it's just exposed
    # publicly as a convenience for debugging & testing.
    def load_world
      raise Error, 'World has already been loaded!' if @em && !@em.empty?
      reset! unless @em

      load_path(File.expand_path('../../data/morrow-base', __FILE__)) if
          config.load_morrow_base
      load_path(config.world_dir)
      info 'world has been loaded'
    end

    # This will wipe the world entirely clean.  Used for testing
    def reset!
      @em = EntityManager.new(components: config.components)
    end

    # Run the server.  More advanced configuration can be done using the block
    # syntax.
    #
    # Parameters:
    # * +host+ host to bind to; default: '0.0.0.0', 'localhost' in development
    # * +telnet_port+ port to listen for telnet connections; default: 5000
    # * +http_port+ port to listen for http connections; default: 8080
    #
    def run(host: nil, telnet_port: 5000, http_port: 8080)

      # configure the server
      config.host = host if host
      config.telnet_port = telnet_port
      config.http_port = http_port

      yield config if block_given?

      info 'Loading the world'
      load_world
      init_views

      info 'Morrow starting in %s mode' % config.env
      WebServer::Backend.set :environment, config.env

      # If we're running in development mode,
      #   * pull in and start running Pry on stdin
      #   * enable pry-rescue
      #   * allow reloading of the web server code
      #   * start a thread dedicated to running Pry
      if config.development?
        require 'pry'
        require 'pry-rescue'

        Pry.enable_rescuing!
        start_reloader
      end

      # Run everything in the EventMachine loop.
      EventMachine::run do
        EventMachine.error_handler { |ex| log_exception(ex) }

        begin
          # Set up a periodic timer to update the world every quarter second.
          EventMachine::PeriodicTimer.new(0.25) { Morrow.update }

          Rack::Handler.get('thin').run(WebServer.app,
              Host: config.host, Port: config.http_port, signals: false) if
                  config.http_port

          TelnetServer.start(config.host, config.telnet_port)
        rescue Exception => ex
          log_exception(ex)
        end
      end
    end

    # Run all the registered systems
    def update
      @update_start_time = Time.now

      @config.systems.each do |system|
        unless view = @views[system]
          @config.systems.delete(system)

          error <<~ERROR.gsub(/\n/, ' ').chomp
            no view found for #{system}; removed.  This may have occurred if
            the system was added to Morrow.config.systems after Morrow.run was
            called; runtime addition of systems is not supported.
          ERROR

          next
        end

        bm = Benchmark.measure do
          view.each { |a| system.update(*a) }
        end
        system.append_system_perf(bm)

      end

      em.flush_updates
    end

    private

    # Start a thread dedicated to reloading resources as they change on disk.
    # For the moment, this only does the web server.
    def start_reloader
      Thread.new do
        base = File.dirname(__FILE__)
        path = File.join(base, 'morrow/web_server/backend.rb')
        mtime = File.mtime(path)

        loop do
          if (t = File.mtime(path)) > mtime
            debug('web server modified; attempting to reload ...')
            mtime = t

            begin
              # We do this in stages; try to load the file, and if it's
              # successful, reset the web server, then load it again.  The
              # reset is necessary, otherwise the routes from the previous web
              # server definition take precidence.
              load(path)
              WebServer::Backend.reset!
              load(path)
              info('web server reloaded')
            rescue Exception => ex
              error('failed to reload web server')
              log_exception(ex)
            end
          end

          sleep 5
        end
      end
    end

    # Load entities from a specific path.
    def load_path(base)
      loader = Loader.new
      Find.find(base)
          .select { |path| File.basename(path) =~ /^[^.].*\.yml$/ }
          .sort
          .each do |path|
        info "loading #{path} ..."
        loader.load_file(path)
      end
      loader.finalize
    end

    # For all configured systems, let's create the required views.
    def init_views
      @views = @config.systems.inject({}) do |o,system|
        view_args = system.view

        # Add { excl: :template } to the args unless the system already put
        # :template somewhere in the args.
        unless view_args.values.flatten.include?(:template)
          view_args[:excl] ||= []
          view_args[:excl] << :template
        end

        o[system] = @em.get_view(**view_args)
        o
      end
    end
  end
end

require_relative 'morrow/component'
require_relative 'morrow/components'
require_relative 'morrow/helpers'
require_relative 'morrow/system'
require_relative 'morrow/telnet_server'
require_relative 'morrow/configuration'
require_relative 'morrow/command'
require_relative 'morrow/web_server'
require_relative 'morrow/entity_manager'
require_relative 'morrow/loader'
require_relative 'morrow/script'

# dynamically load all the commands
Dir.glob(File.expand_path('../morrow/command/**.rb', __FILE__)).each do |file|
  require file
end