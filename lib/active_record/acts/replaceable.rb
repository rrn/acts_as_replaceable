module ActiveRecord
  module Acts #:nodoc:
    module Replaceable #:nodoc:
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def acts_as_replaceable(options = {})
          puts options.to_s
          validate_replaceable_conditions(options[:conditions])
          conditions_hash = Hash.new
          case options[:conditions]
          when Array
            for condition in options[:conditions]
              conditions_hash[condition.to_sym] = condition.to_s
            end
          when Hash
              conditions_hash = options[:conditions]
          end
          # gsub the inspected conditions to remove double quotes since a string is passed as the value of the hash pair
          # :key => "value"   ->   :key => value
          replacement_conditions_string = conditions_hash.inspect.gsub('"','')

          class_eval <<-EOV
            include ActiveRecord::Acts::Replaceable::InstanceMethods

            attr_accessor :has_been_replaced

            def replacement_conditions
              #{replacement_conditions_string}
            end
          EOV
        end

        private

        def validate_replaceable_conditions(conditions)
          puts "Validating conditions for #{self.class}"
          case conditions
          when Array
            conditions.each do |value|
              puts "checking #{value}"
              unless value.is_a?(Symbol) or value.is_a?(String)
                raise "Conditions passed to acts_as_replaceable must be Strings or Symbols"
              end
            end
          when Hash
            conditions.each do |key,value|
              puts "checking #{key} => #{value}"
              unless key.is_a?(Symbol) and value.is_a?(String)
                raise "Conditions passed to acts_as_replaceable must be Strings or Symbols"
              end
            end
          end
        end
      end

      module InstanceMethods
        # Replaces self with the attributes and id of other and assumes other's @new_record status
        def replace(other)
          return false unless other
          # Update self's missing attributes with those from the database
          self.attributes.reverse_merge!(other.attributes)
          self.id = other.id
          @new_record = other.new_record?
          @has_been_replaced = true
          return true
        end

        def find_duplicate(conditions = {})
          records = self.class.find(:all, :conditions => conditions)
          if records.size > 1
            raise "Duplicate Records Present in Database"
          end
          return records.first
        end
        
        def save!
          # Find the existing record if it exists and set this instantiation's attributes to match (as if we replaced the current object with the existing one)
          replace(find_duplicate(replacement_conditions))
          # Begin Save with exception handling
          begin
            super
            if @has_been_replaced
              Log.info("Found existing #{self.class.to_s.humanize} ##{id} - #{name if respond_to?('name')}")
            else
              Log.info("Created #{self.class.to_s.humanize} ##{id} - #{name if respond_to?('name')}")
            end
          rescue => exception
            SiteItemLog.error "RRN #{self.class.to_s.humanize} ##{id} - Name: #{name if respond_to?('name')} - Couldn't save because #{exception.message}"
          end
        end
      end 
    end
  end
end
