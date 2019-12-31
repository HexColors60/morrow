module System::Teleport
  extend System::Base

  class << self
    def view
      @view ||= World.get_view(all: :teleport)
    end

    def update(entity, teleport)
      if !teleport.dest or !teleport.time
        error("invalid teleport (#{teleport.to_h}) on #{entity}; removing")
        remove_component(entity, teleport)
        return
      end

      return if teleport.time > Time.now

      send_to_char(char: entity, buf: teleport.message + "\n") if
          teleport.message

      move_entity(entity: entity, dest: teleport.dest, look: teleport.look)
    end
  end
end
