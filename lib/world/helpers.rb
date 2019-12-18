require 'facets/string/indent'

module World::Helpers
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

  # place one entity inside another entity's contents
  def move_entity(entity, dest)
    dest = dest.entity if dest.is_a?(Reference)
    entity = entity.entity if entity.is_a?(Reference)

    # Remove the entity from any other location it was in previously
    if curr = entity.get(LocationComponent, :ref)
      curr.entity
          .get(ContainerComponent, :contents)
          .delete(entity.to_ref)
    else
      begin
        entity << LocationComponent.new
      rescue Entity::DuplicateUniqueComponent
        # noop; we're just ensuring the entity has a LocationComponent for the
        # next part
      end
    end

    contents = dest.get(ContainerComponent, :contents) or
        fault "dest #{dest} is not a container", dest
    contents << entity.to_ref
    entity.set(LocationComponent, ref: dest)
  end

  # get a/all entities from ++pool++ that have keywords that match our
  # the provided ++keyword++
  #
  # Arguments:
  #   ++buf++ String; "sword", "sharp-sword", "3.sword", "all.sword"
  #   ++pool++ Entity instances
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

    # resolve any references in our pool first
    pool.flatten!.map! { |e| e.is_a?(Reference) ? e.entity : e }

    # if the user hasn't specified an index, or the caller hasn't specified
    # that they want multiple matches, do the simple find here to grab and
    # return the first match
    if index.nil? and multiple != true
      return pool.find do |entity|
        ((entity.get(:keywords, :words) || []) & keywords)
            .size == keywords.size
      end
    end

    # Anything else requires us to have the full matches list
    matches = pool.select do |entity|
      ((entity.get(:keywords) || []) & keywords).size == keywords.size
    end

    return matches if index.nil? or index == 'all'

    index = index.to_i - 1
    multiple ? [ matches[index] ].compact : matches[index]
  end

  # spawn
  #
  # Create a new instance of an Entity base off a +base+ Entity and move it
  # into a +dest+ Entity (container).  This method **will** add the new Entity
  # to World.
  #
  # Arguments:
  #   dest: container Entity to move entity to
  #   base: base Entity to spawn
  def spawn(dest, base)
    add_list = []
    entity = World.add_entity(World.new_entity(base: base))
    # XXX how do we trigger the spawning of things in the base in this new
    # entity?
    move_entity(entity, dest)
  end

  # visible_contents
  #
  # Return the array of Entities within a Container Entity that are visibile to
  # the actor.
  def visible_contents(actor: nil, cont: nil)
    raise ArgumentError, 'no actor' unless actor
    raise ArgumentError, 'no container' unless cont

    # XXX handle visibility checks at some point
    cont.get(ContainerComponent, :contents) || []
  end
end
