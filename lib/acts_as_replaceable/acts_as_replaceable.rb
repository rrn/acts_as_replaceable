module ActsAsReplaceable
  module ActMethod
    # If any before_save methods change the attributes,
    # acts_as_replaceable will not function correctly.
    #
    # OPTIONS
    # :match => what fields to match against when finding a duplicate
    # :insensitive_match => what fields to do case insensitive matching on.
    # :inherit => what attributes of the existing record overwrite our own attributes
    def acts_as_replaceable(options = {})
      include ActsAsReplaceable::InstanceMethods

      options.symbolize_keys!
      cattr_accessor :acts_as_replaceable_options
      self.acts_as_replaceable_options = {}
      self.acts_as_replaceable_options[:match] = ActsAsReplaceable::HelperMethods.sanitize_attribute_names(self, options[:match])
      self.acts_as_replaceable_options[:insensitive_match] = ActsAsReplaceable::HelperMethods.sanitize_attribute_names(self, options[:insensitive_match])
      self.acts_as_replaceable_options[:inherit] = ActsAsReplaceable::HelperMethods.sanitize_attribute_names(self, options[:inherit], options[:insensitive_match], :id, :created_at, :updated_at)
    end
  end
  
  module HelperMethods
    def self.sanitize_attribute_names(klass, *args)
      # Intersect the proposed attributes with the column names so we don't start assigning attributes that don't exist. e.g. if the model doesn't have timestamps
      klass.column_names & args.flatten.compact.collect(&:to_s)
    end
  end

  module InstanceMethods
    # Override the create or update method so we can run callbacks, but opt not to save if we don't need to
    def create
      find_and_replace
      if @has_not_changed
        logger.info "(acts_as_replaceable) Found unchanged #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
      elsif @has_been_replaced
        update
        logger.info "(acts_as_replaceable) Updated existing #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
      else
        super
        logger.info "(acts_as_replaceable) Created #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
      end
      
      return true
    end

    def find_and_replace
      replace(find_duplicate)
    end

    private

    def find_duplicate
      records = self.class.where(conditions_for_find_duplicate)
      if records.size > 1
        raise "#{records.size} Duplicate #{self.class.model_name.pluralize} Present in Database:\n  #{self.inspect} == #{records.inspect}"
      end

      return records.first
    end

    def replace(other)
      return unless other
      inherit_attributes(other)
      @has_been_replaced = true
      define_singleton_method(:new_record?) { false }
      define_singleton_method(:persisted?) { true }
      @has_not_changed = !mark_changes(other)
      puts "#{self.inspect} has changed" unless @has_not_changed
    end

    # Inherit other's attributes for those in acts_as_replaceable_options[:inherit]
    def inherit_attributes(other)
      acts_as_replaceable_options[:inherit].each do |attrib|
        self[attrib] = other[attrib]
      end
    end

    def mark_changes(other)
      attribs = self.attributes

      # Copy attributes to other and see how it would change if we updated it
      # Mark all self's attributes that have changed, so even if they are
      # still default values, they will be saved to the database
      attribs.each do |key, value|
        other[key] = value
      end
      
      other.changed.each {|attribute| send("#{attribute}_will_change!") }

      return other.changed?
    end

    # Search the incoming attributes for attributes that are in the replaceable conditions and use those to form an Find conditions 
    def conditions_for_find_duplicate
      sql = []
      binds = []
      acts_as_replaceable_options[:match].each do |attribute_name|
        sql << "#{attribute_name} = ?"
        binds << self[attribute_name]
      end
      acts_as_replaceable_options[:insensitive_match].each do |attribute_name|
        sql << "LOWER(#{attribute_name}) = ?"
        binds << self[attribute_name].downcase
      end
      return [sql.join(' AND ')] + binds
    end
  end
end