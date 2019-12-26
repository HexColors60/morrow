require 'forwardable'
require 'facets/kernel/deep_clone'
require 'facets/hash/symbolize_keys'
require 'facets/hash/rekey'
require 'facets/hash/deep_rekey'
require 'facets/string/modulize'
require 'facets/kernel/constant'

class Component

  # class methods
  class << self
    def inherited(other)
      other.instance_variable_set(:@defaults, {})
      other.instance_variable_set(:@unique, true)
    end

    # find
    #
    # Given a human-readable component name as a String or Symbol, return the
    # Class for that Component type.
    def find(name)
      begin
        Kernel.constant("#{name}_component".modulize)
      rescue NameError
        raise ArgumentError, "unknown Component, #{name}"
      end
    end

    attr_accessor :defaults

    # Note that this Component will not be unique on the Entity
    def not_unique
      define_method(:unique?) { false }
      @unique = false
    end

    # Determine if this Component is unique in the Entity
    def unique?
      !!@unique
    end

    # To notify Entity#merge that this component should not be merged
    def not_merged
      define_method(:merge?) { false }
    end

    # Define a field in the Component
    #
    # Arguments:
    #   name: Name of the field
    #
    # Parameters:
    #   default: default value; defaults to nil
    #   freeze: if the setter should clone & freeze the value; default false
    #   clone: if the value should be cloned when set; default true
    def field(name, default: nil, freeze: false, clone: true)
      name = name.to_sym
      variable = "@#{name}".to_sym
      modified = "@__modified_#{name}".to_sym

      # set our default value in the class
      @defaults[name] = default

      # declare the getter
      attr_reader name

      # the setter is a little more complicated
      define_method('%s=' % name) do |value, set_modified: true|

        # We don't need to do anything to a frozen variable, but if it's not
        # frozen, if we're supposed to clone it, do so, and if we're supposed
        # to freeze it, also do that.
        unless value.frozen?
          value = value.clone if clone
          value.freeze if freeze
        end

        # set the instance variable for this field
        instance_variable_set(variable, value)

        # also, unless explicitly told not to, mark this variable as modified.
        # This exception is used by the initializer to set the defaults.
        instance_variable_set(modified, true) if set_modified
      end
    end
  end

  # Component.new(1,2,3)    # Same number of fields
  # Component.new(a: 1, b: 2)
  def initialize(arg={})
    fields = self.class.defaults

    case arg
    when Array
      raise ArgumentError, "got #{arg}; need #{fields.size} values" unless
          arg.size == fields.size
      fields.each_with_index { |(k,_),i| send("#{k}=", arg[i]) }

    when Hash
      unknown = arg.keys - fields.keys
      raise ArgumentError,
          "Unknown component fields, #{unknown}, for #{self}" unless
              unknown.empty?

      # For hashes, we'll use the setter method for any field provided, but if
      # one wasn't provided, we'll set it to the default
      fields.each do |key,default|
        if arg.has_key?(key)
          send("#{key}=", arg[key])
        else
          send("#{key}=", default, set_modified: false)
        end
      end
    else
      raise ArgumentError, "Unsupported argument type: #{arg.inspect}"
    end
  end

  # unique?
  #
  # Return if this Component is unique per-Entity.
  #
  # Note, this method is replaced when the subclass calls #not_unique in it's
  # definition.
  def unique?
    true
  end

  # merge?
  #
  # Return if this Component should be merged by Entity#merge
  #
  # Note: this method is replaced when the subclass calls Component.not_merged
  def merge?
    true
  end

  # to_h
  #
  # Return a Hash of field/value pairs
  #
  def to_h
    self.class.defaults.keys.inject({}) do |o,field|
      o[field] = send(field)
      o
    end
  end

  # - / diff
  #
  # Return a Hash of the difference between this Component and another
  # Component of the same type, or a Hash with the same field keys
  def -(other)
    other = other.to_h if other.is_a?(self.class)
    raise ArgumentError, "Unsupported type for diff; #{other.inspect}" unless
        other.is_a?(Hash)
    to_h.reject { |k,v| other[k] == v }
  end

  # clone
  #
  # Clone a component
  def clone
    values = self.class.defaults.keys.map { |k| send(k) }
    self.class.new(values)
  end

  # clear_modified!
  #
  # Clear all modified flags on this instance.  Used in EntityManager after
  # merging all the base entities into a class.
  def clear_modified!
    self.class.defaults.each do |k,_|
      begin
        remove_instance_variable("@__modified_#{k}")
      rescue NameError
      end
    end
    self
  end

  # get_modified_fields
  #
  # Obscenely long name to try to not conflict with a possible field value, but
  # this will get a Hash containing field & modified value for every field in
  # this component that has been modified.
  def get_modified_fields
    self.class.defaults.inject({}) do |out,(k,_)|
      out[k] = send(k) if instance_variable_get("@__modified_#{k}")
      out
    end
  end

  # merge!
  #
  # Merge in another Component, or component values
  #
  # Arguments:
  #   other: Hash, or Component instance
  def merge!(other)
    other = other.get_modified_fields if other.is_a?(self.class)
    raise ArgumentError, "invalid other #{other.inspect}" unless
        other.is_a?(Hash)
    other.each { |k,v| send("#{k}=", v) }
  end
end
