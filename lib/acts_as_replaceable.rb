require 'acts_as_replaceable/acts_as_replaceable'

ActiveRecord::Base.extend ActsAsReplaceable::ActMethod

# Rails 3 compatibility
if ActiveRecord::VERSION::MAJOR < 4
	ActiveRecord::Base.class_eval do
	  def create(*args)
	    create_record(*args)
	  end

	  def update_record(*args)
	    update(*args)
	  end
	end
end
