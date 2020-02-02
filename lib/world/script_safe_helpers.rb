require 'forwardable'
require 'facets/string/indent'

# World::ScriptSafeHelpers
#
# This file contains helpers that are **SAFE** to use within scripts.  Every
# method added here will be exposed to scripts.  As such, be certain you're not
# implementing something that can open the server up to exploit.
#
# If you're not sure, add your helper to World::Helpers instead.
#
module World::ScriptSafeHelpers
  extend Forwardable
  def_delegators :World, :create_entity, :destroy_entity, :add_component,
      :remove_component, :get_component, :get_components, :get_component!

  # raise an exception with a message, and all manner of extra data
  #
  # Arguments:
  #   ++msg++ Message to include in the RuntimeError exception
  #   ++data++ Additional context data for the exception; ex.data
  #
  # Return: None; exception raised
  #
  def fault(msg, *data)
    ex = World::Fault.new(msg, *data)
    ex.set_backtrace(caller)
    raise(ex)
  end

  # Get the cardinal direction from the passage, or the first keyword
  def exit_name(passage)
    keywords = [ passage.get(:keywords, :words) ].flatten
    (keywords & World::CARDINAL_DIRECTIONS).first or keywords.first
  end

  # move_entity
  #
  # Move an entity into the ContainerComponent of another entity.  If the
  # entity being moved already resides within another entity's
  # ContainerComponent, first remove it from it's existing container.
  #
  # This method will also fire the following hooks in order:
  #   * <move the entity>
  #   * on_exit
  #   * on_enter
  #
  def move_entity(dest: nil, entity: nil, look: false)
    container = get_component!(dest, :container)
    location = get_component!(entity, :location)
    src = location.entity

    # I apologize, but this is gonna be ugly and may be premature optimization.
    #
    # For corporeal entities, we need to first check if the entity will fit in
    # the destination (by volume & weight), but only if the container has a
    # limit on at least one of volume or weight.  We only want to sweep through
    # the entities once, so we do all of this at once.  Thus, ugly.
    if corp = get_component(entity, :corporeal) and
        (max_vol = container.max_volume or max_weight = container.max_weight)

      vol, weight = container.contents
          .inject([corp.volume || 0, corp.weight || 0]) do |(v,w),e|
        if c = get_component(e, :corporeal)
          v += c.volume || 0
          w += c.weight || 0
        end
        [v, w]
      end

      return :full if max_vol && vol > max_vol
      return :full if max_weight && weight > max_weight
    end

    # remove the entity from any existing location
    src && get_component(src, :container)&.contents.delete(entity)
    remove_component(entity, :teleport)

    # move the entity
    location.entity = dest
    container.contents << entity

    # perform the look for the entity if it was requested
    # XXX kludge for right now
    send_to_char(char: entity, buf: Command.run(entity, 'look')) if look

    # fire on-enter hook
    container.on_enter&.call(args: { entity: entity, here: dest })

    # schedule the teleport if the dest is a teleporter
    if teleporter = get_component(dest, :teleporter)
      tele = get_component!(entity, :teleport)
      delay = teleporter.delay
      delay = rand(teleporter.delay) if delay.is_a?(Range)
      tele.time = Time.now + delay
      tele.teleporter = dest
    end

    nil
  end

  # get a/all entities from ++pool++ that have keywords that match our
  # the provided ++keyword++
  #
  # Arguments:
  #   ++buf++ String; "sword", "sharp-sword", "3.sword", "all.sword"
  #   ++pool++ Entity ids
  #
  # Parameters:
  #   ++multiple++ set to true if more than one match permitted
  #
  # Return:
  #   when multiple: Array of matching entities in ++pool++
  #   when not multiple: first entity in ++pool++ that matches
  #
  def match_keyword(buf, *pool, multiple: false)

    fault "unparsable keyword; #{buf}" unless buf =~ /^(?:(all|\d+)\.)?(.*)$/
    index = $1
    keywords = $2.split('-').uniq

    # ensure the user isn't using 'all.item' when the caller expects only a
    # single item
    raise Command::SyntaxError,
        "'#{buf}' is not a valid target for this command" if
            index == 'all' and !multiple

    pool.flatten!

    # if the user hasn't specified an index, or the caller hasn't specified
    # that they want multiple matches, do the simple find here to grab and
    # return the first match
    if index.nil? and multiple != true
      return pool.find do |entity|
        comp = get_component(entity, :keywords) or next false
        (comp.words & keywords).size == keywords.size
      end
    end

    # Anything else requires us to have the full matches list
    matches = pool.select do |entity|
      comp = get_component(entity, :keywords) or next false
      (comp.words & keywords).size == keywords.size
    end

    return matches if index.nil? or index == 'all'

    index = index.to_i - 1
    multiple ? [ matches[index] ].compact : matches[index]
  end

  # spawn_at
  #
  # Create a new instance of an entity from a base entity, and move it to dest.
  #
  # Arguments:
  #   dest: container Entity to move entity to
  #   base: base Entity to spawn
  def spawn_at(dest: nil, base: nil)
    raise ArgumentError, 'no dest' unless dest
    raise ArgumentError, 'no base' unless base

    entity = spawn(base: base, area: entity_area(dest))
    move_entity(entity: entity, dest: dest)
    entity
  end

  # spawn
  #
  # Create a new instance of an entity from a base entity
  def spawn(base: [], area: nil)
    entity = create_entity(base: base)
    debug("spawning #{entity} from #{base}")
    remove_component(entity, ViewExemptComponent)
    get_component!(entity, MetadataComponent).area = area

    if container = get_component(entity, ContainerComponent)
      bases = container.contents.clone
      container.contents = bases.map { |b| spawn_at(dest: entity, base: b ) }
    end
    if spawn_point = get_component(entity, SpawnPointComponent)
      bases = spawn_point.list.clone
      spawn_point.list = bases.map { |b| spawn(base: b, area: area) }
    end

    entity
  end

  # send_to_char
  #
  # Send output to entity if they have a connected ConnectionComponent
  def send_to_char(char: nil, buf: nil)
    conn_comp = get_component(char, ConnectionComponent) or return
    return unless conn_comp.conn
    conn_comp.buf << buf.to_s
    nil
  end

  # entity_contents
  #
  # Array of entities within an entity's ContainerComponent
  def entity_contents(entity)
    comp = get_component(entity, ContainerComponent) or return []
    comp.contents
  end

  # visible_contents
  #
  # Return the array of Entities within a Container Entity that are visibile to
  # the actor.
  def visible_contents(actor: nil, cont: nil)
    raise ArgumentError, 'no actor' unless actor
    raise ArgumentError, 'no container' unless cont

    # XXX handle visibility checks at some point
    comp = get_component(cont, ContainerComponent) or return []
    comp.contents.select { |c| get_component(c, ViewableComponent) }
  end

  # entity_exits
  #
  # Get all the exits in a room; most likely you want to use visible_exits
  # instead.
  def entity_exits(room)
    exits = get_component(room, ExitsComponent) or return []
    exits.get_modified_fields.values
  end

  # visible_exits
  #
  # Return the array of exits visible to actor in room.
  def visible_exits(actor: nil, room: nil)
    raise ArgumentError, 'no actor' unless actor
    raise ArgumentError, 'no room' unless room

    # XXX handle visibility checks at some point

    exits = get_component(room, ExitsComponent) or return []
    World::CARDINAL_DIRECTIONS.map do |dir|
      ex = exits.send(dir) or next
      next if entity_closed?(ex) and entity_concealed?(ex)
      ex
    end.compact
  end

  # entity_exists?(entity)
  #
  # Returns true if entity exists
  def entity_exists?(entity)
    !!World.entities[entity]
  end

  # entity_components(entity)
  #
  # Returns array of Components for an entity.
  #
  # Note: Most likely you don't need this, and should be using get_view() or
  # get_component() which are both faster.
  def entity_components(entity)
    World.entities[entity].compact
  end

  # entity_location(entity)
  #
  # Get the location for a given entity
  def entity_location(entity)
    loc = get_component(entity, LocationComponent) or return nil
    loc.entity
  end

  # player_config
  #
  # Get a specific config value from a entity's PlayerConfigComponent
  def player_config(player, option)
    config = get_component(player, PlayerConfigComponent) or return nil
    config.send(option)
  end

  # entity_keywords
  #
  # Get keywords for an entity
  def entity_keywords(entity)
    keywords = get_component(entity, KeywordsComponent) or return nil
    words = keywords.words
    words = [ words ] unless words.is_a?(Array)
    words.join('-')
  end

  # component_name
  #
  # Given a Component instance or class, return the name
  def component_name(arg)
    arg = arg.class if arg.is_a?(Component)
    arg.to_s.snakecase.sub(/_component$/, '').to_sym
  end

  # entity_area
  #
  # Get the area name from an entity id
  def entity_area(entity)
    meta = get_component(entity, :metadata) or return nil
    meta.area
  end

  # entity_has_component?
  #
  # Check to see if the entity has a specific component
  def entity_has_component?(entity, component)
    get_components(entity, component).empty? == false
  end

  # entity_closed?
  #
  # Check if an entity has a ClosableComponent and is closed
  def entity_closed?(entity)
    closable = get_component(entity, ClosableComponent) or return false
    !!closable.closed
  end

  # entity_locked?
  #
  # Check if an entity has a ClosableComponent and is locked
  def entity_locked?(entity)
    closable = get_component(entity, ClosableComponent) or return false
    !!closable.locked
  end

  # entity_concealed?
  #
  # Check if an entity has a ConcealedComponent and it has not been revealed
  def entity_concealed?(entity)
    concealed = get_component(entity, :concealed) or return false
    !concealed.revealed
  end

  # entity_flying?
  def entity_flying?(entity)
    # XXX fixup once we have affects
    false
  end

  # entity_animate?
  #
  # check if the entity is animate
  def entity_animate?(entity)
    entity_has_component?(entity, :animate)
  end

  # entity_short
  #
  # Get the short description for an entity
  def entity_short(entity)
    get_component(entity, ViewableComponent)&.short
  end

  # entity_desc
  #
  # Get the desc description for an entity
  def entity_desc(entity)
    get_component(entity, ViewableComponent)&.desc
  end

  # entity_volume
  #
  # Get the volume for an entity
  def entity_volume(entity)
    get_component(entity, :corporeal)&.volume || 0
  end

  # entity_weight
  #
  # Get the weight for an entity
  def entity_weight(entity)
    get_component(entity, :corporeal)&.weight || 0
  end
end
