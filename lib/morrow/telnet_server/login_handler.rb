class Morrow::TelnetServer::LoginHandler
  include Morrow::TelnetServer::InputHandler
  include Morrow::Helpers

  def initialize(conn)
    @char = create_entity(base: 'morrow:player')

    @conn = get_component!(@char, :connection)
    @conn.conn = conn

    @input = get_component!(@char, :input).queue = Thread::Queue.new

    @config = get_component!(@char, :player_config)
    @config.color = true

    move_entity(entity: @char, dest: 'morrow:room/void')
    input_line('look')

    remove_component(@char, :view_exempt)
  end

  def input_line(line)
    @conn.last_recv = Time.now
    @input.push(line)
    nil
  end

  def color?
    !!@config.color
  end
end
