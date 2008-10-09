$:.unshift "#{File.dirname(__FILE__)}/lib"
require 'active_record/acts/replaceable'
ActiveRecord::Base.class_eval { include ActiveRecord::Acts::Replaceable }
