require 'digest'

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
      extend ActsAsReplaceable::ClassMethods
      include ActsAsReplaceable::InstanceMethods

      attr_reader :has_been_replaced
      cattr_accessor :acts_as_replaceable_options

      options.symbolize_keys!
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

    # Search the incoming attributes for attributes that are in the replaceable conditions and use those to form an Find conditions
    def self.match_conditions(record)
      output = {}
      record.acts_as_replaceable_options[:match].each do |attribute_name|
        output[attribute_name] = record[attribute_name]
      end
      return output
    end

    def self.insensitive_match_conditions(record)
      sql = []
      binds = []
      record.acts_as_replaceable_options[:insensitive_match].each do |attribute_name|
        if value = record[attribute_name]
          sql << "LOWER(#{attribute_name}) = ?"
          binds << record[attribute_name].downcase
        else
          sql << "#{attribute_name} IS NULL"
        end
      end
      return [sql.join(' AND ')] + binds
    end

    # Copy attributes to existing and see how it would change if we updated it
    # Mark all record's attributes that have changed, so even if they are
    # still default values, they will be saved to the database
    def self.mark_changes(record, existing)
      copy_attributes(record.attribute_names, record, existing)

      existing.changed.each {|attribute| record.send("#{attribute}_will_change!") }

      return existing.changed?
    end

    def self.copy_attributes(attributes, source, target)
      attributes.each do |attribute|
        target[attribute] = source[attribute]
      end
    end

    # Searches the database for an existing copies of record
    def self.find_existing(record)
      existing = record.class
      existing = existing.where match_conditions(record)
      existing = existing.where insensitive_match_conditions(record)
    end

    # A lock is used to prevent multiple threads from executing the same query simultaneously
    # eg. In a multi-threaded environment, 'find_or_create' is prone to failure due to the possibility
    # that the process is preempted between the 'find' and 'create' logic
    def self.lock(record)
      query = [match_conditions(record), insensitive_match_conditions(record)].inspect

      lock_id = "query_cache/#{Digest::MD5.hexdigest(query)}"
      lock_acquired = false

      # Acquire the lock
      while !lock_acquired do
        lock_acquired = Rails.cache.increment(lock_id) == 1 # Atomically increment and return the value so we can see if we're the first to request the lock

        unless lock_acquired
          puts "lock was in use #{lock_id}"
          sleep(0.250)
        end
      end
      yield

    ensure # Give up the lock
      Rails.cache.write(lock_id, "0", :raw => true) if lock_acquired
    end
  end

  module ClassMethods
    def duplicates
      columns = acts_as_replaceable_options[:match] + acts_as_replaceable_options[:insensitive_match]

      dup_data = self.select(columns.join(', '))
      dup_data.group! acts_as_replaceable_options[:match].join(', ')
      dup_data.group! acts_as_replaceable_options[:insensitive_match].collect{|m| "LOWER(#{m}) AS #{m}"}.join(', ')
      dup_data.having! "count (*) > 1"

      join_condition = columns.collect{|c| "#{table_name}.#{c} = dup_data.#{c}"}.join(' AND ')

      return self.joins("JOIN (#{dup_data.to_sql}) AS dup_data ON #{join_condition}")
    end
  end

  module InstanceMethods
    # Override the create or update method so we can run callbacks, but opt not to save if we don't need to
    def create_record(*args)

      ActsAsReplaceable::HelperMethods.lock(self) do
        find_and_replace
        if @has_not_changed
          logger.info "(acts_as_replaceable) Found unchanged #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
        elsif @has_been_replaced
          update_record(*args)
          logger.info "(acts_as_replaceable) Updated existing #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
        else
          super
          logger.info "(acts_as_replaceable) Created #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
        end
      end

      return true
    end

    # Replaces self with an existing copy from the database if available, raises an exception if more than one copy exists in the database
    def find_and_replace
      existing = ActsAsReplaceable::HelperMethods.find_existing(self)

      if existing.length > 1
        raise RecordNotUnique, "#{existing.length} duplicate #{record.class.model_name.human.pluralize} present in database"
      end

      replace_with(existing.first) if existing.first
    end

    def replace_with(existing)
      # Inherit target's attributes for those in acts_as_replaceable_options[:inherit]
      ActsAsReplaceable::HelperMethods.copy_attributes(acts_as_replaceable_options[:inherit], existing, self)

      @new_record        = false
      @has_been_replaced = true
      @has_not_changed   = !ActsAsReplaceable::HelperMethods.mark_changes(self, existing)
    end
  end

  class RecordNotUnique < Exception
  end
end
