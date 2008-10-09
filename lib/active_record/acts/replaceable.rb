module ActiveRecord
  module Acts #:nodoc:
    module Replaceable #:nodoc:
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def acts_as_replaceable(options = {})
          class_eval <<-EOV
            include ActiveRecord::Acts::Replaceable::InstanceMethods

            attr_accessor :has_been_replaced

            def replacement_conditions
              #{options[:conditions].inspect}
            end
          EOV
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

          humanized_class_name = self.class.to_s.humanize
          # Begin Save with exception handling
          begin
            super
            if @has_been_replaced
              Log.info("Found existing #{humanized_class_name} ##{id} - #{name}")
            else
              Log.info("Created #{humanized_class_name} ##{id} - #{name}")
            end
          rescue => exception
            SiteItemLog.error "RRN #{humanized_class_name} ##{id} - Name: #{name} - Couldn't save because #{exception.message}"
          end
        end
      end 
    end
  end
end
