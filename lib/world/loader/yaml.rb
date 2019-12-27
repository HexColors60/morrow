class World::Loader::Yaml < World::Loader::Base
  def self.can_load?(path)
    !!(path =~ /\.ya?ml$/)
  end

  SUPPORTED_KEYS = %w{ id base components remove link }

  def load(path: nil, area: 'unknown')
    buf = File.read(path)

    # parse the document into a Psych tree; we don't load here because we want
    # the file/line info while creating our entities.
    doc = YAML.parse(buf)

    unless seq = doc.children[0] and seq.sequence?
      raise "expected #{path} does not contain the expected YAML sequence"
    end

    seq.children.each do |map|
      raise "expected mapping at #{path}@#{map.start_line}, got #{map}" unless
          map.mapping?
      definition = map.to_ruby

      unknown_keys = definition.keys - SUPPORTED_KEYS
      unless unknown_keys.empty?
        warn "unknown keys #{unknown_keys} at #{path}:#{map.start_line}"
      end

      # Create an Array of the various base Entities that will be layered into
      # this Entity
      base = [definition["base"]].flatten.compact

      # Links are an Array of References (!ref -> Reference done in yaml.load)
      links = [definition["link"]].flatten.compact

      # Construct an Array of Component instances
      components = (definition["components"] || {}).map do |conf|
        case conf
        when String, Symbol
          # A bare String or Symbol means to include Component with defaults
          Component.find(conf).new

        when Hash
          # A Hash is a component with non-default values.  The values may be
          # provided as a Hash, an Array (must have all elements), or a scalar
          # (for single field Components)
          comp, config = conf.first
          case config
          when Hash
            config.rekey! { |k| k.to_sym }
          when Array
            # don't make any changes
          else
            # turn this non-array value into an array of a single element
            config = [ config ]
          end

          Component.find(comp).new(config)
        else
          warn 'skipping unsupported component config at %s:%d: %s' %
              [ path, map.start_line, conf.inspect ]
          next
        end
      end

      components << MetadataComponent
          .new(source: "#{path}:#{map.start_line}", area: area, base: base)

      remove = (definition['remove'] || []).map(&:to_sym)

      # common arguments for creating an entity
      args = {
          base: base, components: components, link: links,
          remove: remove
      }

      # if there is an ID assigned to this entity, update the area to report
      # where it really came from, and add it to our args
      args[:id] = definition['id'] if definition.has_key?('id')

      @loader.schedule(:create_entity, args)
    end
  end
end
