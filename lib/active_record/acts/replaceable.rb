module ActiveRecord
  module Acts #:nodoc:
    module Replaceable #:nodoc:
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # If any before_save methods change the attributes,
        # acts_as_replaceable will not function correctly.
        def acts_as_replaceable(options = {})
          class_variable_set(:@@replacement_options, options.reverse_merge!(:conditions => []))

          include ActiveRecord::Acts::Replaceable::InstanceMethods
          extend ActiveRecord::Acts::Replaceable::SingletonMethods
        end
      end

      module SingletonMethods
        # Returns a list of column names that must form a unique key for this model
        def attributes_replaceable_on
          class_variable_get(:@@replacement_options)[:conditions]
        end

      end

      module InstanceMethods

        # Override the create or update method so we can run callbacks, but opt not to save if we don't need to
        def create_or_update_without_callbacks
          find_and_replace
          if @has_not_changed
            logger.info "(acts_as_replaceable) Found unchanged #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
          elsif @has_been_replaced
            super
            logger.info "(acts_as_replaceable) Updated existing #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
          else
            super
            logger.info "(acts_as_replaceable) Created #{self.class.to_s} ##{id} #{"- Name: #{name}" if respond_to?('name')}"
          end
          return true
        end

        def find_and_replace
          replace(find_duplicate(conditions_for_find_duplicate))
        end

        def find_duplicate(conditions = {})
          records = self.class.find(:all, :conditions => conditions)
          if records.size > 1
            raise "Duplicate Records Present in Database: #{self.class} - #{conditions}"
          end

          return records.first
        end

        def replace(other)
          return unless other

          @has_been_replaced = true
          @new_record = false
          @has_not_changed = !mark_changes(other)
          self.id = other.id
        end

        def mark_changes(other)
          attribs = self.attributes

          # Remove timestamps because we don't care about those
          attribs.delete('created_at')
          attribs.delete('updated_at')

          # Copy attributes to other and see how it would change if we updated it
          # Mark all self's attributes that have changed, so even if they are
          # still default values, they will be saved to the database
          other.attributes = attribs
          other.changed.each{|attribute| send("#{attribute}_will_change!")}
          
          return other.changed?
        end

        # Search the incoming attributes for attributes that are in the replaceable conditions and use those to form a conditions hash
        # eg. given acts_as_replaceable :conditions => [:first_name, :last_name]
        #     replacement_conditions({:first_name => 'dave', :last_name => 'bobo', :age => 42}) => :first_name => 'dave', :last_name => 'bobo'
        def conditions_for_find_duplicate
          returning Hash.new do |output|
            self.class.attributes_replaceable_on.each do |attribute_name|
              output[attribute_name] = self[attribute_name]
            end
          end
        end
      end
    end
  end
end