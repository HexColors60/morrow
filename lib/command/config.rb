module Command::Config
  extend World::Helpers

  Command.register('config') do |actor, rest|
    fault 'no :config_options found for actor', actor unless
        config = actor.get_component(:config_options)

    key, value = rest.split(/\s+/, 2) if rest
    if key
      raise Command::SyntaxError,
          'value must be true/false or on/off' unless
              value =~ /^(true|on|false|off)(\s|$)/
      value = %w{ true on }.include?($1)
      config.set(key, value)
      next "#{key} = #{value}"
    end

    fields = config.fields
    field_width = fields.map(&:size).max
    buf = "&WConfigration Options:&0\n"
    fields.each do |name|
      buf << "  &W%#{field_width}s&0: &c%s&0\n" % [ name, config.get(name) ]
    end
    buf
  end
end
