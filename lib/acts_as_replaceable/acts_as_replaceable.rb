require 'openssl'
require 'timeout'

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

      if ActsAsReplaceable.concurrency && !Rails.cache.respond_to?(:increment)
        raise LockingUnavailable, "To run ActsAsReplaceable in concurrency mode, the Rails cache must provide an :increment method that performs an atomic addition to the given key, e.g. Memcached"
      end
    end
  end

  # If using parallel processes to save replaceable records, set this to true to prevent race conditions
  def self.concurrency=(value)
    @concurrency = value
  end

  def self.concurrency
    !!@concurrency
  end

  module HelperMethods
    def self.sanitize_attribute_names(klass, *args)
      unless klass.connected? && klass.table_exists?
        ActiveRecord::Base.logger.warn "(acts_as_replaceable) unable to connect to table `#{klass.table_name}` so excluding all attribute names"
        return []
      end
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

      return nil if sql.empty?
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
      existing = record.class.default_scoped
      existing = existing.where match_conditions(record)
      existing = existing.where insensitive_match_conditions(record)
    end

    # Conditionally lock (lets us enable or disable locking)
    def self.lock_if(condition, *lock_args, &block)
      if condition
        lock(*lock_args, &block)
      else
        yield
      end
    end

    # A lock is used to prevent multiple threads from executing the same query simultaneously
    # eg. In a multi-threaded environment, 'find_or_create' is prone to failure due to the possibility
    # that the process is preempted between the 'find' and 'create' logic
    def self.lock(record, timeout = 20)
      lock_id  = "ActsAsReplaceable/#{OpenSSL::Digest::MD5.digest([match_conditions(record), insensitive_match_conditions(record)].inspect)}"
      acquired = false

      # Acquire the lock by atomically incrementing and returning the value to see if we're first
      while !acquired do
        unless acquired = Rails.cache.increment(lock_id) == 1
          puts "lock was in use #{lock_id}"
          sleep(0.250)
        end
      end

      # Reserve the lock for only 10 seconds more than the timeout to ensure a lock is always eventually released
      Rails.cache.write(lock_id, "1", :raw => true, :expires_in => timeout + 10)
      Timeout::timeout(timeout) do
        yield
      end

    ensure # Give up the lock
      Rails.cache.write(lock_id, "0", :raw => true) if acquired
    end
  end

  module ClassMethods
    def duplicates
      columns = acts_as_replaceable_options[:match] + acts_as_replaceable_options[:insensitive_match]

      dup_data = self.select(columns.join(', '))
      dup_data = dup_data.group acts_as_replaceable_options[:match].join(', ')
      dup_data = dup_data.group acts_as_replaceable_options[:insensitive_match].collect{|m| "LOWER(#{m}) AS #{m}"}.join(', ')
      dup_data = dup_data.having "count (*) > 1"

      join_condition = columns.collect {|c| "#{table_name}.#{c} = dup_data.#{c}" }.join(' AND ')

      return self.joins("JOIN (#{dup_data.to_sql}) AS dup_data ON #{join_condition}")
    end
  end

  module InstanceMethods
    # Override the create or update method so we can run callbacks, but opt not to save if we don't need to
    def _create_record(*args)
      ActsAsReplaceable::HelperMethods.lock_if(ActsAsReplaceable.concurrency, self) do
        find_and_replace
        if @has_not_changed
          logger.info "(acts_as_replaceable) Found unchanged #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
        elsif @has_been_replaced
          _update_record(*args)
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
        raise RecordNotUnique, "#{existing.length} duplicate #{self.class.model_name.human.pluralize} present in database"
      end

      replace_with(existing.first) if existing.first
    end

    def replace_with(existing)
      # Inherit target's attributes for those in acts_as_replaceable_options[:inherit]
      ActsAsReplaceable::HelperMethods.copy_attributes(acts_as_replaceable_options[:inherit], existing, self)

      # Rails 5 introduced AR::Dirty and started using `mutations_from_database` to
      # lookup `id_in_database` which is required for the `_update_record` call
      #
      # This chunk of code is copied from https://api.rubyonrails.org/classes/ActiveRecord/Persistence.html#method-i-becomes
      if existing.respond_to?(:mutations_from_database, true)
        instance_variable_set("@mutations_from_database", existing.send(:mutations_from_database) || nil)
      end

      @new_record        = false
      @has_been_replaced = true
      @has_not_changed   = !ActsAsReplaceable::HelperMethods.mark_changes(self, existing)
    end
  end

  class RecordNotUnique < StandardError; end
  class LockingUnavailable < StandardError; end
end
