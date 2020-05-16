# Entity is a character in the world.  It can perform actions, has a level,
# some classes, etc.
class Morrow::Component::Character < Morrow::Component

  # Overall level of the character.  For players, this will be the maximum
  # level of all their classes.
  field :level, type: (1..), default: 1

  class_level_type = {
    _template: {
      keys: lambda { Morrow.config.classes.keys },
      type: 1..,
      desc: <<~DESC
        Level of the character for the given class.  A value of nil denotes
        that the character is not a member of the class.
      DESC
    }
  }
  # Per-class level for this character.
  field :class_level, type: class_level_type

  # Current health of this entity; may be higher than #health_max for due to
  # temporary hit points.
  field :health, type: Integer

  # Maximum health of this entity.  This is a function of multiple fields in
  # the Attributes component.
  field :health_max, type: Integer

  # Percentage of health_max that will be regenerated each second.
  field :health_regen, type: Float

  # position of the entity.  Affects ability to do specific commands,
  # resource regeneration, damage received.
  field :position, valid: %i{ standing sitting lying }, default: :standing

  # flag to denote the entity is unconscious, and unable to perform any
  # actions.
  field :unconscious, type: :boolean, default: false
end

