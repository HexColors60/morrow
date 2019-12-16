module Command::ActObj
  extend World::Helpers

  class << self
    def open_entity(actor, arg=nil)
      return "Open what?\n" if arg.nil? || arg.empty?

      target = match_keyword(arg, closable_entities(actor)) or
          return "Unable to find anything named '#{arg}' to open."
      
      return "It is locked." if target.get(:closable, :locked)
      return "It is already open." if !target.get(:closable, :closed)

      target.set(:closable, closed: false)

      # XXX need to do the same to the door on the other side; both should be
      # closable
      return "You open #{target.get(:viewable, :short)}"
    end

    def close_entity(actor, arg=nil)
      return "Close what?\n" if arg.nil? || arg.empty?

      target = match_keyword(arg, closable_entities(actor)) or
          return "Unable to find anything named '#{arg}' to close."
      
      return "It is already closed." if target.get(:closable, :closed)

      target.set(:closable, closed: true)
      return "You close #{target.get(:viewable, :short)}"
    end

    def closable_entities(actor)
      room = actor.get(:location, :ref) or fault "actor has no location", actor
      room = room.entity
      [ room.get(:exits, :list),
        visible_contents(actor: actor, cont: room),
        visible_contents(actor: actor, cont: actor) ]
          .flatten
          .compact
          .map(&:entity)
          .select { |e| e.has_component?(:closable) }
    end
  end

  # Register the commands
  Command.register('open', method: method(:open_entity))
  Command.register('close', method: method(:close_entity))
end
