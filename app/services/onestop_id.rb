require 'addressable/template'

module OnestopId

  COMPONENT_SEPARATOR = '-'
  GEOHASH_FILTER = /[^0123456789bcdefghjkmnpqrstuvwxyz]/
  NAME_TILDE = /[\-\:\&\@\/]/
  NAME_FILTER = /[^a-zA-Z\d\@\~]/
  IDENTIFIER_TEMPLATE = Addressable::Template.new("gtfs://{feed_onestop_id}/{entity_prefix}/{entity_id}")

  class OnestopIdBase

    PREFIX = nil
    MODEL = nil
    NUM_COMPONENTS = 3

    attr_accessor :geohash, :name

    def initialize(string: nil, geohash: nil, name: nil, entity_prefix: nil)
      if string && string.length > 0
        @geohash = string.split(COMPONENT_SEPARATOR)[1]
        @name = string.split(COMPONENT_SEPARATOR)[2]
      elsif geohash && name
        # Filter geohash and name; validate later
        @geohash = geohash_filter(geohash)
        @name = name_filter(name)
      else
        raise ArgumentError.new('either a string or entity/geohash/name must be specified')
      end
      # Check valid OnestopID
      is_a_valid_onestop_id, errors = self.validate(self.to_s)
      if !is_a_valid_onestop_id
        raise ArgumentError.new(errors.join(', '))
      end
      self
    end

    def to_s
      [self.class::PREFIX, @geohash, @name].join(COMPONENT_SEPARATOR)
    end

    def validate(value)
      split = value.split(COMPONENT_SEPARATOR)
      errors = []
      errors << 'must not be empty' if value.blank?
      errors << 'incorrect length' unless split.size == self.class::NUM_COMPONENTS
      errors << 'invalid geohash' unless validate_geohash(split[1])
      errors << 'invalid name' unless validate_name(split[2])
      # errors << 'invalid suffix' unless validate_suffix(split[3])
      return (errors.size == 0), errors
    end

    def validate_geohash(value)
      !(value =~ GEOHASH_FILTER)
    end

    def validate_name(value)
      !(value =~ NAME_FILTER)
    end

    def validate_prefix(value)
      value == self.PREFIX
    end

    def validate_suffix(value)
      true
    end

    private

    def name_filter(value)
      value.downcase.gsub(NAME_TILDE, '~').gsub(NAME_FILTER, '')
    end

    def geohash_filter(value)
      value.downcase.gsub(GEOHASH_FILTER, '')
    end
  end

  class OperatorOnestopId < OnestopIdBase
    PREFIX = :o
    MODEL = Operator
  end

  class FeedOnestopId < OnestopIdBase
    PREFIX = :f
    MODEL = Feed
  end

  class StopOnestopId < OnestopIdBase
    PREFIX = :s
    MODEL = Stop
  end

  class RouteOnestopId < OnestopIdBase
    PREFIX = :r
    MODEL = Route
  end

  class RouteStopPatternOnestopId < OnestopIdBase
    PREFIX = :r
    # MODEL = RouteStopPattern
    NUM_COMPONENTS = 4
  end

  LOOKUP = Hash[OnestopId::OnestopIdBase.descendants.map { |c| [[c::PREFIX, c::NUM_COMPONENTS], c] }]

  def self.lookup(string: nil, prefix: nil, num_components: 3)
    if string && string.length > 0
      split = string.split(COMPONENT_SEPARATOR)
      prefix = split[0]
      prefix = prefix.to_sym if prefix
      num_components = split.size
    end
    prefix = prefix.to_sym if prefix
    LOOKUP[[prefix, num_components]]
  end

  def self.create_identifier(feed_onestop_id, entity_prefix, entity_id)
    IDENTIFIER_TEMPLATE.expand(
      feed_onestop_id: feed_onestop_id,
      entity_prefix: entity_prefix,
      entity_id: entity_id
    ).to_s
  end

  def self.validate_onestop_id_string(onestop_id)
    klass = lookup(string: onestop_id)
    return false, ['must not be empty'] if onestop_id.blank?
    return false, ['invalid prefix'] unless klass
    klass.new(string: onestop_id).validate(onestop_id)
  end

  def self.find(onestop_id)
    lookup(string: onestop_id)::MODEL.find_by(onestop_id: onestop_id)
  end

  def self.find!(onestop_id)
    lookup(string: onestop_id)::MODEL.find_by!(onestop_id: onestop_id)
  end

  def self.new(*args)
    if !args.empty? && args[0].has_key?(:string)
      lookup(string: args[0][:string]).new(*args)
    elsif !args.empty? && args[0].has_key?(:entity_prefix)
      lookup(prefix: args[0][:entity_prefix]).new(*args)
    #elsif args[0].has_key?(:route_onestop_id)
      #RouteStopPatternOnestopId.new(*args)
    else
      raise ArgumentError.new('either a string or id components must be specified')
    end
  end
end
