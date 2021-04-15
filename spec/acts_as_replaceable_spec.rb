require 'spec_helper'

describe 'acts_as_replaceable' do
  before(:each) do
    [Material, Item, Person].each(&:destroy_all) # Because we're using sqlite3 and it doesn't support transactional specs (afaik)
  end

  describe "Class methods" do
    it "should be able to return records for which duplicates exist in the database" do
      insert_model(Material, :name => 'glass')
      wood1 = insert_model(Material, :name => 'wood')
      wood2 = insert_model(Material, :name => 'wood')
      Material.duplicates.order(:id).should == [wood1, wood2]
    end
  end

  describe "Model" do
    it 'evaluates without error when no database table exists' do
      eval("class NoTable < ActiveRecord::Base; end")
      klass = NoTable

      klass.table_name = "some_table_that_does_not_exist"
      expect(klass.acts_as_replaceable).to be_nil
    end
  end

  describe "Helper Methods" do
    before(:each) { @record = insert_model(Material, :name => 'glass')}

    it "should only allow one thread to hold the lock at a time" do
      mutex = Mutex.new
      counter = 0
      expect do
        2.times.collect do
          Thread.new do
            ActsAsReplaceable::HelperMethods.lock(@record) do
              expected = mutex.synchronize { counter += 1 }
              sleep 1 # Long enough that the other thread can try to obtain the lock while we're asleep
              raise unless expected == counter
            end
          end
        end.each(&:join)
      end.not_to raise_exception
    end

    it "should time out execution of a lock block after a certain amount of time" do
      expect do
        ActsAsReplaceable::HelperMethods.lock(@record, 1.seconds) { sleep 3 }
      end.to raise_exception(Timeout::Error)
    end
  end

  describe "when saving a record" do
    it "should raise an exception if more than one duplicate exists in the database" do
      insert_model(Material, :name => 'wood')
      insert_model(Material, :name => 'wood')
      lambda {Material.create! :name => 'wood'}.should raise_exception
    end

    it "should raise an exception when matching against multiple fields" do
      insert_model(Item, :identification_number => '1234', :holding_institution_id => 1)
      insert_model(Item, :identification_number => '1234', :holding_institution_id => 1)
      lambda {Item.create! :identification_number => '1234', :holding_institution_id => 1}.should raise_exception
    end

    it "should replace itself with an existing record by matching a single column" do
      Material.create! :name => 'wood'
      Material.create! :name => 'wood'
      Material.where(:name => 'wood').count.should == 1
    end

    it "should replace itself with an existing record by matching multiple columns" do
      Location.create! :country => 'Canada', :city => 'Vancouver'
      Location.create! :country => 'Canada', :city => 'Vancouver'
      Location.where(:country => 'Canada', :city => 'Vancouver').count.should == 1
    end

    it "should replace itself with an existing record by matching multiple columns and inheriting a column from the existing record" do
      a = Item.create! :name => 'Stick', :identification_number => '1234', :holding_institution_id => 1, :collection_id => 2,  :fingerprint => 'asdf'
      b = Item.create! :name => 'Stick', :identification_number => '1234', :holding_institution_id => 1, :collection_id => 2
      Item.where(:identification_number => '1234', :holding_institution_id => 1, :collection_id => 2).count.should == 1
      b.fingerprint.should == 'asdf'
    end

    it "should update the non-match, non-inherit fields of the existing record" do
      a = Item.create! :name => 'Stick', :identification_number => '1234', :holding_institution_id => 1, :collection_id => 2,  :fingerprint => 'asdf'
      b = Item.create! :name => 'Dip Stick', :identification_number => '1234', :holding_institution_id => 1, :collection_id => 2
      c = Item.where(:identification_number => '1234', :holding_institution_id => 1, :collection_id => 2)
      c.count.should == 1
      c.first.name.should == 'Dip Stick'
    end

    it "should correctly replace an existing record when a match value is nil" do
      a = Item.create! :name => 'Stick', :identification_number => '1234', :holding_institution_id => 1
      b = Item.create! :name => 'Dip Stick', :identification_number => '1234', :holding_institution_id => 1
      Item.where(:identification_number => '1234', :holding_institution_id => 1).count.should == 1
    end

    it "should replace itself with an existing record by performing case-insensitive matching on multiple columns" do
      Person.create! :first_name => 'John', :last_name => 'Doe'
      Person.create! :first_name => 'joHn', :last_name => 'doE'
      Person.where(:first_name => 'John', :last_name => 'Doe').count.should == 1

      Person.create! :first_name => 'Alanson', :last_name => 'Skinner'
      Person.create! :first_name => 'Alanson', :last_name => 'Skinner'
      Person.where(:first_name => 'Alanson', :last_name => 'Skinner').count.should == 1
    end

    it "should not replace an existing record with fields that were used to match" do
      Person.create! :first_name => 'joHn', :last_name => 'doE'
      Person.create! :first_name => 'John', :last_name => 'Doe'
      Person.where(:first_name => 'joHn', :last_name => 'doE').count.should == 1
      Person.where(:first_name => 'John', :last_name => 'Doe').count.should == 0
    end

    it "should correctly replace an existing record when an insensitive-match value is nil" do
      a = Person.create! :first_name => 'John'
      a = Person.create! :first_name => 'John'
      Person.where(:first_name => 'John').count.should == 1
    end

    it "should correctly detect difference between blank and nil values" do
      a = Person.create! :first_name => 'John', :last_name => ''
      a = Person.create! :first_name => 'John', :last_name => nil
      Person.where(:first_name => 'John').count.should == 2
    end

    it "should inherit the id of the existing record" do
      a = Material.create! :name => 'wood'
      b = Material.create! :name => 'wood'
      b.id.should == a.id
    end

    it "should not be a new_record? if it has replaced an existing record" do
      a = Material.create! :name => 'wood'
      b = Material.create! :name => 'wood'
      b.new_record?.should be_falsey
    end

    it "should be persisted? if it has replaced an existing record" do
      a = Material.create! :name => 'wood'
      b = Material.create! :name => 'wood'
      b.persisted?.should be_truthy
    end

    # CONCURRENCY

    it "should raise an exception if concurrency is enabled but Rails.cache doesn't support the :increment method" do
      ActsAsReplaceable.concurrency = true
      old_cache = Rails.cache
      Rails.cache = Object.new

      begin
        expect do
          class TestClass < ActiveRecord::Base
            self.table_name = Material.table_name
            acts_as_replaceable
          end
        end.to raise_exception(ActsAsReplaceable::LockingUnavailable)
      ensure
        Rails.cache = old_cache
      end
    end

    it "should use locking if concurrency is enabled" do
      ActsAsReplaceable.concurrency = true
      ActsAsReplaceable::HelperMethods.should_receive(:lock).once
      Material.create! :name => 'wood'
    end

    it "should not use locking if concurrency is disabled" do
      ActsAsReplaceable.concurrency = false
      ActsAsReplaceable::HelperMethods.should_not_receive(:lock)
      Material.create! :name => 'wood'
    end
  end
end
