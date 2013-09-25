$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')

require 'active_record'
require 'logger'
require 'acts_as_replaceable'

ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = Logger::INFO
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")

ActiveRecord::Schema.define(:version => 0) do
  create_table :items, :force => true do |t|
    t.integer :holding_institution_id
    t.string :identification_number
    t.integer :collection_id
    t.string :name
    t.string :fingerprint
  end

  create_table :people, :force => true do |t|
    t.string :first_name
    t.string :last_name
  end

  create_table :materials, :force => true do |t|
    t.string :name
  end

  create_table :locations, :force => true do |t|
    t.string :country
    t.string :city
  end
end


class Material < ActiveRecord::Base
  acts_as_replaceable :match => :name
  validates_presence_of :name
end

class Location < ActiveRecord::Base
  acts_as_replaceable :match => [:country, :city]
  validates_presence_of :country, :city
end

class Item < ActiveRecord::Base
  acts_as_replaceable :match => [:holding_institution_id, :identification_number, :collection_id], :inherit => :fingerprint
  validates_presence_of :holding_institution_id, :identification_number
end

class Person < ActiveRecord::Base
  acts_as_replaceable :insensitive_match => [:first_name, :last_name]
  validates_presence_of :first_name
end

def insert_model(klass, attributes)
  ActiveRecord::Base.connection.execute "INSERT INTO #{klass.quoted_table_name} (#{attributes.keys.join(",")}) VALUES (#{attributes.values.collect { |value| ActiveRecord::Base.connection.quote(value) }.join(",")})", 'Fixture Insert'
  return klass.order(:id).last
end

class Rails
  def self.cache
    @cache ||= Cache.new
  end

  def self.cache=(cache)
    @cache = cache
  end

  class Cache
    def initialize
      @lock = Mutex.new
      @store = {}
    end

    def write(key, value, *args)
      @lock.synchronize do
        @store[key] = value
      end
    end

    def increment(key, *args)
      @lock.synchronize do
        @store[key] = @store[key].to_i + 1
      end
    end
  end

  # init cache so it's there before multiple threads race to initialize it and end up with two different caches
  self.cache
end
